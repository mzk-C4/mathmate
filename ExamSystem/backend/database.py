from __future__ import annotations

from copy import deepcopy
from datetime import datetime
from decimal import Decimal
import json
from pathlib import Path
from threading import RLock
from typing import Any

from config import get_settings


def utc_now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _json_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return str(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


class JsonStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        if not self.path.is_absolute():
            self.path = Path(__file__).resolve().parents[1] / self.path
        self.lock = RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self._write(self._empty_data())

    def _empty_data(self) -> dict[str, Any]:
        return {
            "counters": {
                "questions": 1,
                "exams": 1,
                "exam_questions": 1,
                "answer_records": 1,
                "grading_logs": 1,
            },
            "questions": [],
            "exams": [],
            "exam_questions": [],
            "answer_records": [],
            "grading_logs": [],
        }

    def _read(self) -> dict[str, Any]:
        with self.path.open("r", encoding="utf-8") as file:
            return json.load(file)

    def _write(self, data: dict[str, Any]) -> None:
        temp_path = self.path.with_suffix(".tmp")
        with temp_path.open("w", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2, default=_json_default)
            file.write("\n")
        temp_path.replace(self.path)

    def read(self) -> dict[str, Any]:
        with self.lock:
            return deepcopy(self._read())

    def transact(self, callback):
        with self.lock:
            data = self._read()
            result = callback(data)
            self._write(data)
            return deepcopy(result)

    def next_id(self, data: dict[str, Any], name: str) -> int:
        current = int(data["counters"][name])
        data["counters"][name] = current + 1
        return current

    def list_questions(
        self,
        board: str | None = None,
        question_type: str | None = None,
        difficulty_min: Decimal | None = None,
        difficulty_max: Decimal | None = None,
    ) -> list[dict[str, Any]]:
        data = self.read()
        questions = data["questions"]
        if board:
            questions = [item for item in questions if item["board"] == board]
        if question_type:
            questions = [item for item in questions if item["question_type"] == question_type]
        if difficulty_min is not None:
            questions = [item for item in questions if Decimal(str(item["difficulty"])) >= difficulty_min]
        if difficulty_max is not None:
            questions = [item for item in questions if Decimal(str(item["difficulty"])) <= difficulty_max]
        return sorted(questions, key=lambda item: item["id"])

    def create_question(self, payload: dict[str, Any]) -> dict[str, Any]:
        def op(data: dict[str, Any]) -> dict[str, Any]:
            if any(item["question_code"] == payload["question_code"] for item in data["questions"]):
                raise ValueError("题目编号已存在")
            now = utc_now()
            question = {
                "id": self.next_id(data, "questions"),
                **payload,
                "difficulty": str(payload["difficulty"]),
                "created_at": now,
                "updated_at": now,
            }
            data["questions"].append(question)
            return question

        return self.transact(op)

    def create_questions(self, payloads: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Atomically insert a normalized question batch after duplicate checks."""
        def op(data: dict[str, Any]) -> list[dict[str, Any]]:
            codes = [str(payload["question_code"]) for payload in payloads]
            existing = {str(item["question_code"]) for item in data["questions"]}
            duplicates = sorted(
                {code for code in codes if codes.count(code) > 1 or code in existing}
            )
            if duplicates:
                raise ValueError(f"题目编号重复: {', '.join(duplicates[:10])}")
            now = utc_now()
            created: list[dict[str, Any]] = []
            for payload in payloads:
                question = {
                    "id": self.next_id(data, "questions"),
                    **payload,
                    "difficulty": str(payload["difficulty"]),
                    "created_at": now,
                    "updated_at": now,
                }
                data["questions"].append(question)
                created.append(question)
            return created

        return self.transact(op)

    def get_question(self, question_id: int) -> dict[str, Any] | None:
        data = self.read()
        return next((item for item in data["questions"] if item["id"] == question_id), None)

    def get_exam(self, exam_id: int) -> dict[str, Any] | None:
        data = self.read()
        return next((item for item in data["exams"] if item["id"] == exam_id), None)

    def create_exam(self, title: str | None, student_id: str, questions: list[dict[str, Any]]) -> dict[str, Any]:
        def op(data: dict[str, Any]) -> dict[str, Any]:
            exam = {
                "id": self.next_id(data, "exams"),
                "title": title,
                "student_id": student_id,
                "total_score": "0",
                "started_at": utc_now(),
                "finished_at": None,
            }
            data["exams"].append(exam)
            for index, question in enumerate(questions, start=1):
                data["exam_questions"].append(
                    {
                        "id": self.next_id(data, "exam_questions"),
                        "exam_id": exam["id"],
                        "question_id": question["id"],
                        "question_order": index,
                        "score": "1",
                    }
                )
            return exam

        return self.transact(op)

    def get_exam_questions(self, exam_id: int) -> list[tuple[dict[str, Any], dict[str, Any]]]:
        data = self.read()
        questions_by_id = {item["id"]: item for item in data["questions"]}
        rows = [
            (exam_question, questions_by_id[exam_question["question_id"]])
            for exam_question in data["exam_questions"]
            if exam_question["exam_id"] == exam_id and exam_question["question_id"] in questions_by_id
        ]
        return sorted(rows, key=lambda row: row[0]["question_order"])

    def get_exam_question_score(self, exam_id: int, question_id: int) -> Decimal | None:
        data = self.read()
        row = next(
            (
                item
                for item in data["exam_questions"]
                if item["exam_id"] == exam_id and item["question_id"] == question_id
            ),
            None,
        )
        return Decimal(str(row["score"])) if row else None

    def upsert_answer_record(
        self,
        exam_id: int,
        student_id: str,
        question: dict[str, Any],
        student_answer: str | None,
        image_url: str | None,
        max_score: Decimal,
        grade: Any,
    ) -> dict[str, Any]:
        def op(data: dict[str, Any]) -> dict[str, Any]:
            record = next(
                (
                    item
                    for item in data["answer_records"]
                    if item["exam_id"] == exam_id
                    and item["student_id"] == student_id
                    and item["question_id"] == question["id"]
                ),
                None,
            )
            if record is None:
                record = {
                    "id": self.next_id(data, "answer_records"),
                    "exam_id": exam_id,
                    "student_id": student_id,
                    "question_id": question["id"],
                }
                data["answer_records"].append(record)

            record.update(
                {
                    "question_code_snapshot": question["question_code"],
                    "content_snapshot": question["content"],
                    "standard_answer_snapshot": question["standard_answer"],
                    "explanation_snapshot": question.get("explanation"),
                    "difficulty_snapshot": question["difficulty"],
                    "board_snapshot": question["board"],
                    "question_type_snapshot": question["question_type"],
                    "knowledge_points_snapshot": question.get("knowledge_points", []),
                    "source_snapshot": question.get("source", {}),
                    "student_answer": student_answer,
                    "image_url": image_url,
                    "is_correct": grade.is_correct,
                    "score": str(grade.score),
                    "max_score": str(max_score),
                    "grader_type": grade.grader_type,
                    "llm_feedback": grade.feedback,
                    "submitted_at": utc_now(),
                }
            )

            if grade.prompt or grade.raw_response:
                data["grading_logs"].append(
                    {
                        "id": self.next_id(data, "grading_logs"),
                        "answer_record_id": record["id"],
                        "prompt": grade.prompt,
                        "llm_response": grade.raw_response,
                        "created_at": utc_now(),
                    }
                )
            return record

        return self.transact(op)

    def list_answer_records(self, exam_id: int, student_id: str) -> list[dict[str, Any]]:
        data = self.read()
        records = [
            item
            for item in data["answer_records"]
            if item["exam_id"] == exam_id and item["student_id"] == student_id
        ]
        return sorted(records, key=lambda item: item["id"])

    def finish_exam(self, exam_id: int, total_score: Decimal) -> dict[str, Any] | None:
        def op(data: dict[str, Any]) -> dict[str, Any] | None:
            exam = next((item for item in data["exams"] if item["id"] == exam_id), None)
            if exam is None:
                return None
            exam["total_score"] = str(total_score)
            exam["finished_at"] = utc_now()
            return exam

        return self.transact(op)


store = JsonStore(get_settings().json_database_path)


def get_store() -> JsonStore:
    return store
