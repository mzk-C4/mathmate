import 'dart:convert';

/// 题目模型（对应云端 API Question Schema）
class Question {
  final String id;
  final String subject;
  final String section; // 板块：函数与导数/解析几何/...
  final String type; // 单选题/多选题/填空题/解答题
  final String content; // 题干（含 LaTeX）
  final List<String>? options; // 选择题选项；非选择题 null
  final String answer;
  final String solution;
  final double difficulty; // 难度系数 0~1
  final List<String> knowledgePoints;
  final Map<String, dynamic>? source;

  const Question({
    required this.id,
    this.subject = '数学',
    this.section = '',
    this.type = '',
    this.content = '',
    this.options,
    this.answer = '',
    this.solution = '',
    this.difficulty = 0.5,
    this.knowledgePoints = const [],
    this.source,
  });

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id']?.toString() ?? '',
        subject: j['subject']?.toString() ?? '数学',
        section: j['section']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        options: (j['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
        answer: j['answer']?.toString() ?? '',
        solution: j['solution']?.toString() ?? '',
        difficulty: (j['difficulty'] as num?)?.toDouble() ?? 0.5,
        knowledgePoints: (j['knowledgePoints'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
        source: j['source'] as Map<String, dynamic>?,
      );

  /// 难度档位（用于筛选 + 色点）
  String get difficultyLabel {
    if (difficulty < 0.4) return '基础';
    if (difficulty < 0.6) return '中等';
    if (difficulty < 0.8) return '较难';
    return '挑战';
  }

  /// 答题类型图标
  String get typeIcon {
    switch (type) {
      case '单选题':
        return '◉';
      case '多选题':
        return '✚';
      case '填空题':
        return '▭';
      case '解答题':
        return '✎';
      default:
        return '•';
    }
  }
}

/// 板块统计项
class SectionStat {
  final String section;
  final int count;
  const SectionStat({required this.section, required this.count});
  factory SectionStat.fromJson(Map<String, dynamic> j) => SectionStat(
        section: j['section']?.toString() ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// 答题选项解析（"A. xxx" → letter/文本）
class ParsedOption {
  final String letter;
  final String text;
  const ParsedOption(this.letter, this.text);
}

List<ParsedOption> parseOptions(List<String>? options) {
  if (options == null) return const <ParsedOption>[];
  final List<ParsedOption> out = <ParsedOption>[];
  for (final o in options) {
    final m = RegExp(r'^([A-D])[\.、．]\s*(.*)').firstMatch(o);
    if (m != null) {
      out.add(ParsedOption(m.group(1)!, m.group(2)!));
    } else {
      out.add(ParsedOption('', o));
    }
  }
  return out;
}

// 便于 source 字段序列化展示
String prettySource(Map<String, dynamic>? s) {
  if (s == null) return '';
  return jsonEncode(s);
}
