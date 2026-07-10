from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile

from config import get_settings


async def save_upload(file: UploadFile) -> tuple[str, Path]:
    settings = get_settings()
    upload_dir = Path(settings.upload_dir)
    upload_dir.mkdir(parents=True, exist_ok=True)

    suffix = Path(file.filename or "").suffix.lower() or ".png"
    filename = f"answer_{uuid4().hex}{suffix}"
    target = upload_dir / filename

    content = await file.read()
    max_bytes = settings.max_upload_mb * 1024 * 1024
    if len(content) > max_bytes:
        raise HTTPException(status_code=413, detail=f"图片不能超过 {settings.max_upload_mb}MB")
    target.write_bytes(content)
    return f"/uploads/{filename}", target


async def recognize_answer_text(file_path: Path) -> str:
    settings = get_settings()
    if not settings.ocr_api_key or not settings.ocr_base_url:
        return ""
    # 这里预留 OCR 服务接入点。不同供应商入参差异较大，第一版先统一输出文本。
    return ""
