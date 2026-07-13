from collections import defaultdict
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from auth import AuthUser, ensure_owner, require_user
from database import JsonStore, get_store
from schemas import (
    BoardAnalysisItem,
    ExamAvailabilityResponse,
    ExamCreateRequest,
    ExamCreateResponse,
    ExamDetailResponse,
    ExamFilterRequest,
    ExamQuestionOut,
    FinishExamRequest,
    FinishExamResponse,
    SubmitAnswerRequest,
    SubmitAnswerResponse,
    WrongQuestionItem,
)
from services.blank_grader import grade_blank_by_rule
from services.choice_grader import grade_choice
from services.llm_grader import grade_with_llm
from services.question_selector import filter_questions, select_questions
from services.record_service import get_exam_question_score, save_answer_record

router = APIRouter(prefix="/exams", tags=["exams"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.post("/available-count", response_model=ExamAvailabilityResponse)
def available_count(
    payload: ExamFilterRequest,
    store: JsonStore = Depends(get_store),
    _user: AuthUser = Depends(require_user),
) -> ExamAvailabilityResponse:
    questions = filter_questions(
        store,
        board=payload.board,
        boards=payload.boards,
        difficulty_min=payload.difficulty_min,
        difficulty_max=payload.difficulty_max,
        question_types=payload.question_types,
    )
    return ExamAvailabilityResponse(available_count=len(questions))


@router.post("/create", response_model=ExamCreateResponse, status_code=201)
def create_exam(
    payload: ExamCreateRequest,
    store: JsonStore = Depends(get_store),
    user: AuthUser = Depends(require_user),
) -> ExamCreateResponse:
    ensure_owner(user, payload.student_id)
    questions = select_questions(
        store,
        total_count=payload.total_count,
        board=payload.board,
        boards=payload.boards,
        difficulty_min=payload.difficulty_min,
        difficulty_max=payload.difficulty_max,
        question_types=payload.question_types,
    )
    exam = store.create_exam(title=payload.title, student_id=payload.student_id, questions=questions)
    return ExamCreateResponse(
        exam_id=exam["id"],
        title=exam["title"],
        student_id=exam["student_id"],
        questions=questions,
    )


@router.get("/{exam_id}", response_model=ExamDetailResponse)
def get_exam(
    exam_id: int,
    store: JsonStore = Depends(get_store),
    user: AuthUser = Depends(require_user),
) -> ExamDetailResponse:
    exam = store.get_exam(exam_id)
    if not exam:
        raise HTTPException(status_code=404, detail="考试不存在")
    ensure_owner(user, exam.get("student_id"))

    questions = [
        ExamQuestionOut(
            id=question["id"],
            question_code=question["question_code"],
            content=question["content"],
            difficulty=Decimal(str(question["difficulty"])),
            board=question["board"],
            question_type=question["question_type"],
            options=question.get("options"),
            question_order=exam_question["question_order"],
            max_score=Decimal(str(exam_question["score"])),
        )
        for exam_question, question in store.get_exam_questions(exam_id)
    ]
    return ExamDetailResponse(
        exam_id=exam["id"],
        title=exam["title"],
        student_id=exam["student_id"],
        started_at=exam["started_at"],
        finished_at=exam["finished_at"],
        questions=questions,
    )


@router.post("/submit-answer", response_model=SubmitAnswerResponse)
async def submit_answer(
    payload: SubmitAnswerRequest,
    store: JsonStore = Depends(get_store),
    user: AuthUser = Depends(require_user),
) -> SubmitAnswerResponse:
    exam = store.get_exam(payload.exam_id)
    if not exam:
        raise HTTPException(status_code=404, detail="考试不存在")
    ensure_owner(user, exam.get("student_id"))
    ensure_owner(user, payload.student_id)

    question = store.get_question(payload.question_id)
    if not question:
        raise HTTPException(status_code=404, detail="题目不存在")

    max_score = get_exam_question_score(store, payload.exam_id, payload.question_id)
    if max_score is None:
        raise HTTPException(status_code=400, detail="该题目不属于当前考试")

    if question["question_type"] == "choice":
        grade = grade_choice(payload.student_answer, question["standard_answer"], max_score)
    elif question["question_type"] == "blank":
        grade = grade_blank_by_rule(payload.student_answer, question["standard_answer"], max_score)
        if grade is None:
            grade = await grade_with_llm(question, payload.student_answer, max_score)
    else:
        grade = await grade_with_llm(question, payload.student_answer, max_score)

    record = save_answer_record(
        store=store,
        exam_id=payload.exam_id,
        student_id=payload.student_id,
        question=question,
        student_answer=payload.student_answer,
        image_url=payload.image_url,
        max_score=max_score,
        grade=grade,
    )
    return SubmitAnswerResponse(
        question_id=question["id"],
        is_correct=bool(record["is_correct"]),
        score=Decimal(str(record.get("score") or "0")),
        max_score=Decimal(str(record["max_score"])),
        feedback=record.get("llm_feedback") or "",
        grader_type=record.get("grader_type") or "",
        answer_record_id=record["id"],
    )


@router.post("/finish", response_model=FinishExamResponse)
def finish_exam(
    payload: FinishExamRequest,
    store: JsonStore = Depends(get_store),
    user: AuthUser = Depends(require_user),
) -> FinishExamResponse:
    exam = store.get_exam(payload.exam_id)
    if not exam:
        raise HTTPException(status_code=404, detail="考试不存在")
    ensure_owner(user, exam.get("student_id"))
    ensure_owner(user, payload.student_id)

    records = store.list_answer_records(payload.exam_id, payload.student_id)
    records_by_question = {record["question_id"]: record for record in records}
    exam_questions = store.get_exam_questions(payload.exam_id)
    total_score = Decimal("0")
    max_score = Decimal("0")
    correct_count = 0

    by_board: dict[str, dict[str, Decimal | int]] = defaultdict(
        lambda: {"total": 0, "correct": 0, "score": Decimal("0"), "max_score": Decimal("0")}
    )
    wrong_questions: list[WrongQuestionItem] = []
    for exam_question, question in exam_questions:
        record = records_by_question.get(question["id"])
        question_max_score = Decimal(str(exam_question.get("score") or "0"))
        question_score = Decimal(str(record.get("score") or "0")) if record else Decimal("0")
        is_correct = bool(record and record.get("is_correct"))
        total_score += question_score
        max_score += question_max_score
        correct_count += 1 if is_correct else 0

        board = (record.get("board_snapshot") if record else question.get("board")) or "未分类"
        stats = by_board[board]
        stats["total"] = int(stats["total"]) + 1
        stats["correct"] = int(stats["correct"]) + (1 if is_correct else 0)
        stats["score"] = Decimal(stats["score"]) + question_score
        stats["max_score"] = Decimal(stats["max_score"]) + question_max_score
        if not is_correct:
            wrong_questions.append(
                WrongQuestionItem(
                    question_code=(record.get("question_code_snapshot") if record else question.get("question_code")),
                    content=(record.get("content_snapshot") if record else question.get("content")),
                    student_answer=record.get("student_answer") if record else None,
                    standard_answer=(record.get("standard_answer_snapshot") if record else question.get("standard_answer")),
                    explanation=(record.get("explanation_snapshot") if record else question.get("explanation")),
                    llm_feedback=record.get("llm_feedback") if record else "未作答",
                    board=(record.get("board_snapshot") if record else question.get("board")),
                    question_type=(record.get("question_type_snapshot") if record else question.get("question_type")),
                    difficulty=float(record.get("difficulty_snapshot") if record else question.get("difficulty", 0.5)),
                    knowledge_points=(record.get("knowledge_points_snapshot") if record else question.get("knowledge_points", [])),
                    source=(record.get("source_snapshot") if record else question.get("source", {})),
                )
            )

    accuracy = correct_count / len(exam_questions) if exam_questions else 0

    board_analysis = [
        BoardAnalysisItem(
            board=board,
            total=int(stats["total"]),
            correct=int(stats["correct"]),
            score=Decimal(stats["score"]),
            max_score=Decimal(stats["max_score"]),
        )
        for board, stats in by_board.items()
    ]

    store.finish_exam(exam_id=payload.exam_id, total_score=total_score)
    return FinishExamResponse(
        exam_id=exam["id"],
        total_score=total_score,
        max_score=max_score,
        accuracy=accuracy,
        board_analysis=board_analysis,
        wrong_questions=wrong_questions,
    )
