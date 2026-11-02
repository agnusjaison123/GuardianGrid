from __future__ import annotations

from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

from .config import get_settings


class FirebaseInitializationError(RuntimeError):
    """Raised when Firebase Admin initialization fails."""


def get_firebase_app() -> firebase_admin.App:
    try:
        return firebase_admin.get_app()
    except ValueError:
        settings = get_settings()
        service_account_path = Path(settings.firebase_service_account_path)
        if not service_account_path.is_absolute():
            service_account_path = Path.cwd() / service_account_path

        if not service_account_path.exists():
            raise FirebaseInitializationError(
                f"Firebase service account file not found at {service_account_path}."
            )

        cred = credentials.Certificate(str(service_account_path))
        options: dict[str, str] = {}
        if settings.firebase_project_id:
            options["projectId"] = settings.firebase_project_id

        return firebase_admin.initialize_app(cred, options=options or None)


def get_firestore_client() -> firestore.Client:
    app = get_firebase_app()
    return firestore.client(app=app)