from __future__ import annotations

from pydantic import BaseModel, Field


class RouteSafeRequest(BaseModel):
    origin_lat: float = Field(..., ge=-90, le=90)
    origin_lng: float = Field(..., ge=-180, le=180)
    dest_lat: float = Field(..., ge=-90, le=90)
    dest_lng: float = Field(..., ge=-180, le=180)


class RiskBreakdownResponse(BaseModel):
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


class RouteOptionResponse(BaseModel):
    polyline: list[list[float]]
    risk_score: float
    eta: str
    risk_breakdown: RiskBreakdownResponse


class RouteSafeResponse(BaseModel):
    routes: list[RouteOptionResponse]


class EmergencyContactPayload(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    phone: str | None = Field(default=None, max_length=40)
    email: str | None = Field(default=None, max_length=320)


class EmergencyAlertRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    contacts: list[EmergencyContactPayload] = Field(default_factory=list)


class EmergencyAlertResponse(BaseModel):
    sent: int
    failed: int
    dry_run: bool
    message: str | None = None


class HealthResponse(BaseModel):
    status: str
