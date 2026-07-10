from fastapi import APIRouter, File, UploadFile

from schemas import ImageUploadResponse
from services.ocr_service import recognize_answer_text, save_upload

router = APIRouter(prefix="/grading", tags=["grading"])


@router.post("/upload-image", response_model=ImageUploadResponse)
async def upload_image(file: UploadFile = File(...)) -> ImageUploadResponse:
    image_url, target = await save_upload(file)
    ocr_text = await recognize_answer_text(target)
    return ImageUploadResponse(ocr_text=ocr_text, image_url=image_url)
