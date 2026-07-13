import 'dart:convert';

/// 资料类型
enum MaterialKind {
  pptx('PPT 课件'),
  pdf('PDF 文档'),
  image('板书 / 图片'),
  audio('划重点录音');

  const MaterialKind(this.displayName);
  final String displayName;
}

/// AI 分类服务产出的标签集合
class MaterialTags {
  final String subject;
  final List<String> knowledgePoints;
  final String materialType;
  final String? university;
  final String? course;
  final String? year;
  final String difficulty;
  final String summary;
  final List<String> keyConcepts;

  const MaterialTags({
    this.subject = '',
    this.knowledgePoints = const [],
    this.materialType = '',
    this.university,
    this.course,
    this.year,
    this.difficulty = '',
    this.summary = '',
    this.keyConcepts = const [],
  });

  factory MaterialTags.fromJson(Map<String, dynamic> json) {
    List<String> asList(dynamic v) => (v as List<dynamic>? ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    String? asStr(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty || s == 'null') ? null : s;
    }

    return MaterialTags(
      subject: (json['subject']?.toString().trim()) ?? '',
      knowledgePoints: asList(json['knowledgePoints']),
      materialType: (json['materialType']?.toString().trim()) ?? '',
      university: asStr(json['university']),
      course: asStr(json['course']),
      year: asStr(json['year']),
      difficulty: (json['difficulty']?.toString().trim()) ?? '',
      summary: (json['summary']?.toString().trim()) ?? '',
      keyConcepts: asList(json['keyConcepts']),
    );
  }

  /// 空标签（分类失败时兜底，仍允许入库）
  factory MaterialTags.unknown() => const MaterialTags(
    subject: '未分类',
    materialType: '未分类',
    summary: 'AI 分类失败，已按原文件入库',
  );

  bool get isUnknown => subject == '未分类';
}

/// 一份学习资料（用户上传的多模态原始资料）
class StudyMaterial {
  final String id;
  final String title;

  // —— 原始文件 ——
  final MaterialKind kind;
  final String localPath;
  final int sizeBytes;
  final DateTime uploadedAt;

  // —— 解析产物 ——
  final String extractedText;
  final int pageCount;

  // —— AI 自动标签 ——
  final String subject;
  final List<String> knowledgePoints; // 枢纽字段：喂画像/出题/路径
  final String materialType;
  final String? university; // ★高校专属
  final String? course;
  final String? year;
  final String difficulty;
  final String summary;
  final List<String> keyConcepts;

  // —— 使用行为（反哺画像）——
  final int openCount;
  final DateTime? lastOpenedAt;

  const StudyMaterial({
    required this.id,
    required this.title,
    required this.kind,
    required this.localPath,
    required this.sizeBytes,
    required this.uploadedAt,
    this.extractedText = '',
    this.pageCount = 0,
    this.subject = '',
    this.knowledgePoints = const [],
    this.materialType = '',
    this.university,
    this.course,
    this.year,
    this.difficulty = '',
    this.summary = '',
    this.keyConcepts = const [],
    this.openCount = 0,
    this.lastOpenedAt,
  });

  /// 由原始信息 + AI 标签组装
  factory StudyMaterial.create({
    required MaterialKind kind,
    required String localPath,
    required String fileName,
    required int sizeBytes,
    required String extractedText,
    int pageCount = 0,
    required MaterialTags tags,
  }) {
    final now = DateTime.now();
    final String title = tags.summary.isNotEmpty
        ? '${tags.subject.isNotEmpty ? tags.subject : fileName} · ${tags.summary}'
        : fileName;
    return StudyMaterial(
      id: 'm_${now.millisecondsSinceEpoch}',
      title: title,
      kind: kind,
      localPath: localPath,
      sizeBytes: sizeBytes,
      uploadedAt: now,
      extractedText: extractedText,
      pageCount: pageCount,
      subject: tags.subject,
      knowledgePoints: tags.knowledgePoints,
      materialType: tags.materialType,
      university: tags.university,
      course: tags.course,
      year: tags.year,
      difficulty: tags.difficulty,
      summary: tags.summary,
      keyConcepts: tags.keyConcepts,
    );
  }

  StudyMaterial copyWith({
    String? title,
    int? openCount,
    DateTime? lastOpenedAt,
  }) {
    return StudyMaterial(
      id: id,
      title: title ?? this.title,
      kind: kind,
      localPath: localPath,
      sizeBytes: sizeBytes,
      uploadedAt: uploadedAt,
      extractedText: extractedText,
      pageCount: pageCount,
      subject: subject,
      knowledgePoints: knowledgePoints,
      materialType: materialType,
      university: university,
      course: course,
      year: year,
      difficulty: difficulty,
      summary: summary,
      keyConcepts: keyConcepts,
      openCount: openCount ?? this.openCount,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'localPath': localPath,
    'sizeBytes': sizeBytes,
    'uploadedAt': uploadedAt.toIso8601String(),
    'extractedText': extractedText,
    'pageCount': pageCount,
    'subject': subject,
    'knowledgePoints': knowledgePoints,
    'materialType': materialType,
    'university': university,
    'course': course,
    'year': year,
    'difficulty': difficulty,
    'summary': summary,
    'keyConcepts': keyConcepts,
    'openCount': openCount,
    'lastOpenedAt': lastOpenedAt?.toIso8601String(),
  };

  factory StudyMaterial.fromJson(Map<String, dynamic> json) {
    String? asStr(dynamic v) {
      final s = v?.toString();
      return (s == null || s.isEmpty || s == 'null') ? null : s;
    }

    return StudyMaterial(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      kind: MaterialKind.values.firstWhere(
        (k) => k.name == (json['kind'] as String?),
        orElse: () => MaterialKind.image,
      ),
      localPath: json['localPath'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt:
          DateTime.tryParse(json['uploadedAt'] as String? ?? '') ??
          DateTime.now(),
      extractedText: json['extractedText'] as String? ?? '',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      subject: json['subject'] as String? ?? '',
      knowledgePoints: (json['knowledgePoints'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      materialType: json['materialType'] as String? ?? '',
      university: asStr(json['university']),
      course: asStr(json['course']),
      year: asStr(json['year']),
      difficulty: json['difficulty'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      keyConcepts: (json['keyConcepts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      openCount: (json['openCount'] as num?)?.toInt() ?? 0,
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? ''),
    );
  }

  /// 序列化为 JSON 字符串（Hive 的字符串 Box 存储）。
  String encode() => jsonEncode(toJson());

  static StudyMaterial? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return StudyMaterial.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
