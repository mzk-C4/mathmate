import 'package:flutter/material.dart';

/// 资源类型（由 awesome-math README 的 emoji 推导）
enum ResourceType {
  book('书'), // 📖
  video('视频'), // 🎥
  notes('讲义'), // 📝
  link('链接'); // 无 emoji
  const ResourceType(this.label);
  final String label;

  factory ResourceType.fromName(String? name) {
    return ResourceType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ResourceType.link,
    );
  }

  IconData get icon => const <ResourceType, IconData>{
        ResourceType.book: Icons.menu_book_rounded,
        ResourceType.video: Icons.play_circle_outline_rounded,
        ResourceType.notes: Icons.description_outlined,
        ResourceType.link: Icons.link_rounded,
      }[this]!;
}

/// 学习学段（general = 工具/平台/百科等跨学段资源，筛选时任一学段都透出）
enum LearnStage {
  middle('中学'),
  undergrad('本科'),
  grad('研究生'),
  general('通用');
  const LearnStage(this.label);
  final String label;

  factory LearnStage.fromName(String? name) {
    return LearnStage.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LearnStage.undergrad,
    );
  }
}

/// 一条 awesome-math 资源（预置公共数据，与用户上传的 StudyMaterial 隔离）
class AwesomeMathResource {
  final String id;
  final String title;
  final String url;
  final ResourceType type;
  final bool paid;
  final String author;
  final String institution;
  final String note;
  final String section1;
  final String? section2;
  final String? section3;
  final LearnStage stage;

  const AwesomeMathResource({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    required this.paid,
    required this.author,
    required this.institution,
    required this.note,
    required this.section1,
    required this.section2,
    required this.section3,
    required this.stage,
  });

  /// 分类路径（如 "Branches of Mathematics / Algebra"）
  String get path => (section2 != null && section2!.isNotEmpty)
      ? '$section1 / $section2'
      : section1;

  /// 副标题（作者 · 机构）
  String get subtitle =>
      <String>[author, institution].where((s) => s.isNotEmpty).join(' · ');

  factory AwesomeMathResource.fromJson(Map<String, dynamic> j) {
    String? asStr(dynamic v) {
      final String? s = v?.toString();
      return (s == null || s.isEmpty || s == 'null') ? null : s;
    }
    return AwesomeMathResource(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      url: j['url'] as String? ?? '',
      type: ResourceType.fromName(j['type'] as String?),
      paid: j['paid'] as bool? ?? false,
      author: j['author'] as String? ?? '',
      institution: j['institution'] as String? ?? '',
      note: j['note'] as String? ?? '',
      section1: j['section1'] as String? ?? '',
      section2: asStr(j['section2']),
      section3: asStr(j['section3']),
      stage: LearnStage.fromName(j['stage'] as String?),
    );
  }
}
