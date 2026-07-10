from decimal import Decimal

from services.blank_grader import grade_blank_by_rule, normalize_blank_answer
from services.choice_grader import grade_choice


def test_choice_grader_is_case_insensitive() -> None:
    result = grade_choice(" b ", "B", Decimal("1"))
    assert result.is_correct is True
    assert result.score == Decimal("1")


def test_blank_grader_accepts_value_after_equal_sign() -> None:
    result = grade_blank_by_rule("2", "x = 2", Decimal("1"))
    assert result is not None
    assert result.is_correct is True


def test_blank_normalizer_unifies_chinese_symbols() -> None:
    assert normalize_blank_answer("x ＝ 2") == "x=2"
