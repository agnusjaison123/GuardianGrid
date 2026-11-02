from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.auth import verify_token
from app.models.schemas import (
    EmergencyAlertRequest,
    EmergencyAlertResponse,
)
from app.services.emergency_notifier import EmergencyContact, EmergencyNotifier


router = APIRouter(tags=["emergency"])
notifier = EmergencyNotifier()


@router.post("/emergency/alert", response_model=EmergencyAlertResponse)
async def send_emergency_alert(
    payload: EmergencyAlertRequest,
    uid: str = Depends(verify_token),
) -> EmergencyAlertResponse:
    contacts = [
        EmergencyContact(
            name=contact.name.strip(),
            phone=(contact.phone or "").strip() or None,
            email=(contact.email or "").strip() or None,
        )
        for contact in payload.contacts
    ]

    result = await notifier.dispatch(
        uid=uid,
        latitude=payload.latitude,
        longitude=payload.longitude,
        contacts=contacts,
    )

    message_parts: list[str] = []
    if result.intel_summary:
        message_parts.append(result.intel_summary)
    if result.errors:
        message_parts.append("; ".join(result.errors[:3]))

    message = " | ".join(message_parts) if message_parts else None

    return EmergencyAlertResponse(
        sent=result.sent,
        failed=result.failed,
        dry_run=result.dry_run,
        message=message,
    )
