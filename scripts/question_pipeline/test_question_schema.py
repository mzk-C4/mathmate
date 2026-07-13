import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from question_schema import normalize_question
from audit_question_bank import approved_items, audit


class QuestionSchemaTest(unittest.TestCase):
    def test_normalizes_library_shape(self):
        question = normalize_question({
            "id": "demo-1", "content": "1+1=?", "answer": "2",
            "section": "数与代数", "type": "填空题", "difficulty": 1.4,
            "knowledgePoints": ["加法"],
        }, "demo")
        self.assertEqual(question.question_type, "blank")
        self.assertEqual(question.difficulty, 1.0)
        self.assertEqual(question.knowledge_points, ["加法"])
        self.assertEqual(question.source["dataset"], "demo")

    def test_stable_generated_code(self):
        raw = {"题干": "x+1=2", "答案": "x=1", "题型": "解答题"}
        self.assertEqual(
            normalize_question(raw, "bank").question_code,
            normalize_question(raw, "bank").question_code,
        )

    def test_audit_marks_review_items_and_duplicates(self):
        report = audit([
            {"question_code": "one", "content": "x = 1", "question_type": "choice"},
            {"question_code": "two", "content": "x=1", "question_type": "blank", "standard_answer": "1", "explanation": "ok"},
        ])
        self.assertEqual(report["review_count"], 1)
        self.assertEqual(len(report["duplicate_content_groups"]), 1)
        self.assertEqual(len(approved_items([
            {"question_code": "one", "content": "x = 1", "question_type": "choice"},
            {"question_code": "two", "content": "x=1", "question_type": "blank", "standard_answer": "1", "explanation": "ok"},
        ])), 1)


if __name__ == "__main__":
    unittest.main()
