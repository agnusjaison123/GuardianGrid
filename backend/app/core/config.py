from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import os
from pathlib import Path

from dotenv import load_dotenv


_ENV_PATH = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=_ENV_PATH)


@dataclass(frozen=True)
class Settings:
    app_name: str
    host: str
    port: int
    osrm_base_url: str
    openweather_api_key: str
    openweather_base_url: str
    open_meteo_base_url: str
    tomtom_api_key: str
    tomtom_base_url: str
    firebase_service_account_path: str
    firebase_project_id: str
    emergency_from_email: str
    sendgrid_api_key: str
    twilio_account_sid: str
    twilio_auth_token: str
    twilio_from_number: str
    emergency_dry_run: bool
    auth_bypass_local: bool
    firestore_hazards_collection: str
    risk_hazard_radius_meters: float
    school_zone_bonus: float
    historical_bonus: float
    historical_window_days: int
    school_zone_active_start_hour: int
    school_zone_active_end_hour: int
    request_timeout_s: float
    max_osrm_routes: int
    default_fallback_lat: float
    default_fallback_lng: float


@lru_cache
def get_settings() -> Settings:
    emergency_dry_run_raw = os.getenv("EMERGENCY_DRY_RUN", "true").strip().lower()
    auth_bypass_local_raw = os.getenv("AUTH_BYPASS_LOCAL", "false").strip().lower()
    return Settings(
        app_name=os.getenv("APP_NAME", "GuardianGrid API"),
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8000")),
        osrm_base_url=os.getenv("OSRM_BASE_URL", "https://router.project-osrm.org").rstrip("/"),
        openweather_api_key=os.getenv("OPENWEATHER_API_KEY", "").strip(),
        openweather_base_url=os.getenv("OPENWEATHER_BASE_URL", "https://api.openweathermap.org/data/2.5").rstrip("/"),
        open_meteo_base_url=os.getenv("OPEN_METEO_BASE_URL", "https://api.open-meteo.com/v1").rstrip("/"),
        tomtom_api_key=os.getenv("TOMTOM_API_KEY", "").strip(),
        tomtom_base_url=os.getenv("TOMTOM_BASE_URL", "https://api.tomtom.com/traffic/services/4").rstrip("/"),
        firebase_service_account_path=os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "firebase-service-account.json"),
        firebase_project_id=os.getenv("FIREBASE_PROJECT_ID", "").strip(),
        emergency_from_email=os.getenv("EMERGENCY_FROM_EMAIL", "noreply@guardiangrid.local").strip(),
        sendgrid_api_key=os.getenv("SENDGRID_API_KEY", "").strip(),
        twilio_account_sid=os.getenv("TWILIO_ACCOUNT_SID", "").strip(),
        twilio_auth_token=os.getenv("TWILIO_AUTH_TOKEN", "").strip(),
        twilio_from_number=os.getenv("TWILIO_FROM_NUMBER", "").strip(),
        emergency_dry_run=emergency_dry_run_raw in {"1", "true", "yes", "on"},
        auth_bypass_local=auth_bypass_local_raw in {"1", "true", "yes", "on"},
        firestore_hazards_collection=os.getenv("FIRESTORE_HAZARDS_COLLECTION", "hazard_reports"),
        risk_hazard_radius_meters=float(os.getenv("RISK_HAZARD_RADIUS_METERS", "100")),
        school_zone_bonus=float(os.getenv("SCHOOL_ZONE_BONUS", "15")),
        historical_bonus=float(os.getenv("HISTORICAL_BONUS", "10")),
        historical_window_days=int(os.getenv("HISTORICAL_WINDOW_DAYS", "90")),
        school_zone_active_start_hour=int(os.getenv("SCHOOL_ZONE_ACTIVE_START_HOUR", "7")),
        school_zone_active_end_hour=int(os.getenv("SCHOOL_ZONE_ACTIVE_END_HOUR", "16")),
        request_timeout_s=float(os.getenv("REQUEST_TIMEOUT_S", "20")),
        max_osrm_routes=int(os.getenv("MAX_OSRM_ROUTES", "3")),
        default_fallback_lat=float(os.getenv("DEFAULT_FALLBACK_LAT", "12.9716")),
        default_fallback_lng=float(os.getenv("DEFAULT_FALLBACK_LNG", "77.5946")),
    )
