from decimal import Decimal

from schemas import GradeResult


def grade_choice(student_answer: str | None, standard_answer: str, max_score: Decimal) -> GradeResult:
    normalized_student = (student_answer or "").strip().upper()
    normalized_standard = standard_answer.strip().upper()
    is_correct = normalized_student == normalized_standard
    return GradeResult(
        is_correct=is_correct,
        score=max_score if is_correct else Decimal("0"),
        feedback="回答正确" if is_correct else f"回答错误，正确答案是 {normalized_standard}",
        grader_type="rule",
    )
