from decimal import Decimal

from database import JsonStore
from routers.exams import available_count, finish_exam
from schemas import ExamFilterRequest, FinishExamRequest
from services.choice_grader import grade_choice
from services.record_service import save_answer_record


def _create_choice_question(
    store: JsonStore,
    *,
    code: str,
    board: str,
    answer: str = "A",
) -> dict:
    return store.create_question(
        {
            "question_code": code,
            "content": f"题目 {code}",
            "standard_answer": answer,
            "explanation": "测试解析",
            "difficulty": Decimal("0.5"),
            "board": board,
            "question_type": "choice",
            "options": {"A": "正确", "B": "错误"},
        }
    )


def test_available_count_supports_multiple_boards(tmp_path) -> None:
    store = JsonStore(tmp_path / "exam.json")
    _create_choice_question(store, code="ALG-1", board="代数")
    _create_choice_question(store, code="GEO-1", board="解析几何")
    _create_choice_question(store, code="FUNC-1", board="函数")

    response = available_count(
        ExamFilterRequest(
            boards=["代数", "解析几何"],
            question_types=["choice"],
        ),
        store,
    )

    assert response.available_count == 2


def test_finish_exam_counts_unanswered_questions_as_incorrect(tmp_path) -> None:
    store = JsonStore(tmp_path / "exam.json")
    answered = _create_choice_question(store, code="ALG-1", board="代数")
    _create_choice_question(store, code="ALG-2", board="代数")
    exam = store.create_exam(
        title="测试",
        student_id="student-1",
        questions=store.list_questions(),
    )
    max_score = store.get_exam_question_score(exam["id"], answered["id"])
    assert max_score is not None
    save_answer_record(
        store=store,
        exam_id=exam["id"],
        student_id="student-1",
        question=answered,
        student_answer="A",
        image_url=None,
        max_score=max_score,
        grade=grade_choice("A", "A", max_score),
    )

    response = finish_exam(
        FinishExamRequest(exam_id=exam["id"], student_id="student-1"),
        store,
    )

    assert response.total_score == Decimal("1")
    assert response.max_score == Decimal("2")
    assert response.accuracy == 0.5
    assert len(response.wrong_questions) == 1
    assert response.wrong_questions[0].llm_feedback == "未作答"
    assert response.board_analysis[0].total == 2
    assert response.board_analysis[0].correct == 1
