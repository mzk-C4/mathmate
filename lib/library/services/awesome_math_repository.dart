import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:mathmate/library/models/awesome_resource.dart';

/// awesome-math 预置资源仓储
///
/// 静态公共数据（CC0），从 assets/awesome_math.json 一次性加载后常驻内存。
/// 与 MaterialRepository（用户私有上传、Hive 持久化）完全隔离。
/// 加载模式对齐 katex_pdf_service 的 _cachedJs ??= 缓存。
class AwesomeMathRepository {
  AwesomeMathRepository._();
  static final AwesomeMathRepository instance = AwesomeMathRepository._();

  static const String _assetPath = 'assets/awesome_math.json';

  List<AwesomeMathResource>? _cache;
  bool get isLoaded => _cache != null;
  List<AwesomeMathResource> get all =>
      _cache ?? const <AwesomeMathResource>[];

  /// 幂等加载
  Future<List<AwesomeMathResource>> load() async {
    if (_cache != null) return _cache!;
    final String raw = await rootBundle.loadString(_assetPath);
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    _cache = (json['items'] as List<dynamic>)
        .map((e) => AwesomeMathResource.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return _cache!;
  }

  /// 二级分类（去重 + 保留 README 出现顺序），供分类 chip
  List<String> get categories {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final AwesomeMathResource r in all) {
      final String s2 = r.section2 ?? '';
      if (s2.isNotEmpty && seen.add(s2)) out.add(s2);
    }
    return out;
  }

  /// 综合检索：学段 + 类型 + 分类 + 关键词（全在内存，同步）
  List<AwesomeMathResource> filter({
    LearnStage? stage,
    ResourceType? type,
    String? category,
    String? keyword,
  }) {
    List<AwesomeMathResource> list = all;
    if (stage != null) {
      // general 资源在任一学段筛选下都透出（跨学段通用）
      list = list
          .where((r) => r.stage == stage || r.stage == LearnStage.general)
          .toList();
    }
    if (type != null) {
      list = list.where((r) => r.type == type).toList();
    }
    if (category != null && category.isNotEmpty) {
      list = list.where((r) => r.section2 == category).toList();
    }
    final String kw = (keyword ?? '').trim().toLowerCase();
    if (kw.isNotEmpty) {
      list = list.where((r) {
        final String hay = <String>[
          r.title, r.author, r.institution, r.note,
          r.section1, r.section2 ?? '', r.section3 ?? '',
        ].join(' ').toLowerCase();
        return hay.contains(kw);
      }).toList();
    }
    return list;
  }
}
