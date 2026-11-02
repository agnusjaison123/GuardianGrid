from __future__ import annotations

from dataclasses import dataclass

import httpx

from app.core.config import get_settings


@dataclass(frozen=True)
class WeatherSnapshot:
    condition: str
    multiplier: float
    source: str


class WeatherService:
    def __init__(self) -> None:
        self.settings = get_settings()

    async def get_weather_snapshot(self, lat: float, lng: float) -> WeatherSnapshot:
        if self.settings.openweather_api_key:
            snapshot = await self._try_openweather(lat, lng)
            if snapshot is not None:
                return snapshot

        snapshot = await self._try_open_meteo(lat, lng)
        if snapshot is not None:
            return snapshot

        return WeatherSnapshot(
            condition="clear (fallback)",
            multiplier=1.0,
            source="fallback",
        )

    async def _try_openweather(self, lat: float, lng: float) -> WeatherSnapshot | None:
        params = {
            "lat": lat,
            "lon": lng,
            "appid": self.settings.openweather_api_key,
            "units": "metric",
        }
        url = f"{self.settings.openweather_base_url}/weather"

        timeout = httpx.Timeout(self.settings.request_timeout_s)
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.get(url, params=params)
            if response.status_code != 200:
                return None

            payload = response.json()
            weather = payload.get("weather", [])
            first = weather[0] if isinstance(weather, list) and weather else {}
            weather_id = int(first.get("id", 800))
            description = str(first.get("description", "clear"))

            multiplier = self._openweather_multiplier(weather_id, description)
            return WeatherSnapshot(
                condition=description,
                multiplier=multiplier,
                source="openweather",
            )
        except (ValueError, TypeError, httpx.HTTPError):
            return None

    async def _try_open_meteo(self, lat: float, lng: float) -> WeatherSnapshot | None:
        url = f"{self.settings.open_meteo_base_url}/forecast"
        params = {
            "latitude": lat,
            "longitude": lng,
            "current": "weather_code,precipitation",
            "timezone": "auto",
        }

        timeout = httpx.Timeout(self.settings.request_timeout_s)
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.get(url, params=params)
            if response.status_code != 200:
                return None

            payload = response.json()
            current = payload.get("current", {})
            weather_code = int(current.get("weather_code", 0))
            precipitation = float(current.get("precipitation", 0.0))

            multiplier = self._open_meteo_multiplier(weather_code, precipitation)
            condition = self._open_meteo_label(weather_code)
            return WeatherSnapshot(
                condition=condition,
                multiplier=multiplier,
                source="open-meteo",
            )
        except (ValueError, TypeError, httpx.HTTPError):
            return None

    def _openweather_multiplier(self, weather_id: int, description: str) -> float:
        desc = description.lower()
        if "flood" in desc:
            return 2.0
        if 502 <= weather_id <= 531 or 200 <= weather_id <= 232 or 600 <= weather_id <= 622:
            return 1.5
        if 300 <= weather_id <= 321 or 500 <= weather_id <= 501 or 701 <= weather_id <= 781:
            return 1.2
        return 1.0

    def _open_meteo_multiplier(self, weather_code: int, precipitation: float) -> float:
        if weather_code >= 95:
            return 2.0
        if weather_code in {65, 67, 75, 82, 86}:  # heavy rain/showers/snow
            return 1.5
        if weather_code in {51, 53, 55, 56, 57, 61, 63, 66, 80, 81} or precipitation > 0:
            return 1.2
        return 1.0

    def _open_meteo_label(self, weather_code: int) -> str:
        mapping = {
            0: "clear sky",
            1: "mainly clear",
            2: "partly cloudy",
            3: "overcast",
            45: "fog",
            48: "depositing rime fog",
            51: "light drizzle",
            53: "drizzle",
            55: "dense drizzle",
            61: "light rain",
            63: "rain",
            65: "heavy rain",
            80: "light rain showers",
            81: "rain showers",
            82: "violent rain showers",
            95: "thunderstorm",
        }
        return mapping.get(weather_code, f"weather code {weather_code}")