from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auth import verify_token
from app.models.schemas import (
    RiskBreakdownResponse,
    RouteOptionResponse,
    RouteSafeRequest,
    RouteSafeResponse,
)
from app.services.osrm_service import OsrmService, OsrmServiceError
from app.services.risk_scoring_service import ScoredRoute, RiskScoringService


router = APIRouter(tags=["navigation"])
osrm_service = OsrmService()
risk_scoring_service = RiskScoringService()


@router.post("/route/safe", response_model=RouteSafeResponse)
async def get_safe_routes(
    payload: RouteSafeRequest,
    uid: str = Depends(verify_token),
) -> RouteSafeResponse:
    del uid

    if payload.origin_lat == payload.dest_lat and payload.origin_lng == payload.dest_lng:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Origin and destination cannot be identical.",
        )

    try:
        candidates = await osrm_service.get_candidate_routes(
            origin_lat=payload.origin_lat,
            origin_lng=payload.origin_lng,
            dest_lat=payload.dest_lat,
            dest_lng=payload.dest_lng,
        )
        scored_routes = await risk_scoring_service.score_routes(candidates)
        return RouteSafeResponse(routes=[_to_response(route) for route in scored_routes])
    except OsrmServiceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to compute safe routes: {exc}",
        ) from exc


def _to_response(route: ScoredRoute) -> RouteOptionResponse:
    return RouteOptionResponse(
        polyline=[[lat, lng] for lat, lng in route.coordinates],
        risk_score=route.risk_score,
        eta=route.eta,
        risk_breakdown=RiskBreakdownResponse(
            base_score=route.breakdown.base_score,
            weather_multiplier=route.breakdown.weather_multiplier,
            traffic_multiplier=route.breakdown.traffic_multiplier,
            school_bonus=route.breakdown.school_bonus,
            historical_bonus=route.breakdown.historical_bonus,
            weather_condition=route.breakdown.weather_condition,
            weather_source=route.breakdown.weather_source,
            traffic_level=route.breakdown.traffic_level,
            traffic_source=route.breakdown.traffic_source,
            nearby_hazards=route.breakdown.nearby_hazards,
        ),
    )