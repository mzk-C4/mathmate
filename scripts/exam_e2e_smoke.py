#!/usr/bin/env python3
"""Run an authenticated end-to-end smoke test against the exam API.

The script never prints the signing secret or generated bearer tokens. Point
``--base-url`` at a disposable ExamSystem instance because it creates and
finishes an exam. ``--public-url`` is optional and is only used for read-only
checks against the production proxy.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import ssl
import time
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def _b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def create_token(secret_path: Path, user_id: str) -> str:
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = _b64url(
        json.dumps(
            {"uid": user_id, "role": "user", "iat": now, "exp": now + 600},
            separators=(",", ":"),
        ).encode()
    )
    secret = secret_path.read_text(encoding="utf-8").strip().encode()
    signature = _b64url(
        hmac.new(secret, f"{header}.{payload}".encode("ascii"), hashlib.sha256).digest()
    )
    return f"{header}.{payload}.{signature}"


def api_request(
    base_url: str,
    method: str,
    path: str,
    *,
    token: str | None = None,
    body: dict[str, Any] | None = None,
) -> tuple[int, Any]:
    headers = {"Accept": "application/json"}
    data = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = Request(
        f"{base_url.rstrip('/')}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urlopen(request, timeout=20, context=ssl.create_default_context()) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except HTTPError as error:
        raw = error.read()
        try:
            payload = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            payload = raw.decode("utf-8", errors="replace")
        return error.code, payload


def require_status(actual: int, expected: int, label: str, payload: Any) -> None:
    if actual != expected:
        raise RuntimeError(f"{label}: expected HTTP {expected}, got {actual}: {payload}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--public-url")
    parser.add_argument("--secret-path", type=Path, required=True)
    parser.add_argument("--database-path", type=Path, required=True)
    args = parser.parse_args()

    student_id = f"e2e-{int(time.time())}"
    token = create_token(args.secret_path, student_id)
    other_token = create_token(args.secret_path, f"{student_id}-other")

    summary: dict[str, Any] = {"student_id": student_id}

    if args.public_url:
        status, payload = api_request(args.public_url, "GET", "/api/exams/health")
        require_status(status, 200, "public health", payload)

        status, payload = api_request(
            args.public_url,
            "POST",
            "/api/exams/available-count",
            body={"question_types": ["choice"]},
        )
        require_status(status, 401, "public anonymous authorization", payload)

        status, payload = api_request(
            args.public_url,
            "POST",
            "/api/exams/available-count",
            token=token,
            body={"question_types": ["choice"]},
        )
        require_status(status, 200, "public authenticated availability", payload)
        summary["public_choice_count"] = int(payload["available_count"])

    status, payload = api_request(args.base_url, "GET", "/api/exams/health")
    require_status(status, 200, "isolated health", payload)

    status, payload = api_request(
        args.base_url,
        "POST",
        "/api/exams/available-count",
        token=token,
        body={"question_types": ["choice"]},
    )
    require_status(status, 200, "isolated availability", payload)
    available = int(payload["available_count"])
    if available < 1:
        raise RuntimeError("No choice questions are available for the smoke test")
    question_count = min(3, available)

    status, exam = api_request(
        args.base_url,
        "POST",
        "/api/exams/create",
        token=token,
        body={
            "student_id": student_id,
            "title": "__MathMate E2E smoke test__",
            "total_count": question_count,
            "question_types": ["choice"],
        },
    )
    require_status(status, 201, "create exam", exam)
    exam_id = int(exam["exam_id"])
    if len(exam["questions"]) != question_count:
        raise RuntimeError("Created exam has an unexpected question count")

    status, detail = api_request(
        args.base_url, "GET", f"/api/exams/{exam_id}", token=token
    )
    require_status(status, 200, "get exam", detail)
    if [q["id"] for q in detail["questions"]] != [q["id"] for q in exam["questions"]]:
        raise RuntimeError("Exam detail question order differs from create response")

    status, payload = api_request(
        args.base_url, "GET", f"/api/exams/{exam_id}", token=other_token
    )
    require_status(status, 403, "ownership isolation", payload)

    database = json.loads(args.database_path.read_text(encoding="utf-8"))
    answers = {int(q["id"]): str(q["standard_answer"]) for q in database["questions"]}
    for question in detail["questions"]:
        question_id = int(question["id"])
        status, result = api_request(
            args.base_url,
            "POST",
            "/api/exams/submit-answer",
            token=token,
            body={
                "exam_id": exam_id,
                "student_id": student_id,
                "question_id": question_id,
                "student_answer": answers[question_id],
            },
        )
        require_status(status, 200, f"submit answer {question_id}", result)
        if not result["is_correct"] or float(result["score"]) != float(result["max_score"]):
            raise RuntimeError(f"Correct answer was graded incorrectly: {result}")

    status, result = api_request(
        args.base_url,
        "POST",
        "/api/exams/finish",
        token=token,
        body={"exam_id": exam_id, "student_id": student_id},
    )
    require_status(status, 200, "finish exam", result)
    if float(result["accuracy"]) != 1.0:
        raise RuntimeError(f"Finished exam accuracy is not 100%: {result}")
    if float(result["total_score"]) != float(result["max_score"]):
        raise RuntimeError(f"Finished exam score is inconsistent: {result}")
    if result["wrong_questions"]:
        raise RuntimeError(f"Correctly answered exam has wrong questions: {result}")

    status, finished_detail = api_request(
        args.base_url, "GET", f"/api/exams/{exam_id}", token=token
    )
    require_status(status, 200, "get finished exam", finished_detail)
    if not finished_detail["finished_at"]:
        raise RuntimeError("Finished exam does not contain finished_at")

    summary.update(
        {
            "isolated_choice_count": available,
            "exam_id": exam_id,
            "questions_created": question_count,
            "answers_submitted": question_count,
            "accuracy": result["accuracy"],
            "total_score": result["total_score"],
            "max_score": result["max_score"],
            "ownership_check": 403,
            "status": "passed",
        }
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
