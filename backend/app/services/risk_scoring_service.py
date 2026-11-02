from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json

import anyio

from app.core.config import get_settings
from app.core.firebase_admin import FirebaseInitializationError, get_firestore_client
from app.services.geo import point_to_polyline_distance_m
from app.services.osrm_service import RouteCandidate
from app.services.traffic_service import TrafficService
from app.services.weather_service import WeatherService


@dataclass(frozen=True)
class HazardPoint:
    latitude: float
    longitude: float
    severity: str


@dataclass(frozen=True)
class SchoolZone:
    latitude: float
    longitude: float
    radius_meters: float


@dataclass(frozen=True)
class IncidentRecord:
    latitude: float
    longitude: float
    recorded_at: datetime


@dataclass(frozen=True)
class RouteRiskBreakdown:
    base_score: float
    weather_multiplier: float
    traffic_multiplier: float
    school_bonus: float
    historical_bonus: float
    weather_condition: str
    weather_source: str
    traffic_level: str
    traffic_source: str
    nearby_hazards: int


@dataclass(frozen=True)
class ScoredRoute:
    coordinates: list[tuple[float, float]]
    risk_score: float
    eta: str
    breakdown: RouteRiskBreakdown


class RiskScoringService:
    _severity_weights = {
        "low": 10.0,
        "medium": 25.0,
        "high": 50.0,
        "critical": 100.0,
    }

    def __init__(self) -> None:
        self.settings = get_settings()
        self.weather_service = WeatherService()
        self.traffic_service = TrafficService()
        self.school_zones = self._load_school_zones()
        self.incidents = self._load_incidents()

    async def score_routes(self, routes: list[RouteCandidate]) -> list[ScoredRoute]:
        if not routes:
            return []

        hazards = await self._fetch_active_hazards()
        scored: list[ScoredRoute] = []

        for route in routes:
            midpoint_lat, midpoint_lng = _route_midpoint(route.coordinates)
            weather = await self.weather_service.get_weather_snapshot(
                midpoint_lat,
                midpoint_lng,
            )
            traffic = await self.traffic_service.get_traffic_snapshot(
                midpoint_lat,
                midpoint_lng,
            )

            nearby_hazards = self._nearby_hazards(route.coordinates, hazards)
            base_score = self._base_hazard_score(nearby_hazards)
            school_bonus = self._school_zone_bonus(route.coordinates)
            historical_bonus = self._historical_bonus(route.coordinates)

            raw_score = (
                base_score * weather.multiplier * traffic.multiplier
                + school_bonus
                + historical_bonus
            )
            bounded_score = max(0.0, min(100.0, raw_score))

            scored.append(
                ScoredRoute(
                    coordinates=route.coordinates,
                    risk_score=round(bounded_score, 2),
                    eta=_format_eta(route.duration_seconds),
                    breakdown=RouteRiskBreakdown(
                        base_score=round(base_score, 2),
                        weather_multiplier=weather.multiplier,
                        traffic_multiplier=traffic.multiplier,
                        school_bonus=school_bonus,
                        historical_bonus=historical_bonus,
                        weather_condition=weather.condition,
                        weather_source=weather.source,
                        traffic_level=traffic.level,
                        traffic_source=traffic.source,
                        nearby_hazards=len(nearby_hazards),
                    ),
                )
            )

        scored.sort(key=lambda route: route.risk_score)
        max_routes = max(1, self.settings.max_osrm_routes)
        return scored[:max_routes]

    async def _fetch_active_hazards(self) -> list[HazardPoint]:
        try:
            return await anyio.to_thread.run_sync(self._fetch_active_hazards_sync)
        except FirebaseInitializationError:
            return []
        except Exception:
            return []

    def _fetch_active_hazards_sync(self) -> list[HazardPoint]:
        db = get_firestore_client()
        now_utc = datetime.now(timezone.utc)

        docs = db.collection(self.settings.firestore_hazards_collection).stream()
        hazards: list[HazardPoint] = []

        for doc in docs:
            data = doc.to_dict() or {}
            status = str(data.get("status", "")).lower()
            if status != "verified":
                continue

            expires_at = data.get("expires_at")
            if expires_at is not None:
                expires_at_dt = _normalize_datetime(expires_at)
                if expires_at_dt is not None and expires_at_dt < now_utc:
                    continue

            location = data.get("location")
            if location is None or not hasattr(location, "latitude"):
                continue

            severity = str(data.get("severity", "low")).lower()
            hazards.append(
                HazardPoint(
                    latitude=float(location.latitude),
                    longitude=float(location.longitude),
                    severity=severity,
                )
            )

        return hazards

    def _nearby_hazards(
        self,
        route_coords: list[tuple[float, float]],
        hazards: list[HazardPoint],
    ) -> list[HazardPoint]:
        nearby: list[HazardPoint] = []
        for hazard in hazards:
            distance = point_to_polyline_distance_m(
                point_lat=hazard.latitude,
                point_lng=hazard.longitude,
                polyline=route_coords,
            )
            if distance <= self.settings.risk_hazard_radius_meters:
                nearby.append(hazard)
        return nearby

    def _base_hazard_score(self, nearby_hazards: list[HazardPoint]) -> float:
        return sum(
            self._severity_weights.get(hazard.severity, self._severity_weights["low"])
            for hazard in nearby_hazards
        )

    def _school_zone_bonus(self, route_coords: list[tuple[float, float]]) -> float:
        if not self.school_zones:
            return 0.0
        if not _is_school_time(
            start_hour=self.settings.school_zone_active_start_hour,
            end_hour=self.settings.school_zone_active_end_hour,
        ):
            return 0.0

        for zone in self.school_zones:
            distance = point_to_polyline_distance_m(
                point_lat=zone.latitude,
                point_lng=zone.longitude,
                polyline=route_coords,
            )
            if distance <= zone.radius_meters:
                return self.settings.school_zone_bonus

        return 0.0

    def _historical_bonus(self, route_coords: list[tuple[float, float]]) -> float:
        if not self.incidents:
            return 0.0

        threshold = datetime.now(timezone.utc) - timedelta(
            days=self.settings.historical_window_days
        )
        nearby_recent = 0
        for incident in self.incidents:
            if incident.recorded_at < threshold:
                continue
            distance = point_to_polyline_distance_m(
                point_lat=incident.latitude,
                point_lng=incident.longitude,
                polyline=route_coords,
            )
            if distance <= self.settings.risk_hazard_radius_meters:
                nearby_recent += 1

        return self.settings.historical_bonus if nearby_recent >= 3 else 0.0

    def _load_school_zones(self) -> list[SchoolZone]:
        root = Path(__file__).resolve().parents[2]
        file_path = root / "data" / "school_zones.json"
        if not file_path.exists():
            return []

        try:
            raw = json.loads(file_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return []

        zones: list[SchoolZone] = []
        for item in raw if isinstance(raw, list) else []:
            try:
                zones.append(
                    SchoolZone(
                        latitude=float(item["latitude"]),
                        longitude=float(item["longitude"]),
                        radius_meters=float(item.get("radius_meters", 200.0)),
                    )
                )
            except (KeyError, TypeError, ValueError):
                continue

        return zones

    def _load_incidents(self) -> list[IncidentRecord]:
        root = Path(__file__).resolve().parents[2]
        file_path = root / "data" / "incidents.json"
        if not file_path.exists():
            return []

        try:
            raw = json.loads(file_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return []

        incidents: list[IncidentRecord] = []
        for item in raw if isinstance(raw, list) else []:
            try:
                recorded_at = _parse_iso_datetime(str(item["recorded_at"]))
                incidents.append(
                    IncidentRecord(
                        latitude=float(item["latitude"]),
                        longitude=float(item["longitude"]),
                        recorded_at=recorded_at,
                    )
                )
            except (KeyError, TypeError, ValueError):
                continue

        return incidents


def _route_midpoint(coordinates: list[tuple[float, float]]) -> tuple[float, float]:
    if not coordinates:
        settings = get_settings()
        return settings.default_fallback_lat, settings.default_fallback_lng

    midpoint_index = len(coordinates) // 2
    midpoint = coordinates[midpoint_index]
    return midpoint[0], midpoint[1]


def _format_eta(duration_seconds: float) -> str:
    minutes = max(1, int(round(duration_seconds / 60.0)))
    if minutes >= 60:
        hours = minutes // 60
        remainder = minutes % 60
        if remainder == 0:
            return f"{hours}h"
        return f"{hours}h {remainder}m"
    return f"{minutes} min"


def _is_school_time(start_hour: int, end_hour: int) -> bool:
    now = datetime.now().hour
    return start_hour <= now < end_hour


def _parse_iso_datetime(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _normalize_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    return None
