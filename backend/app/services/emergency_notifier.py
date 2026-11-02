from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import logging

import anyio

from app.core.config import get_settings
from app.services.emergency_intel_service import EmergencyIntelService


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class EmergencyContact:
    name: str
    phone: str | None
    email: str | None


@dataclass(frozen=True)
class EmergencyDispatchResult:
    sent: int
    failed: int
    dry_run: bool
    errors: tuple[str, ...] = ()
    intel_summary: str | None = None


class EmergencyNotifier:
    def __init__(self) -> None:
        self.settings = get_settings()
        self._intel_service = EmergencyIntelService()

    async def dispatch(
        self,
        *,
        uid: str,
        latitude: float,
        longitude: float,
        contacts: list[EmergencyContact],
    ) -> EmergencyDispatchResult:
        if not contacts:
            return EmergencyDispatchResult(
                sent=0,
                failed=0,
                dry_run=self.settings.emergency_dry_run,
            )

        sent = 0
        failed = 0
        errors: list[str] = []
        intel_summary = await self._intel_service.build_nearby_help_summary(
            latitude=latitude,
            longitude=longitude,
        )

        map_link = f"https://maps.google.com/?q={latitude:.6f},{longitude:.6f}"
        timestamp = datetime.now(timezone.utc).isoformat()
        subject = "[EMERGENCY ALERT] Possible crash detected - GuardianGrid"
        body = (
            "GuardianGrid detected a possible crash.\n"
            f"Reporter UID: {uid}\n"
            f"Coordinates: {latitude:.6f}, {longitude:.6f}\n"
            f"Map: {map_link}\n"
            f"Time (UTC): {timestamp}\n"
            "\nPlease check on them immediately."
        )
        if intel_summary:
            body += f"\n\nNearby help:\n{intel_summary}"

        sms_text = (
            "GuardianGrid emergency alert: possible crash detected. "
            f"Location: {map_link}"
        )
        if intel_summary:
            sms_text = f"{sms_text}. {intel_summary}"

        for contact in contacts:
            email = (contact.email or "").strip()
            phone = (contact.phone or "").strip()
            channel_attempted = False
            channel_sent = False

            if email:
                channel_attempted = True
                ok, error = await anyio.to_thread.run_sync(
                    self._send_email,
                    email,
                    subject,
                    body,
                )
                channel_sent = channel_sent or ok
                if error:
                    errors.append(f"{contact.name} email: {error}")

            if phone:
                channel_attempted = True
                ok, error = await anyio.to_thread.run_sync(
                    self._send_sms,
                    phone,
                    sms_text,
                )
                channel_sent = channel_sent or ok
                if error:
                    errors.append(f"{contact.name} sms: {error}")

            if not channel_attempted:
                failed += 1
                errors.append(f"{contact.name}: no email or phone set")
            elif channel_sent:
                sent += 1
            else:
                failed += 1

        return EmergencyDispatchResult(
            sent=sent,
            failed=failed,
            dry_run=self.settings.emergency_dry_run,
            errors=tuple(errors),
            intel_summary=intel_summary,
        )

    def _send_email(
        self,
        to_email: str,
        subject: str,
        body: str,
    ) -> tuple[bool, str | None]:
        api_key = self.settings.sendgrid_api_key
        if not api_key:
            if self.settings.emergency_dry_run:
                logger.info("DRY-RUN email to %s: %s", to_email, subject)
                return True, None
            return False, "SENDGRID_API_KEY missing"

        try:
            from sendgrid import SendGridAPIClient
            from sendgrid.helpers.mail import Mail
        except Exception as exc:
            if self.settings.emergency_dry_run:
                logger.info("DRY-RUN email fallback to %s (%s)", to_email, exc)
                return True, None
            return False, f"sendgrid package unavailable: {exc}"

        try:
            client = SendGridAPIClient(api_key)
            message = Mail(
                from_email=self.settings.emergency_from_email,
                to_emails=to_email,
                subject=subject,
                plain_text_content=body,
            )
            response = client.send(message)
            if 200 <= response.status_code < 300:
                return True, None
            return False, f"sendgrid status {response.status_code}"
        except Exception as exc:
            if self.settings.emergency_dry_run:
                logger.info("DRY-RUN email error fallback to %s (%s)", to_email, exc)
                return True, None
            return False, str(exc)

    def _send_sms(self, to_phone: str, text: str) -> tuple[bool, str | None]:
        account_sid = self.settings.twilio_account_sid
        auth_token = self.settings.twilio_auth_token
        from_number = self.settings.twilio_from_number

        if not account_sid or not auth_token or not from_number:
            if self.settings.emergency_dry_run:
                logger.info("DRY-RUN sms to %s: %s", to_phone, text)
                return True, None
            return False, "Twilio credentials missing"

        try:
            from twilio.rest import Client
        except Exception as exc:
            if self.settings.emergency_dry_run:
                logger.info("DRY-RUN sms fallback to %s (%s)", to_phone, exc)
                return True, None
            return False, f"twilio package unavailable: {exc}"

        try:
            client = Client(account_sid, auth_token)
            message = client.messages.create(
                body=text,
                from_=from_number,
                to=to_phone,
            )
            if message.sid:
                return True, None
            return False, "Twilio did not return SID"
        except Exception as exc:
            if self.settings.emergency_dry_run:
                logger.info("DRY-RUN sms error fallback to %s (%s)", to_phone, exc)
                return True, None
            return False, str(exc)
