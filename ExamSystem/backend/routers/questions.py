from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from auth import AuthUser, require_admin
from database import JsonStore, get_store
from schemas import (
    QuestionAdminOut,
    QuestionCreate,
    QuestionImportRequest,
    QuestionImportResponse,
    QuestionOut,
)

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
    _admin: AuthUser = Depends(require_admin),
    store: JsonStore = Depends(get_store),
) -> dict[str, Any]:
    try:
        return store.create_question(payload.model_dump())
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@router.post("/import", response_model=QuestionImportResponse)
def import_questions(
    payload: QuestionImportRequest,
    _admin: AuthUser = Depends(require_admin),
    store: JsonStore = Depends(get_store),
) -> QuestionImportResponse:
    questions = [question.model_dump() for question in payload.questions]
    codes = [str(question["question_code"]) for question in questions]
    existing = {str(question["question_code"]) for question in store.list_questions()}
    duplicates = sorted(
        {code for code in codes if codes.count(code) > 1 or code in existing}
    )
    if duplicates:
        return QuestionImportResponse(
            dry_run=payload.dry_run,
            accepted_count=0,
            imported_count=0,
            duplicate_codes=duplicates,
        )
    if payload.dry_run:
        return QuestionImportResponse(
            dry_run=True,
            accepted_count=len(questions),
            imported_count=0,
        )
    try:
        created = store.create_questions(questions)
    except ValueError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return QuestionImportResponse(
        dry_run=False,
        accepted_count=len(created),
        imported_count=len(created),
    )
