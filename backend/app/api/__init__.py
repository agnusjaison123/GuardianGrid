from fastapi import APIRouter

from app.api.routes import deepfake_router, emergency_router, health_router, route_router

api_router = APIRouter()
api_router.include_router(health_router)
api_router.include_router(route_router)
api_router.include_router(emergency_router)
api_router.include_router(deepfake_router)
