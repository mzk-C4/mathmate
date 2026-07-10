#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
题库建设脚本：MinerU 解析的 Markdown → 切题 → DeepSeek 打标 → Question JSON

用法:
  python build_questions.py <md_path> <source_ref> <out_json>
例:
  python build_questions.py "D:/projects/add/senior high question/parsed_test/main/auto/main.md" \
      "2024新高考I卷" "questions_2024.json"

标签: 题型(单选/多选/填空/解答) + 板块 + 难度系数(0-1) + 知识点 + 答案 + 解析
"""
import sys
import os
import re
import json
import time
import requests
from dotenv import load_dotenv

# ---- 加载 MathMate 的 .env（复用 DeepSeek 配置）----
MATHMATE_DIR = r"D:\projects\MathMate"
load_dotenv(os.path.join(MATHMATE_DIR, ".env"))

API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()
MODEL_ID = os.getenv("DEEPSEEK_MODEL_ID", "").strip()
BASE_URL = os.getenv("DEEPSEEK_BASE_URL",
                     "https://api.deepseek.com/chat/completions").strip()

# 板块枚举（与 App 端 Question Schema 一致）
SECTIONS = [
    "集合与逻辑", "复数", "向量", "三角函数", "数列", "函数与导数",
    "立体几何", "解析几何", "概率统计", "计数原理", "不等式", "其他",
]

TAG_PROMPT = """你是高考数学题库标注助手。给你一道题的文本（题干，可能含选项 A/B/C/D），请严格输出一个 JSON 对象（不要 ```json 代码块包裹、不要任何解释、不要前后多余文字）：
{
  "section": "板块，从 [集合与逻辑, 复数, 向量, 三角函数, 数列, 函数与导数, 立体几何, 解析几何, 概率统计, 计数原理, 不等式, 其他] 中选最贴切的一个",
  "type": "题型，从 [单选题, 多选题, 填空题, 解答题] 选一个（多选题=明确说明有多个正确选项的选择题；普通选择题=单选题）",
  "difficulty": "难度系数，0~1 之间的纯数字（0.20 很容易 / 0.40 基础 / 0.55 中等 / 0.70 较难 / 0.85 挑战）",
  "knowledgePoints": ["2-4 个具体知识点"],
  "answer": "标准答案（尽量简短，如 'C' 或 '1/2' 或 'a=2'；解答题给关键结论）",
  "solution": "简明解析步骤（2-5 行，含关键公式/思路）"
}
注意：
1. difficulty 必须是 0~1 的纯数字，不要带引号、不要写"中等"等文字。
2. 只输出 JSON 对象本身。"""


def parse_questions(md):
    """从 MinerU 产出的 Markdown 切出单题。

    逻辑：按题型区标题(## 一、选择题 / 二、 / 三、填空 / 四、解答)确定题型，
    在区内按行首题号(\\d+.) 切分。标题行末尾若含首题号(如"四、解答题...15.")一并提取。
    注意事项(题型区之前)不切。
    """
    questions = []
    current_type = "单选题"
    current = None
    started = False

    for line in md.splitlines():
        s = line.strip()
        if not s:
            continue

        # 题型区标题
        if s.startswith("#"):
            if "解答" in s:
                current_type = "解答题"; started = True
            elif "填空" in s:
                current_type = "填空题"; started = True
            elif "多项" in s or ("选择" in s and "多" in s):
                current_type = "多选题"; started = True
            elif "选择" in s:
                current_type = "单选题"; started = True
            # 标题行末尾可能含首题号（如 "## 四、解答题...15. （13 分）"）
            m = re.search(r"(\d+)\s*[.、．]\s+(.+)$", s)
            if m and started:
                if current:
                    questions.append(current)
                current = {"num": int(m.group(1)), "type_guess": current_type,
                           "raw": m.group(2)}
            continue

        if not started:
            continue

        # 行首题号
        m = re.match(r"^(\d+)\s*[.、．]\s*(.*)", s)
        if m:
            if current:
                questions.append(current)
            current = {"num": int(m.group(1)), "type_guess": current_type,
                       "raw": m.group(2)}
        elif current:
            current["raw"] += "\n" + s

    if current:
        questions.append(current)
    return questions


def split_options(stem):
    """从题干提取 A./B./C./D. 选项。要求至少 A. + B. 连续出现（避免误匹配题干字母）。"""
    if not re.search(r"A[\.\．、]\s.*B[\.\．、]\s", stem):
        return stem.strip(), []
    am = re.search(r"A[\.\．、]\s", stem)
    opts_text = stem[am.start():]
    stem_clean = stem[:am.start()].strip()
    parts = re.split(r"\s*([A-D])[\.\．、]\s*", opts_text)
    options = []
    for i in range(1, len(parts) - 1, 2):
        options.append(f"{parts[i]}. {parts[i + 1].strip()}")
    return stem_clean, options


def deepseek_tag(stem, options, type_guess):
    """调 DeepSeek 给单题打标。返回 dict 或 None。"""
    user = f"【题型参考（仅供参考，可修正）】{type_guess}\n【题干】\n{stem}\n"
    if options:
        user += "【选项】\n" + "\n".join(options) + "\n"
    user += "\n请输出标注 JSON。"

    headers = {"Authorization": f"Bearer {API_KEY}",
               "Content-Type": "application/json"}
    body = {
        "model": MODEL_ID,
        "messages": [
            {"role": "system", "content": TAG_PROMPT},
            {"role": "user", "content": user},
        ],
        "temperature": 0.2,
    }
    resp = requests.post(BASE_URL, headers=headers, json=body, timeout=120)
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"].strip()
    m = re.search(r"\{[\s\S]*\}", content)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None


def build(md_path, source_ref, out_path):
    with open(md_path, encoding="utf-8") as f:
        md = f.read()

    raw_qs = parse_questions(md)
    print(f"切出 {len(raw_qs)} 道题，开始 DeepSeek 打标…")

    out = []
    for i, q in enumerate(raw_qs, 1):
        stem_clean, options = split_options(q["raw"])
        if not stem_clean:
            continue
        try:
            tag = deepseek_tag(stem_clean, options, q["type_guess"])
        except Exception as e:
            print(f"[{i}] 第{q['num']}题 打标失败: {e}")
            tag = None

        qtype = (tag.get("type") if tag else None) or q["type_guess"]
        try:
            difficulty = float(tag.get("difficulty", 0.55)) if tag else 0.55
            difficulty = max(0.0, min(1.0, difficulty))
        except Exception:
            difficulty = 0.55
        section = (tag.get("section") if tag else None) or "其他"
        if section not in SECTIONS:
            section = "其他"

        item = {
            "id": f"q_{source_ref}_{q['num']}",
            "subject": "数学",
            "section": section,
            "type": qtype,
            "content": stem_clean,
            "options": options if options else None,
            "answer": (tag.get("answer", "") if tag else ""),
            "solution": (tag.get("solution", "") if tag else ""),
            "difficulty": difficulty,
            "knowledgePoints": (tag.get("knowledgePoints", []) if tag else []),
            "source": {"type": "pdf", "ref": source_ref, "qnum": q["num"]},
        }
        out.append(item)
        print(f"[{i}/{len(raw_qs)}] 第{q['num']}题 {section} / {qtype} / "
              f"难度{difficulty:.2f} / 知识点{item['knowledgePoints']}")
        time.sleep(0.3)  # 避免 API 限频

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\n[完成] {len(out)} 道题 -> {out_path}")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print('用法: python build_questions.py <md_path> <source_ref> <out_json>')
        sys.exit(1)
    build(sys.argv[1], sys.argv[2], sys.argv[3])
