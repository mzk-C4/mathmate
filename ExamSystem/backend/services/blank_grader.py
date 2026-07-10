from decimal import Decimal
import re

from schemas import GradeResult


def normalize_blank_answer(value: str | None) -> str:
    text = (value or "").strip().lower()
    replacements = {
        "＝": "=",
        "，": ",",
        "。": ".",
        "；": ";",
        "：": ":",
        "（": "(",
        "）": ")",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    return re.sub(r"\s+", "", text)


def _answer_variants(value: str | None) -> set[str]:
    normalized = normalize_blank_answer(value)
    variants = {normalized}
    if "=" in normalized:
        variants.add(normalized.split("=")[-1])
    return {item for item in variants if item}


def grade_blank_by_rule(
    student_answer: str | None,
    standard_answer: str,
    max_score: Decimal,
) -> GradeResult | None:
    student_variants = _answer_variants(student_answer)
    standard_variants = _answer_variants(standard_answer)
    if not student_variants:
        return GradeResult(
            is_correct=False,
            score=Decimal("0"),
            feedback="未填写答案",
            grader_type="rule",
        )
    if student_variants & standard_variants:
        return GradeResult(
            is_correct=True,
            score=max_score,
            feedback="回答正确",
            grader_type="rule",
        )
    return None
