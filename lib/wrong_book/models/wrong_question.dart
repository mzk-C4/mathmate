import 'dart:convert';

class WrongQuestion {
  const WrongQuestion({
    required this.id,
    required this.questionCode,
    required this.content,
    required this.studentAnswer,
    required this.standardAnswer,
    required this.recordedAt,
    this.explanation = '',
    this.feedback = '',
    this.board = '',
    this.questionType = '',
    this.difficulty = 0.5,
    this.knowledgePoints = const <String>[],
    this.source = const <String, dynamic>{},
    this.wrongCount = 1,
    this.mastered = false,
  });

  final String id;
  final String questionCode;
  final String content;
  final String studentAnswer;
  final String standardAnswer;
  final String explanation;
  final String feedback;
  final String board;
  final String questionType;
  final double difficulty;
  final List<String> knowledgePoints;
  final Map<String, dynamic> source;
  final DateTime recordedAt;
  final int wrongCount;
  final bool mastered;

  factory WrongQuestion.fromReport(Map<String, dynamic> json) {
    final String code = json['question_code']?.toString() ?? '';
    final String content = json['content']?.toString() ?? '';
    return WrongQuestion(
      id: code.isNotEmpty
          ? code
          : content.hashCode.toUnsigned(32).toRadixString(16),
      questionCode: code,
      content: content,
      studentAnswer: json['student_answer']?.toString() ?? '',
      standardAnswer: json['standard_answer']?.toString() ?? '',
      explanation: json['explanation']?.toString() ?? '',
      feedback: json['llm_feedback']?.toString() ?? '',
      board: json['board']?.toString() ?? '',
      questionType: json['question_type']?.toString() ?? '',
      difficulty: (json['difficulty'] as num?)?.toDouble() ?? 0.5,
      knowledgePoints:
          (json['knowledge_points'] as List<dynamic>? ?? const <dynamic>[])
              .map((dynamic item) => item.toString())
              .toList(),
      source: Map<String, dynamic>.from(
        json['source'] as Map<dynamic, dynamic>? ?? const <dynamic, dynamic>{},
      ),
      recordedAt: DateTime.now(),
    );
  }

  WrongQuestion recordAgain(WrongQuestion latest) => WrongQuestion(
    id: id,
    questionCode: latest.questionCode,
    content: latest.content,
    studentAnswer: latest.studentAnswer,
    standardAnswer: latest.standardAnswer,
    explanation: latest.explanation,
    feedback: latest.feedback,
    board: latest.board,
    questionType: latest.questionType,
    difficulty: latest.difficulty,
    knowledgePoints: latest.knowledgePoints,
    source: latest.source,
    recordedAt: latest.recordedAt,
    wrongCount: wrongCount + 1,
    mastered: false,
  );

  WrongQuestion copyWith({bool? mastered}) => WrongQuestion(
    id: id,
    questionCode: questionCode,
    content: content,
    studentAnswer: studentAnswer,
    standardAnswer: standardAnswer,
    explanation: explanation,
    feedback: feedback,
    board: board,
    questionType: questionType,
    difficulty: difficulty,
    knowledgePoints: knowledgePoints,
    source: source,
    recordedAt: recordedAt,
    wrongCount: wrongCount,
    mastered: mastered ?? this.mastered,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'questionCode': questionCode,
    'content': content,
    'studentAnswer': studentAnswer,
    'standardAnswer': standardAnswer,
    'explanation': explanation,
    'feedback': feedback,
    'board': board,
    'questionType': questionType,
    'difficulty': difficulty,
    'knowledgePoints': knowledgePoints,
    'source': source,
    'recordedAt': recordedAt.toIso8601String(),
    'wrongCount': wrongCount,
    'mastered': mastered,
  };

  String encode() => jsonEncode(toJson());

  factory WrongQuestion.fromJson(Map<String, dynamic> json) => WrongQuestion(
    id: json['id']?.toString() ?? '',
    questionCode: json['questionCode']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    studentAnswer: json['studentAnswer']?.toString() ?? '',
    standardAnswer: json['standardAnswer']?.toString() ?? '',
    explanation: json['explanation']?.toString() ?? '',
    feedback: json['feedback']?.toString() ?? '',
    board: json['board']?.toString() ?? '',
    questionType: json['questionType']?.toString() ?? '',
    difficulty: (json['difficulty'] as num?)?.toDouble() ?? 0.5,
    knowledgePoints:
        (json['knowledgePoints'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic item) => item.toString())
            .toList(),
    source: Map<String, dynamic>.from(
      json['source'] as Map<dynamic, dynamic>? ?? const <dynamic, dynamic>{},
    ),
    recordedAt:
        DateTime.tryParse(json['recordedAt']?.toString() ?? '') ??
        DateTime.now(),
    wrongCount: (json['wrongCount'] as num?)?.toInt() ?? 1,
    mastered: json['mastered'] as bool? ?? false,
  );
}
