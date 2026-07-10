import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mathmate/exam/models/question.dart';

/// 题库 API 客户端（接云端 mathmate.top）
///
/// 端点见 docs/library_api.md。
/// 队员开发考试功能（组卷/判卷/评估）时复用此类。
class QuestionApi {
  static const String baseUrl = 'https://mathmate.top/api/library';

  /// 题库列表（支持板块/题型/难度/关键词过滤 + 分页）
  Future<({List<Question> items, int total})> fetchQuestions({
    String? section,
    String? type,
    double? dmin,
    double? dmax,
    String? q,
    int page = 1,
    int limit = 50,
  }) async {
    final Map<String, String> params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (section != null && section.isNotEmpty) params['section'] = section;
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (dmin != null) params['dmin'] = '$dmin';
    if (dmax != null) params['dmax'] = '$dmax';
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();

    final Uri uri =
        Uri.parse('$baseUrl/questions').replace(queryParameters: params);
    final http.Response resp =
        await http.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('fetchQuestions ${resp.statusCode}: ${resp.body}');
    }
    final Map<String, dynamic> data =
        jsonDecode(resp.body) as Map<String, dynamic>;
    final List<dynamic> items = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return (
      items: items
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// 单题
  Future<Question> fetchQuestion(String id) async {
    final http.Response resp =
        await http.get(Uri.parse('$baseUrl/questions/$id')).timeout(
      const Duration(seconds: 30),
    );
    if (resp.statusCode != 200) {
      throw Exception('fetchQuestion ${resp.statusCode}');
    }
    return Question.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 板块树（带题量）
  Future<List<SectionStat>> fetchSections() async {
    final http.Response resp =
        await http.get(Uri.parse('$baseUrl/sections')).timeout(
      const Duration(seconds: 30),
    );
    if (resp.statusCode != 200) return const <SectionStat>[];
    final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => SectionStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 统计
  Future<Map<String, dynamic>> fetchStats() async {
    final http.Response resp =
        await http.get(Uri.parse('$baseUrl/stats')).timeout(
      const Duration(seconds: 30),
    );
    if (resp.statusCode != 200) return <String, dynamic>{};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// 健康检查（题量）
  Future<int> healthTotal() async {
    try {
      final http.Response resp =
          await http.get(Uri.parse('$baseUrl/health')).timeout(
        const Duration(seconds: 15),
      );
      if (resp.statusCode != 200) return -1;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return -1;
    }
  }
}
