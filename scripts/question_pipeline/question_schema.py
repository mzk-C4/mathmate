"""Canonical MathMate question normalization shared by import scripts."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from hashlib import sha256
from typing import Any


TYPE_ALIASES = {
    "choice": "choice", "single_choice": "choice", "multiple_choice": "choice",
    "单选题": "choice", "多选题": "choice", "选择题": "choice",
    "blank": "blank", "fill_blank": "blank", "填空题": "blank",
    "short_answer": "short_answer", "解答题": "short_answer", "简答题": "short_answer",
}


def _first(raw: dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        value = raw.get(key)
        if value is not None and value != "":
            return value
    return default


def _strings(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [part.strip() for part in value.replace("，", ",").split(",") if part.strip()]
    if isinstance(value, (list, tuple, set)):
        return [str(item).strip() for item in value if str(item).strip()]
    return [str(value).strip()]


def _options(value: Any) -> dict[str, str] | None:
    if not value:
        return None
    if isinstance(value, dict):
        return {str(key).upper(): str(item).strip() for key, item in value.items()}
    if isinstance(value, list):
        result: dict[str, str] = {}
        for index, item in enumerate(value):
            text = str(item).strip()
            letter = chr(65 + index)
            if len(text) > 2 and text[0].upper() in "ABCDEFG" and text[1] in ".、． ":
                letter, text = text[0].upper(), text[2:].strip()
            result[letter] = text
        return result or None
    return None


@dataclass(frozen=True)
class CanonicalQuestion:
    question_code: str
    content: str
    standard_answer: str
    difficulty: float
    board: str
    question_type: str
    explanation: str | None = None
    options: dict[str, str] | None = None
    knowledge_points: list[str] = field(default_factory=list)
    source: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def normalize_question(raw: dict[str, Any], source_name: str = "unknown") -> CanonicalQuestion:
    content = str(_first(raw, "content", "question", "stem", "text", "题目", "题干", default="")).strip()
    if not content:
        raise ValueError("question content is empty")
    answer = str(_first(raw, "standard_answer", "answer", "答案", default="")).strip()
    board = str(_first(raw, "board", "section", "category", "章节", "板块", default="其他")).strip()
    raw_type = str(_first(raw, "question_type", "type", "题型", default="short_answer")).strip()
    question_type = TYPE_ALIASES.get(raw_type.lower(), TYPE_ALIASES.get(raw_type, "short_answer"))
    difficulty = float(_first(raw, "difficulty", "难度", default=0.5))
    difficulty = min(1.0, max(0.0, difficulty))
    source = _first(raw, "source", "来源", default={})
    if not isinstance(source, dict):
        source = {"ref": str(source)}
    source = {"dataset": source_name, **source}
    fingerprint = sha256(f"{source_name}\n{content}\n{answer}".encode("utf-8")).hexdigest()[:16]
    code = str(_first(raw, "question_code", "code", "id", "编号", default=f"q_{fingerprint}"))
    return CanonicalQuestion(
        question_code=code,
        content=content,
        standard_answer=answer,
        explanation=str(_first(raw, "explanation", "solution", "analysis", "解析", default="")).strip() or None,
        difficulty=difficulty,
        board=board,
        question_type=question_type,
        options=_options(_first(raw, "options", "choices", "选项")),
        knowledge_points=_strings(_first(raw, "knowledge_points", "knowledgePoints", "tags", "知识点")),
        source=source,
    )
