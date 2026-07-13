#!/usr/bin/env python
"""Create a review report for canonical MathMate question-bank JSON."""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from hashlib import sha256
from pathlib import Path
from typing import Any


def content_key(content: str) -> str:
    normalized = re.sub(r"\s+", "", content).lower()
    return sha256(normalized.encode("utf-8")).hexdigest()[:16]


def review_flags(item: dict[str, Any]) -> list[str]:
    flags: list[str] = []
    content = str(item.get("content") or "")
    if not content.strip():
        flags.append("missing_content")
    if not str(item.get("standard_answer") or "").strip():
        flags.append("missing_answer")
    if not str(item.get("explanation") or "").strip():
        flags.append("missing_explanation")
    if str(item.get("question_type") or "") == "choice" and not item.get("options"):
        flags.append("choice_missing_options")
    if "![](" in content:
        flags.append("requires_image_asset")
    return flags


def audit(items: list[dict[str, Any]]) -> dict[str, Any]:
    by_content: dict[str, list[str]] = defaultdict(list)
    review: list[dict[str, Any]] = []
    type_counts: Counter[str] = Counter()
    board_counts: Counter[str] = Counter()

    for item in items:
        code = str(item.get("question_code") or "")
        content = str(item.get("content") or "")
        question_type = str(item.get("question_type") or "")
        type_counts[question_type] += 1
        board_counts[str(item.get("board") or "未分类")] += 1
        by_content[content_key(content)].append(code)

        flags = review_flags(item)
        if flags:
            review.append({"question_code": code, "flags": flags})

    duplicate_groups = [
        {"content_key": key, "question_codes": codes}
        for key, codes in by_content.items()
        if len(codes) > 1
    ]
    return {
        "total": len(items),
        "question_types": dict(sorted(type_counts.items())),
        "boards": dict(board_counts.most_common()),
        "review_count": len(review),
        "review_items": review,
        "duplicate_content_groups": duplicate_groups,
    }


def approved_items(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep the first clean item for each exact normalized-content group."""
    seen: set[str] = set()
    approved: list[dict[str, Any]] = []
    for item in items:
        if review_flags(item):
            continue
        key = content_key(str(item.get("content") or ""))
        if key in seen:
            continue
        seen.add(key)
        approved.append(item)
    return approved


def main(argv: list[str]) -> int:
    if len(argv) not in {3, 4}:
        print("usage: audit_question_bank.py INPUT.json REPORT.json [APPROVED.json]", file=sys.stderr)
        return 2
    source, target = Path(argv[1]), Path(argv[2])
    payload = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("canonical input must be a JSON list")
    items = [item for item in payload if isinstance(item, dict)]
    report = audit(items)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if len(argv) == 4:
        approved = approved_items(items)
        Path(argv[3]).write_text(
            json.dumps(approved, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote approved={len(approved)} to {argv[3]}")
    print(
        f"audited total={report['total']} review={report['review_count']} "
        f"duplicate_groups={len(report['duplicate_content_groups'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
