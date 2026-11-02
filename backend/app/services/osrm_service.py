from __future__ import annotations

from dataclasses import dataclass

import httpx

from app.core.config import get_settings


class OsrmServiceError(RuntimeError):
    """Raised when OSRM route generation fails."""


@dataclass(frozen=True)
class RouteCandidate:
    route_index: int
    coordinates: list[tuple[float, float]]
    duration_seconds: float
    distance_meters: float


class OsrmService:
    def __init__(self) -> None:
        self.settings = get_settings()

    async def get_candidate_routes(
        self,
        origin_lat: float,
        origin_lng: float,
        dest_lat: float,
        dest_lng: float,
    ) -> list[RouteCandidate]:
        max_routes = max(1, self.settings.max_osrm_routes)
        url = (
            f"{self.settings.osrm_base_url}/route/v1/driving/"
            f"{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
        )
        base_params = {
            # Ask OSRM for up to max_routes route options.
            "alternatives": str(max_routes),
            "overview": "full",
            "steps": "false",
            "geometries": "geojson",
        }

        timeout = httpx.Timeout(self.settings.request_timeout_s)
        async with httpx.AsyncClient(timeout=timeout) as client:
            primary_payload = await self._request_payload(client, url, base_params)

            routes = primary_payload.get("routes")
            if not isinstance(routes, list) or not routes:
                raise OsrmServiceError("OSRM returned no route candidates.")

            candidates: list[RouteCandidate] = []
            signatures: set[str] = set()
            route_index = 0

            route_index = self._append_candidates_from_routes(
                routes=routes,
                route_index_start=route_index,
                target=candidates,
                signatures=signatures,
                max_routes=max_routes,
            )

            # Fallback: request extra variants with different exclusions when
            # the primary alternatives call still returns only one option.
            if len(candidates) < max_routes:
                for exclusion in ("motorway", "toll", "ferry"):
                    params = {
                        **base_params,
                        "alternatives": "false",
                        "exclude": exclusion,
                    }
                    try:
                        payload = await self._request_payload(client, url, params)
                    except OsrmServiceError:
                        continue

                    raw = payload.get("routes")
                    if not isinstance(raw, list) or not raw:
                        continue

                    route_index = self._append_candidates_from_routes(
                        routes=raw[:1],
                        route_index_start=route_index,
                        target=candidates,
                        signatures=signatures,
                        max_routes=max_routes,
                    )
                    if len(candidates) >= max_routes:
                        break

        if not candidates:
            raise OsrmServiceError("OSRM returned routes without usable geometry.")

        return candidates

    async def _request_payload(
        self,
        client: httpx.AsyncClient,
        url: str,
        params: dict[str, str],
    ) -> dict:
        response = await client.get(url, params=params)
        if response.status_code != 200:
            raise OsrmServiceError(
                f"OSRM request failed with status {response.status_code}: {response.text}"
            )

        payload = response.json()
        if payload.get("code") != "Ok":
            raise OsrmServiceError(f"OSRM returned error payload: {payload}")

        if not isinstance(payload, dict):
            raise OsrmServiceError("OSRM returned non-object payload.")
        return payload

    def _append_candidates_from_routes(
        self,
        routes: list,
        route_index_start: int,
        target: list[RouteCandidate],
        signatures: set[str],
        max_routes: int,
    ) -> int:
        route_index = route_index_start

        for route in routes:
            if len(target) >= max_routes:
                break
            if not isinstance(route, dict):
                continue

            geometry = route.get("geometry", {})
            if not isinstance(geometry, dict):
                continue

            raw_coords = geometry.get("coordinates")
            if not isinstance(raw_coords, list):
                continue

            coordinates: list[tuple[float, float]] = []
            for pair in raw_coords:
                if not isinstance(pair, list) or len(pair) != 2:
                    continue
                lng, lat = pair
                coordinates.append((float(lat), float(lng)))

            if not coordinates:
                continue

            signature = self._route_signature(coordinates)
            if signature in signatures:
                continue

            duration = float(route.get("duration", 0.0))
            distance = float(route.get("distance", 0.0))
            target.append(
                RouteCandidate(
                    route_index=route_index,
                    coordinates=coordinates,
                    duration_seconds=duration,
                    distance_meters=distance,
                )
            )
            signatures.add(signature)
            route_index += 1

        return route_index

    def _route_signature(self, coordinates: list[tuple[float, float]]) -> str:
        first = coordinates[0]
        midpoint = coordinates[len(coordinates) // 2]
        last = coordinates[-1]
        return (
            f"{len(coordinates)}|"
            f"{first[0]:.5f},{first[1]:.5f}|"
            f"{midpoint[0]:.5f},{midpoint[1]:.5f}|"
            f"{last[0]:.5f},{last[1]:.5f}"
        )
