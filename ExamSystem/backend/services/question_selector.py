from decimal import Decimal
import random
from typing import Any

from fastapi import HTTPException

from database import JsonStore


def select_questions(
    store: JsonStore,
    total_count: int,
    board: str | None = None,
    difficulty_min: Decimal | None = None,
    difficulty_max: Decimal | None = None,
    question_types: list[str] | None = None,
) -> list[dict[str, Any]]:
    questions = store.list_questions(
        board=board,
        difficulty_min=difficulty_min,
        difficulty_max=difficulty_max,
    )
    if question_types:
        questions = [item for item in questions if item["question_type"] in question_types]

    if len(questions) < total_count:
        raise HTTPException(
            status_code=400,
            detail=f"满足条件的题目不足：需要 {total_count} 道，当前只有 {len(questions)} 道",
        )
    return random.sample(questions, total_count)
