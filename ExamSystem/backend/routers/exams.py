from collections import defaultdict
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from database import JsonStore, get_store
from schemas import (
    BoardAnalysisItem,
    ExamCreateRequest,
    ExamCreateResponse,
    ExamDetailResponse,
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
from services.question_selector import select_questions
from services.record_service import get_exam_question_score, save_answer_record

router = APIRouter(prefix="/exams", tags=["exams"])


@router.post("/create", response_model=ExamCreateResponse, status_code=201)
def create_exam(
    payload: ExamCreateRequest,
    store: JsonStore = Depends(get_store),
) -> ExamCreateResponse:
    questions = select_questions(
        store,
        total_count=payload.total_count,
        board=payload.board,
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
) -> ExamDetailResponse:
    exam = store.get_exam(exam_id)
    if not exam:
        raise HTTPException(status_code=404, detail="考试不存在")

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
) -> SubmitAnswerResponse:
    exam = store.get_exam(payload.exam_id)
    if not exam:
        raise HTTPException(status_code=404, detail="考试不存在")

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
) -> FinishExamResponse:
    exam = store.get_exam(payload.exam_id)
    if not exam:
        raise HTTPException(status_code=404, detail="考试不存在")

    records = store.list_answer_records(payload.exam_id, payload.student_id)
    total_score = sum((Decimal(str(record.get("score") or "0")) for record in records), Decimal("0"))
    max_score = sum((Decimal(str(record.get("max_score") or "0")) for record in records), Decimal("0"))
    correct_count = sum(1 for record in records if record.get("is_correct"))
    accuracy = correct_count / len(records) if records else 0

    by_board: dict[str, dict[str, Decimal | int]] = defaultdict(
        lambda: {"total": 0, "correct": 0, "score": Decimal("0"), "max_score": Decimal("0")}
    )
    wrong_questions: list[WrongQuestionItem] = []
    for record in records:
        board = record.get("board_snapshot") or "未分类"
        stats = by_board[board]
        stats["total"] = int(stats["total"]) + 1
        stats["correct"] = int(stats["correct"]) + (1 if record.get("is_correct") else 0)
        stats["score"] = Decimal(stats["score"]) + Decimal(str(record.get("score") or "0"))
        stats["max_score"] = Decimal(stats["max_score"]) + Decimal(str(record.get("max_score") or "0"))
        if not record.get("is_correct"):
            wrong_questions.append(
                WrongQuestionItem(
                    question_code=record.get("question_code_snapshot"),
                    content=record.get("content_snapshot"),
                    student_answer=record.get("student_answer"),
                    standard_answer=record.get("standard_answer_snapshot"),
                    explanation=record.get("explanation_snapshot"),
                    llm_feedback=record.get("llm_feedback"),
                )
            )

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
