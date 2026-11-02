from app.api.routes.deepfake import router as deepfake_router
from app.api.routes.emergency import router as emergency_router
from app.api.routes.health import router as health_router
from app.api.routes.route import router as route_router

__all__ = ["health_router", "route_router", "emergency_router", "deepfake_router"]
