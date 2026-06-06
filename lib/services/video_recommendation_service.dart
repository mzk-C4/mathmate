import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/data/hive_models.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:mathmate/data/video_resources.dart';
import 'package:mathmate/services/provider_config_service.dart';

class VideoRecommendationService {
  /// 通过千问推荐视频 - 结合年级和历史记录
  /// 返回推荐的视频资源列表
  Future<List<VideoResource>> recommendVideos() async {
    try {
      final pc = ProviderConfigService.instance;
      final String apiKey = pc.chatApiKey;
      if (apiKey.isEmpty) {
        debugPrint('VideoRecommendationService: missing VIVO_API_KEY.');
        return <VideoResource>[];
      }

      final String modelId = pc.chatModelId;
      final String baseUrl = pc.chatBaseUrl;

      // 获取年级信息
      final int? grade = await HistoryRepository.instance.getGradeLevel();
      final String gradeText = _formatGrade(grade);

      // 获取历史记录中的题目内容
      final List<String> historyContents = await _getRecentHistoryContents();

      // 构建prompt
      final String prompt = _buildRecommendationPrompt(gradeText, historyContents);

      // 调用千问API
      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
      };

      final Map<String, dynamic> body = <String, dynamic>{
        'model': modelId,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
        'max_tokens': 1500,
      };

      final http.Response response = await http.post(
        Uri.parse(baseUrl),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String content = data['choices']?[0]?['message']?['content'] ?? '';
        return _parseRecommendedVideos(content);
      } else {
        debugPrint('VideoRecommendationService API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('VideoRecommendationService error: $e');
    }
    return <VideoResource>[];
  }

  /// 格式化年级为中文描述
  String _formatGrade(int? grade) {
    if (grade == null) return '未知年级';
    if (grade >= 1 && grade <= 6) return '小学${grade}年级';
    if (grade >= 7 && grade <= 9) return '初中${grade - 6}年级';
    if (grade >= 10 && grade <= 12) return '高中${grade - 9}年级';
    if (grade >= 13 && grade <= 16) return '大学${grade - 12}年级';
    if (grade == 17) return '研究生';
    return '未知年级';
  }

  /// 获取最近的历史记录内容
  Future<List<String>> _getRecentHistoryContents() async {
    final List<MathHistory> histories = await HistoryRepository.instance
        .watchHistories()
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => <MathHistory>[]);

    // 取最近10条记录的OCR内容
    return histories
        .take(10)
        .map((MathHistory h) => h.ocrContent)
        .where((String c) => c.isNotEmpty)
        .toList();
  }

  /// 构建推荐prompt
  String _buildRecommendationPrompt(String gradeText, List<String> historyContents) {
    final String historyText = historyContents.isEmpty
        ? '暂无历史记录'
        : historyContents.join('\n');

    // 格式化视频资料库
    final StringBuffer videoDb = StringBuffer();
    videoDb.writeln('视频资料库内容：');
    videoDb.writeln();

    for (final String grade in getAllGrades()) {
      videoDb.writeln('【$grade】');
      final List<String> modules = getModulesByGrade(grade);
      for (final String module in modules) {
        videoDb.writeln('  $module:');
        final List<VideoResource> videos = getVideoResourcesByModule(module);
        for (final VideoResource video in videos) {
          final String bvStr = video.bvId.isEmpty ? '(暂无BV号)' : '(${video.bvId})';
          videoDb.writeln('    - ${video.title} ${bvStr} - ${video.uploader}');
        }
      }
      videoDb.writeln();
    }

    return '''
你是一个专业的数学视频推荐助手。用户是$gradeText的学生。

用户最近的搜题历史：
$historyText

$videoDb

请根据用户的年级和最近的搜题历史，从视频资料库中选择最合适的视频进行推荐。

要求：
1. 优先选择与用户近期搜题内容相关的视频
2. 结合年级选择对应学段的视频
3. 选择用户可能薄弱或需要加强的知识点的视频

请以JSON数组格式返回推荐结果，数组中每个元素包含title（知识点标题）和reason（推荐理由）。
只返回JSON数组，不要包含其他文字。

返回格式示例：
[
  {"title": "正弦/余弦定理", "reason": "你最近在复习三角函数，这个视频能帮助你掌握正弦余弦定理"},
  {"title": "导数综合讲解", "reason": "导数是高中数学的重点，建议加强练习"}
]

请只返回JSON数组：''';
  }

  /// 解析千问返回的推荐结果
  Future<List<VideoResource>> _parseRecommendedVideos(String content) async {
    if (content.isEmpty) return <VideoResource>[];

    try {
      // 尝试提取JSON数组
      String jsonStr = content.trim();

      // 移除可能的markdown代码块标记
      if (jsonStr.startsWith('```')) {
        final int firstNewline = jsonStr.indexOf('\n');
        if (firstNewline != -1) {
          jsonStr = jsonStr.substring(firstNewline + 1);
        }
      }
      if (jsonStr.endsWith('```')) {
        jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      }
      jsonStr = jsonStr.trim();

      // 解析JSON
      final List<dynamic> parsed = jsonDecode(jsonStr);
      final List<String> recommendedTitles = <String>[];

      for (final dynamic item in parsed) {
        if (item is Map<String, dynamic> && item['title'] != null) {
          recommendedTitles.add(item['title'].toString());
        }
      }

      // 在视频资料库中匹配
      final List<VideoResource> matched = <VideoResource>[];
      for (final String title in recommendedTitles) {
        for (final VideoResource video in allVideoResources) {
          if (video.title == title && !matched.contains(video)) {
            matched.add(video);
            break;
          }
        }
      }

      // 如果匹配到的视频太少（少于3个），补充一些同年级的基础视频
      if (matched.length < 3) {
        final int? grade = await HistoryRepository.instance.getGradeLevel();
        String targetGrade = '高中';
        if (grade != null) {
          if (grade >= 1 && grade <= 6) {
            targetGrade = '小学';
          } else if (grade >= 7 && grade <= 9) {
            targetGrade = '初中';
          } else if (grade >= 13) {
            targetGrade = '大学';
          }
        }

        for (final VideoResource video in allVideoResources) {
          if (video.grade == targetGrade && !matched.contains(video)) {
            matched.add(video);
            if (matched.length >= 5) break;
          }
        }
      }

      return matched.take(5).toList();
    } catch (e) {
      debugPrint('parseRecommendedVideos error: $e');
      return <VideoResource>[];
    }
  }

  // ========== 以下为兼容旧代码的方法 ==========

  /// 兼容旧代码：提取关键词
  Future<List<String>> extractKeywords(String text) async {
    try {
      final pc = ProviderConfigService.instance;
      final String apiKey = pc.chatApiKey;
      if (apiKey.isEmpty) {
        debugPrint('VideoRecommendationService: missing VIVO_API_KEY.');
        return <String>[];
      }

      final String modelId = pc.chatModelId;
      final String baseUrl = pc.chatBaseUrl;

      final String prompt = '''
请从以下数学题目中提取关键词（数学概念、题型类别等），只返回关键词，用逗号分隔，最多返回5个关键词。

题目内容：
$text

关键词：''';

      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
      };

      final Map<String, dynamic> body = <String, dynamic>{
        'model': modelId,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
        'temperature': 0.3,
        'max_tokens': 100,
      };

      final http.Response response = await http.post(
        Uri.parse(baseUrl),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String content = data['choices']?[0]?['message']?['content'] ?? '';
        return content
            .split(RegExp(r'[,，、\n]'))
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .take(5)
            .toList();
      }
    } catch (e) {
      debugPrint('extractKeywords error: $e');
    }
    return <String>[];
  }
}
