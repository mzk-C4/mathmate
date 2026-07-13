from services.question_selector import select_questions


class Store:
    def list_questions(self, **_kwargs):
        return [
            {"id": 1, "question_type": "choice", "standard_answer": "A"},
            {"id": 2, "question_type": "choice", "standard_answer": ""},
        ]


def test_selector_excludes_questions_without_standard_answer():
    selected = select_questions(Store(), total_count=1)
    assert [item["id"] for item in selected] == [1]
