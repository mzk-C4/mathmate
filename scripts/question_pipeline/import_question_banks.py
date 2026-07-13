#!/usr/bin/env python
"""Normalize one or more JSON question banks into ExamSystem JSON records.

Usage:
  python import_question_banks.py output.json input.json input_directory
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Iterable

from question_schema import normalize_question


def iter_json(path: Path) -> Iterable[tuple[str, dict[str, Any]]]:
    files = sorted(path.rglob("*.json")) if path.is_dir() else [path]
    for file in files:
        try:
            payload = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            print(f"skip {file}: {error}", file=sys.stderr)
            continue
        if isinstance(payload, dict):
            items = next((payload[key] for key in ("questions", "items", "data") if isinstance(payload.get(key), list)), [payload])
        else:
            items = payload
        if not isinstance(items, list):
            continue
        for item in items:
            if isinstance(item, dict):
                yield file.parent.name or file.stem, item


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: import_question_banks.py OUTPUT INPUT [INPUT ...]", file=sys.stderr)
        return 2
    output = Path(argv[1])
    normalized: dict[str, dict[str, Any]] = {}
    rejected = 0
    for input_name in argv[2:]:
        for source_name, raw in iter_json(Path(input_name)):
            try:
                question = normalize_question(raw, source_name)
                normalized.setdefault(question.question_code, question.to_dict())
            except (TypeError, ValueError) as error:
                rejected += 1
                print(f"reject {source_name}: {error}", file=sys.stderr)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(list(normalized.values()), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(normalized)} questions to {output}; rejected={rejected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
