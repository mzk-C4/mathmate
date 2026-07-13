import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/wrong_book/models/wrong_question.dart';

void main() {
  test('wrong question maps report metadata', () {
    final WrongQuestion item = WrongQuestion.fromReport(<String, dynamic>{
      'question_code': 'q-1',
      'content': '1+1=?',
      'student_answer': '3',
      'standard_answer': '2',
      'board': '数与代数',
      'difficulty': 0.3,
      'knowledge_points': <String>['加法'],
      'source': <String, dynamic>{'dataset': 'demo'},
    });
    expect(item.id, 'q-1');
    expect(item.knowledgePoints, <String>['加法']);
    expect(item.source['dataset'], 'demo');
  });

  test('repeated mistakes increment count and reset mastery', () {
    final WrongQuestion first = WrongQuestion.fromReport(<String, dynamic>{
      'question_code': 'q-1',
      'content': 'x',
    });
    final WrongQuestion next = first.recordAgain(first);
    expect(next.wrongCount, 2);
    expect(next.mastered, isFalse);
  });
}
