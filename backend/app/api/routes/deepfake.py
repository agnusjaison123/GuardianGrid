from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status

from app.core.auth import verify_token


router = APIRouter(tags=["media"])

_MODEL_NAME = "guardiangrid-demo-heuristic-v1"


@router.post("/media/deepfake/verify")
async def verify_deepfake(
    file: UploadFile | None = File(default=None),
    media_type: str | None = Form(default=None),
    photo: UploadFile | None = File(default=None),
    video: UploadFile | None = File(default=None),
    hazard_type: str | None = Form(default=None),
    severity: str | None = Form(default=None),
    location_text: str | None = Form(default=None),
    uid: str = Depends(verify_token),
) -> dict:
    del uid, hazard_type, severity, location_text

    if photo is not None and video is not None:
        photo_result = await _evaluate_media(photo, media_type="image")
        video_result = await _evaluate_media(video, media_type="video")
        is_deepfake = photo_result["is_deepfake"] or video_result["is_deepfake"]
        return {
            "photo": photo_result,
            "video": video_result,
            "is_deepfake": is_deepfake,
            "is_authentic": not is_deepfake,
            "confidence": min(photo_result["confidence"], video_result["confidence"]),
            "verdict": "deepfake" if is_deepfake else "real",
            "model": _MODEL_NAME,
        }

    if file is None:
        if photo is not None:
            file = photo
            media_type = "image"
        elif video is not None:
            file = video
            media_type = "video"

    if file is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Provide either file (+ media_type) or photo/video.",
        )

    normalized_type = (media_type or "").strip().lower()
    if normalized_type not in {"image", "video"}:
        filename = (file.filename or "").lower()
        if filename.endswith((".mp4", ".mov", ".mkv", ".avi", ".webm")):
            normalized_type = "video"
        else:
            normalized_type = "image"

    return await _evaluate_media(file, media_type=normalized_type)


async def _evaluate_media(upload: UploadFile, media_type: str) -> dict:
    content = await upload.read()
    filename = (upload.filename or "").strip() or f"{media_type}-upload"
    lowered = filename.lower()
    size_kb = max(1, len(content) // 1024)

    # Demo-safe heuristic:
    # - marks clearly suspicious file names as deepfake.
    # - keeps normal user captures as authentic so reporting flow works.
    suspicious_name_tokens = ("deepfake", "face-swap", "faceswap", "ai-fake", "fake")
    suspicious_by_name = any(token in lowered for token in suspicious_name_tokens)

    tiny_media_threshold_kb = 8 if media_type == "image" else 32
    suspicious_by_size = size_kb <= tiny_media_threshold_kb

    is_deepfake = suspicious_by_name or suspicious_by_size
    confidence = 0.93 if is_deepfake else 0.97
    verdict = "deepfake" if is_deepfake else "real"

    return {
        "is_deepfake": is_deepfake,
        "is_authentic": not is_deepfake,
        "confidence": confidence,
        "verdict": verdict,
        "media_type": media_type,
        "file_name": filename,
        "size_kb": size_kb,
        "model": _MODEL_NAME,
    }
