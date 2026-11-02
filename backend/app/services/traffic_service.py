from __future__ import annotations

from dataclasses import dataclass

import httpx

from app.core.config import get_settings


@dataclass(frozen=True)
class TrafficSnapshot:
    level: str
    multiplier: float
    current_speed_kmh: float | None
    free_flow_speed_kmh: float | None
    source: str


class TrafficService:
    def __init__(self) -> None:
        self.settings = get_settings()

    async def get_traffic_snapshot(self, lat: float, lng: float) -> TrafficSnapshot:
        if not self.settings.tomtom_api_key:
            return TrafficSnapshot(
                level="low",
                multiplier=1.0,
                current_speed_kmh=None,
                free_flow_speed_kmh=None,
                source="default-no-key",
            )

        url = (
            f"{self.settings.tomtom_base_url}/flowSegmentData/relative0/10/json"
        )
        params = {
            "point": f"{lat},{lng}",
            "unit": "KMPH",
            "openLr": "false",
            "key": self.settings.tomtom_api_key,
        }

        timeout = httpx.Timeout(self.settings.request_timeout_s)
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.get(url, params=params)
            if response.status_code != 200:
                return self._fallback_snapshot(source=f"tomtom-http-{response.status_code}")

            payload = response.json()
            flow = payload.get("flowSegmentData", {})
            current = float(flow.get("currentSpeed", 0.0))
            free_flow = float(flow.get("freeFlowSpeed", 0.0))
            if free_flow <= 0:
                return self._fallback_snapshot(source="tomtom-no-speed")

            ratio = current / free_flow
            if ratio >= 0.8:
                return TrafficSnapshot(
                    level="low",
                    multiplier=1.0,
                    current_speed_kmh=current,
                    free_flow_speed_kmh=free_flow,
                    source="tomtom",
                )
            if ratio >= 0.5:
                return TrafficSnapshot(
                    level="medium",
                    multiplier=1.1,
                    current_speed_kmh=current,
                    free_flow_speed_kmh=free_flow,
                    source="tomtom",
                )
            return TrafficSnapshot(
                level="high",
                multiplier=1.3,
                current_speed_kmh=current,
                free_flow_speed_kmh=free_flow,
                source="tomtom",
            )
        except (ValueError, TypeError, httpx.HTTPError):
            return self._fallback_snapshot(source="tomtom-exception")

    def _fallback_snapshot(self, source: str) -> TrafficSnapshot:
        return TrafficSnapshot(
            level="low",
            multiplier=1.0,
            current_speed_kmh=None,
            free_flow_speed_kmh=None,
            source=source,
        )