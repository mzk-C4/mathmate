from decimal import Decimal
from typing import Any

from database import JsonStore
from schemas import GradeResult


def get_exam_question_score(store: JsonStore, exam_id: int, question_id: int) -> Decimal | None:
    return store.get_exam_question_score(exam_id, question_id)


def save_answer_record(
    store: JsonStore,
    exam_id: int,
    student_id: str,
    question: dict[str, Any],
    student_answer: str | None,
    image_url: str | None,
    max_score: Decimal,
    grade: GradeResult,
) -> dict[str, Any]:
    return store.upsert_answer_record(
        exam_id=exam_id,
        student_id=student_id,
        question=question,
        student_answer=student_answer,
        image_url=image_url,
        max_score=max_score,
        grade=grade,
    )
