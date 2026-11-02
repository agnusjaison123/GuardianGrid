from __future__ import annotations

from dataclasses import dataclass
import math

import httpx

from app.core.config import get_settings


_OVERPASS_URL = "https://overpass-api.de/api/interpreter"


@dataclass(frozen=True)
class NearbyEmergencyPlace:
    kind: str
    name: str
    latitude: float
    longitude: float
    distance_m: float


class EmergencyIntelService:
    def __init__(self) -> None:
        self.settings = get_settings()

    async def build_nearby_help_summary(
        self,
        *,
        latitude: float,
        longitude: float,
    ) -> str | None:
        places = await self._fetch_nearby_places(latitude=latitude, longitude=longitude)
        if not places:
            return None

        nearest_police = next((place for place in places if place.kind == "police"), None)
        nearest_hospital = next((place for place in places if place.kind == "hospital"), None)

        parts: list[str] = []
        if nearest_police is not None:
            parts.append(f"Nearest police: {self._format_place(nearest_police)}.")
        if nearest_hospital is not None:
            parts.append(f"Nearest hospital: {self._format_place(nearest_hospital)}.")

        if not parts:
            return None
        return " ".join(parts)

    async def _fetch_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
    ) -> list[NearbyEmergencyPlace]:
        query = f"""
[out:json][timeout:25];
(
  node(around:5000,{latitude},{longitude})["amenity"~"^(police|hospital)$"];
  way(around:5000,{latitude},{longitude})["amenity"~"^(police|hospital)$"];
  relation(around:5000,{latitude},{longitude})["amenity"~"^(police|hospital)$"];
);
out center 25;
""".strip()

        timeout = httpx.Timeout(self.settings.request_timeout_s)
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(
                    _OVERPASS_URL,
                    data={"data": query},
                    headers={"User-Agent": "GuardianGrid/1.0"},
                )
            if response.status_code != 200:
                return []
            payload = response.json()
        except (httpx.HTTPError, ValueError, TypeError):
            return []

        places: list[NearbyEmergencyPlace] = []
        for element in payload.get("elements", []):
            if not isinstance(element, dict):
                continue

            tags = element.get("tags")
            if not isinstance(tags, dict):
                continue

            kind = str(tags.get("amenity", "")).strip().lower()
            if kind not in {"police", "hospital"}:
                continue

            lat = element.get("lat")
            lon = element.get("lon")
            if lat is None or lon is None:
                center = element.get("center")
                if isinstance(center, dict):
                    lat = center.get("lat")
                    lon = center.get("lon")

            try:
                place_lat = float(lat)
                place_lon = float(lon)
            except (TypeError, ValueError):
                continue

            name = str(tags.get("name", "")).strip()
            if not name:
                name = "Unnamed police station" if kind == "police" else "Unnamed hospital"

            places.append(
                NearbyEmergencyPlace(
                    kind=kind,
                    name=name,
                    latitude=place_lat,
                    longitude=place_lon,
                    distance_m=_distance_m(latitude, longitude, place_lat, place_lon),
                )
            )

        places.sort(key=lambda place: place.distance_m)
        return places

    def _format_place(self, place: NearbyEmergencyPlace) -> str:
        if place.distance_m >= 1000:
            distance = f"{place.distance_m / 1000:.1f} km"
        else:
            distance = f"{int(round(place.distance_m))} m"
        return f"{place.name} ({distance})"


def _distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(d_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    )
    return 2 * radius * math.atan2(math.sqrt(a), math.sqrt(1 - a))
