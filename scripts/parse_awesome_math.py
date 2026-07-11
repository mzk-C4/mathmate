#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 rossant/awesome-math 的 README.md 解析为 MathMate 资料库用的扁平 JSON。

数据源:同目录 awesome_math_readme.md(CC0 快照,由 curl 从 GitHub 拉取)。
输出:项目根 assets/awesome_math.json

用法: python scripts/parse_awesome_math.py
"""
import json
import hashlib
import re
import sys
from collections import Counter
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
README = SCRIPT_DIR / "awesome_math_readme.md"
OUT = SCRIPT_DIR.parents[0] / "assets" / "awesome_math.json"

# ----------------------- 学段标注规则 -----------------------
# 中学(优先于 general,因 mathsisfun/ilovemaths 自述 up to highschool / grades 6-12)
MIDDLE_KEYS = [
    "high school", "highschool", "up to highschool", "grades 6", "k-12", "k12",
    "grade 6", "grade 7", "grade 8", "grade 9", "grade 10", "grade 11", "grade 12",
    "precalculus", "pre-calculus", "pre algebra", "pre-algebra",
]
# 通用(跨学段:工具 / 平台 / 百科 / YouTube 频道)
GENERAL_KEYS = [
    "khan academy", "khanacademy", "3blue1brown", "3blue1brown", "symbolab", "desmos",
    "wolfram alpha", "wolframalpha", "mathworld", "geogebra", "sympy", "sagemath",
    "sage math", "maxima", "mathematica", "octave", "matlab", "maple", "magma",
    "macaulay2", "singular", "encyclopedia", "planetmath", "proofwiki", "oeis",
    "wikipedia", "stack exchange", "stackoverflow", "mathoverflow", "brilliant",
    "mathigon", "numberphile", "mathologer", "math sorcerer", "patrickjmt",
    "professor leonard", "brandon foltz", "statquest", "crash course", "coursera",
    "edx", "mit opencourseware", "ocw", "ximera", "almost fun", "math academy",
    "quanta magazine", "wootube", "mathwords", "unit converter", "copypastemathjax",
    "mathcheap", "midpoint calculator", "quartiles calculator", "mathsjam",
    "talking maths", "bridges", "foltz", "leonard", "math theorems",
    "internet archive", "archive.org",
]
GRAD_KEYS = [
    "graduate", "grad course", "grad year", "fields medal", "for researchers",
    "professional", "research-level",
]
# 子分类(section3)直接判研究生
GRAD_SUBCATS = {
    "Category Theory", "Homotopy Type Theory", "Type Theory", "Lie Algebras",
    "Galois Theory", "Ring Theory", "Algebraic Geometry", "Algebraic Topology",
    "Algebraic Statistics", "Algebraic Number Theory", "Analytic Number Theory",
    "Differential Geometry", "Measure Theory", "Functional Analysis", "Harmonic Analysis",
}
# 二级分类(section2)归通用
GENERAL_SECTIONS2 = {
    "Tools", "Encyclopedia", "Questions and Answers", "Learning Platforms",
    "Youtube Series", "Blogs", "Magazines", "Meetings and Conferences", "Misc",
    "Learn to Learn",
}


def classify_stage(section1, section2, section3, title, note, url):
    blob = f"{title} {note} {url}".lower()
    # (a1) 中学关键词(优先,处理自述中学语料)
    for k in MIDDLE_KEYS:
        if k in blob:
            return "middle"
    # (a2) euclid / elements 经典几何 —— 只看标题,避免 url 含 euclid 域名误判
    title_low = title.lower()
    if "euclid" in title_low or ("elements" in title_low and section2 and "geometry" in section2.lower()):
        return "middle"
    # (a3) 通用白名单
    for k in GENERAL_KEYS:
        if k in blob:
            return "general"
    # (b) 研究生 / 本科 关键词
    for k in GRAD_KEYS:
        if k in blob:
            return "grad"
    if "undergraduate" in blob:
        return "undergrad"
    # (c) 子分类
    if section3 in GRAD_SUBCATS:
        return "grad"
    # (d) 二级分类通用
    if section2 in GENERAL_SECTIONS2:
        return "general"
    # (e) 兜底
    return "undergrad"


# ----------------------- README 解析 -----------------------
LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)\s]+)\)")
EMOJI_RE = re.compile(r"^(💲)?\s*(📖|🎥|📝🎥|📝)\s*")
PAID_RE = re.compile(r"^(💲)\s*")
SEP_RE = re.compile(r"^[\-—]+\s*")
PAREN_RE = re.compile(r"^(.*?)\s*\(([^)]*)\)\s*$")


def emoji_to_type(body):
    """返回 (type, 去除 emoji 后的 body)。视频会在解析阶段排除。"""
    m = EMOJI_RE.match(body)
    if m:
        e = m.group(2)
        t = {"📖": "book", "🎥": "video"}.get(e, "notes")
        return t, body[m.end():]
    m2 = PAID_RE.match(body)
    if m2:
        return "link", body[m2.end():]
    return "link", body


def infer_type(rtype, section2, url):
    """在 README 未标 emoji 时，结合分类与 URL 推断资源类型。"""
    if rtype != "link":
        return rtype
    section = (section2 or "").lower()
    url_low = url.lower()
    if section == "books" or url_low.endswith((".pdf", ".epub")):
        return "book"
    if section in {"students lecture notes", "transition to pure rigour math"}:
        return "notes"
    return "link"


def is_video_resource(rtype, url):
    url_low = url.lower()
    return rtype == "video" or "youtube.com" in url_low or "youtu.be" in url_low


def stable_id(url):
    """URL 派生的稳定 ID；上游增删条目不会改变已有资源标识。"""
    digest = hashlib.sha256(url.strip().lower().encode("utf-8")).hexdigest()[:12]
    return f"awm_{digest}"


def parse_line(body):
    """解析一行资源体,返回 dict 或 None。"""
    lm = LINK_RE.search(body)
    if not lm:
        return None
    title, url = lm.group(1).strip(), lm.group(2).strip()
    rtype, after = emoji_to_type(body)
    paid = "💲" in body[:6]
    rest = after.replace(f"[{lm.group(1)}]({url})", "", 1).strip()
    rest = rest.lstrip("💲").strip()
    rest = SEP_RE.sub("", rest).strip()
    author = institution = note = ""
    if rest:
        pm = PAREN_RE.match(rest)
        if pm:
            author = pm.group(1).strip()
            institution = pm.group(2).strip()
        else:
            note = rest
    return {
        "title": title, "url": url, "type": rtype, "paid": paid,
        "author": author, "institution": institution, "note": note,
    }


def main():
    if not README.exists():
        print(f"[err] README 不存在: {README}", file=sys.stderr)
        print("      请先: curl -sSL https://cdn.jsdelivr.net/gh/rossant/awesome-math@master/README.md "
              "-o scripts/awesome_math_readme.md", file=sys.stderr)
        sys.exit(1)

    text = README.read_text(encoding="utf-8")
    items = []
    section1 = section2 = section3 = None
    in_license = False
    n = 0

    for raw in text.split("\n"):
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith("# "):
            h1 = line[2:].strip()
            section1, section2, section3 = h1, None, None
            in_license = h1.lower() == "license"
            continue
        if in_license:
            continue
        if line.startswith("## "):
            section2, section3 = line[3:].strip(), None
            continue
        if line.startswith("### "):
            section3 = line[4:].strip()
            continue
        m = re.match(r"^\s*[*\-]\s+(.+)$", line)
        if not m:
            continue
        parsed = parse_line(m.group(1))
        if not parsed:
            continue
        if is_video_resource(parsed["type"], parsed["url"]):
            continue
        parsed["type"] = infer_type(parsed["type"], section2, parsed["url"])
        stage = classify_stage(section1, section2, section3,
                               parsed["title"], parsed["note"], parsed["url"])
        items.append({
            "id": stable_id(parsed["url"]),
            **parsed,
            "section1": section1 or "",
            "section2": section2,
            "section3": section3,
            "stage": stage,
        })

    out = {
        "version": 1,
        "source": "rossant/awesome-math (master)",
        "index_license": "CC0",
        "content_license": "varies_by_resource",
        "usage_mode": "external_link_only",
        "count": len(items),
        "items": items,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    # 统计
    print(f"[ok] 解析 {len(items)} 条 → {OUT}")
    print("stage :", dict(Counter(it["stage"] for it in items)))
    print("type  :", dict(Counter(it["type"] for it in items)))
    print("sec1  :", dict(Counter(it["section1"] for it in items)))


if __name__ == "__main__":
    main()
