from __future__ import annotations

from fastapi import Header, HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import exceptions as firebase_exceptions

from .config import get_settings
from .firebase_admin import FirebaseInitializationError, get_firebase_app


async def verify_token(authorization: str | None = Header(default=None)) -> str:
    settings = get_settings()
    if settings.auth_bypass_local:
        return "local-dev-user"

    if authorization is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header.",
        )

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header must be in format: Bearer <token>",
        )

    token = authorization.replace("Bearer ", "", 1).strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Firebase ID token.",
        )

    try:
        get_firebase_app()
        decoded = firebase_auth.verify_id_token(token)
        uid = decoded.get("uid")
        if not uid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token is valid but UID is missing.",
            )
        return uid
    except FirebaseInitializationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except (ValueError, firebase_auth.InvalidIdTokenError, firebase_auth.ExpiredIdTokenError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token.",
        )
    except firebase_exceptions.FirebaseError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Firebase token verification failed: {exc}",
        ) from exc
