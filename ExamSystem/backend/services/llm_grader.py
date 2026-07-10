from decimal import Decimal
import json
from typing import Any

import httpx

from config import get_settings
from schemas import GradeResult


def build_grading_prompt(
    question: dict[str, Any],
    student_answer: str | None,
    max_score: Decimal,
) -> str:
    return f"""你是一个严谨的数学考试阅卷老师。

请根据题目内容、标准答案、答案解析和学生答案进行评分。

要求：
1. 只根据数学正确性评分
2. 不因为表达方式不同而扣分
3. 如果学生答案思路正确但过程不完整，可以给部分分
4. 返回 JSON 格式，不要输出多余文字

题目内容：
{question["content"]}

标准答案：
{question["standard_answer"]}

答案解析：
{question.get("explanation") or ""}

学生答案：
{student_answer or ""}

满分：
{max_score}

请返回：
{{
  "score": 0 到 {max_score} 之间的数字,
  "is_correct": true 或 false,
  "feedback": "简短评分理由"
}}"""


def _fallback_grade(question: dict[str, Any], student_answer: str | None, max_score: Decimal) -> GradeResult:
    student = (student_answer or "").strip()
    standard = question["standard_answer"].strip()
    is_correct = bool(student) and student == standard
    return GradeResult(
        is_correct=is_correct,
        score=max_score if is_correct else Decimal("0"),
        feedback="未配置大模型 API，已使用本地保守规则判分",
        grader_type="fallback",
    )


async def grade_with_llm(
    question: dict[str, Any],
    student_answer: str | None,
    max_score: Decimal,
) -> GradeResult:
    settings = get_settings()
    prompt = build_grading_prompt(question, student_answer, max_score)
    if not settings.llm_api_key:
        result = _fallback_grade(question, student_answer, max_score)
        result.prompt = prompt
        return result

    payload = {
        "model": settings.llm_model,
        "messages": [
            {"role": "system", "content": "你只输出 JSON，不输出解释性前后缀。"},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0,
    }
    headers = {"Authorization": f"Bearer {settings.llm_api_key}"}
    url = settings.llm_base_url.rstrip("/") + "/chat/completions"

    async with httpx.AsyncClient(timeout=settings.llm_timeout_seconds) as client:
        response = await client.post(url, json=payload, headers=headers)
        response.raise_for_status()

    raw_content = response.json()["choices"][0]["message"]["content"]
    parsed = json.loads(raw_content)
    score = max(Decimal("0"), min(Decimal(str(parsed.get("score", 0))), max_score))
    is_correct = bool(parsed.get("is_correct", score >= max_score))
    feedback = str(parsed.get("feedback", "大模型已完成评分"))
    return GradeResult(
        score=score,
        is_correct=is_correct,
        feedback=feedback,
        grader_type="llm",
        raw_response=raw_content,
        prompt=prompt,
    )
