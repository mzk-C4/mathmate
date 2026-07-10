from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from database import JsonStore, get_store
from schemas import QuestionAdminOut, QuestionCreate, QuestionOut

router = APIRouter(prefix="/questions", tags=["questions"])


@router.get("", response_model=list[QuestionOut])
def list_questions(
    board: str | None = None,
    question_type: str | None = None,
    difficulty_min: Decimal | None = Query(default=None, ge=0, le=1),
    difficulty_max: Decimal | None = Query(default=None, ge=0, le=1),
    store: JsonStore = Depends(get_store),
) -> list[dict[str, Any]]:
    return store.list_questions(
        board=board,
        question_type=question_type,
        difficulty_min=difficulty_min,
        difficulty_max=difficulty_max,
    )


@router.post("", response_model=QuestionAdminOut, status_code=201)
def create_question(
    payload: QuestionCreate,
    store: JsonStore = Depends(get_store),
) -> dict[str, Any]:
    try:
        return store.create_question(payload.model_dump())
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
