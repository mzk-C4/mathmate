from datetime import datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

QuestionType = Literal["choice", "blank", "short_answer"]


class QuestionCreate(BaseModel):
    question_code: str
    content: str
    standard_answer: str
    explanation: str | None = None
    difficulty: Decimal = Field(ge=0, le=1)
    board: str
    question_type: QuestionType
    options: dict[str, str] | None = None
    knowledge_points: list[str] = Field(default_factory=list)
    source: dict[str, Any] = Field(default_factory=dict)


class QuestionOut(BaseModel):
    id: int
    question_code: str
    content: str
    difficulty: Decimal
    board: str
    question_type: str
    options: dict[str, Any] | None = None
    knowledge_points: list[str] = Field(default_factory=list)
    source: dict[str, Any] = Field(default_factory=dict)

    model_config = ConfigDict(from_attributes=True)


class QuestionAdminOut(QuestionOut):
    standard_answer: str
    explanation: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class QuestionImportRequest(BaseModel):
    questions: list[QuestionCreate] = Field(min_length=1, max_length=2000)
    dry_run: bool = True


class QuestionImportResponse(BaseModel):
    dry_run: bool
    accepted_count: int
    imported_count: int
    duplicate_codes: list[str] = Field(default_factory=list)


class ExamFilterRequest(BaseModel):
    board: str | None = None
    boards: list[str] | None = None
    difficulty_min: Decimal | None = Field(default=None, ge=0, le=1)
    difficulty_max: Decimal | None = Field(default=None, ge=0, le=1)
    question_types: list[QuestionType] | None = None


class ExamCreateRequest(ExamFilterRequest):
    student_id: str
    title: str | None = "数学测试"
    total_count: int = Field(default=10, ge=1, le=100)


class ExamAvailabilityResponse(BaseModel):
    available_count: int


class ExamCreateResponse(BaseModel):
    exam_id: int
    title: str | None
    student_id: str | None
    questions: list[QuestionOut]


class ExamQuestionOut(QuestionOut):
    question_order: int
    max_score: Decimal


class ExamDetailResponse(BaseModel):
    exam_id: int
    title: str | None
    student_id: str | None
    started_at: datetime | None
    finished_at: datetime | None
    questions: list[ExamQuestionOut]


class SubmitAnswerRequest(BaseModel):
    exam_id: int
    student_id: str
    question_id: int
    student_answer: str | None = ""
    image_url: str | None = None


class SubmitAnswerResponse(BaseModel):
    question_id: int
    is_correct: bool
    score: Decimal
    max_score: Decimal
    feedback: str
    grader_type: str
    answer_record_id: int


class FinishExamRequest(BaseModel):
    exam_id: int
    student_id: str


class BoardAnalysisItem(BaseModel):
    board: str
    total: int
    correct: int
    score: Decimal
    max_score: Decimal


class WrongQuestionItem(BaseModel):
    question_code: str | None
    content: str | None
    student_answer: str | None
    standard_answer: str | None
    explanation: str | None
    llm_feedback: str | None
    board: str | None = None
    question_type: str | None = None
    difficulty: float = 0.5
    knowledge_points: list[str] = Field(default_factory=list)
    source: dict[str, Any] = Field(default_factory=dict)


class FinishExamResponse(BaseModel):
    exam_id: int
    total_score: Decimal
    max_score: Decimal
    accuracy: float
    board_analysis: list[BoardAnalysisItem]
    wrong_questions: list[WrongQuestionItem]


class ImageUploadResponse(BaseModel):
    ocr_text: str
    image_url: str


class GradeResult(BaseModel):
    score: Decimal
    is_correct: bool
    feedback: str
    grader_type: str
    raw_response: str | None = None
    prompt: str | None = None
