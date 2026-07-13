from decimal import Decimal
import random
from typing import Any

from fastapi import HTTPException

from database import JsonStore


def filter_questions(
    store: JsonStore,
    board: str | None = None,
    boards: list[str] | None = None,
    difficulty_min: Decimal | None = None,
    difficulty_max: Decimal | None = None,
    question_types: list[str] | None = None,
) -> list[dict[str, Any]]:
    questions = store.list_questions(
        board=board,
        difficulty_min=difficulty_min,
        difficulty_max=difficulty_max,
    )
    if boards:
        allowed_boards = set(boards)
        questions = [item for item in questions if item["board"] in allowed_boards]
    if question_types:
        questions = [item for item in questions if item["question_type"] in question_types]
    questions = [
        item for item in questions if str(item.get("standard_answer") or "").strip()
    ]
    return questions


def select_questions(
    store: JsonStore,
    total_count: int,
    board: str | None = None,
    boards: list[str] | None = None,
    difficulty_min: Decimal | None = None,
    difficulty_max: Decimal | None = None,
    question_types: list[str] | None = None,
) -> list[dict[str, Any]]:
    questions = filter_questions(
        store,
        board=board,
        boards=boards,
        difficulty_min=difficulty_min,
        difficulty_max=difficulty_max,
        question_types=question_types,
    )

    if len(questions) < total_count:
        raise HTTPException(
            status_code=400,
            detail=f"满足条件的题目不足：需要 {total_count} 道，当前只有 {len(questions)} 道",
        )
    return random.sample(questions, total_count)
