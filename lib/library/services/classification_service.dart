import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mathmate/library/models/study_material.dart';
import 'package:mathmate/library/prompts/classification_prompt.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/deepseek_service.dart';

/// 资料自动分类服务 —— 复刻 ProfileBuilderService 的 DeepSeek + JSON 范式
///
/// 一次调用产出 9 维标签（学科/知识点/类型/学校/课程/年份/难度/摘要/关键概念）。
/// 分类失败返回 null，调用方可用 MaterialTags.unknown() 兜底仍允许入库。
class ClassificationService {
  final DeepSeekService _deepseek;

  ClassificationService({DeepSeekService? deepseek})
    : _deepseek = deepseek ?? DeepSeekService();

  /// 对一份资料进行分类打标签
  Future<MaterialTags?> classify({
    required MaterialKind kind,
    required String extractedText,
    required String fileName,
    int pageCount = 0,
  }) async {
    try {
      final StringBuffer userText = StringBuffer()
        ..writeln('文件名: $fileName')
        ..writeln('资料类型: ${kind.displayName}');
      if (pageCount > 0) userText.writeln('页数: $pageCount');
      userText.writeln('内容:');
      // 文本不足时（如 PDF 未提取），至少给文件名供推断
      if (extractedText.trim().isNotEmpty) {
        userText.writeln(_truncate(extractedText, 6000));
      } else {
        userText.writeln('（正文暂未提取，请主要依据文件名和资料类型推断分类）');
      }

      AppLogger.instance.info('[Classify] 开始分类: $fileName');
      final String raw = await _deepseek.callTextPrompt(
        prompt: ClassificationPrompt.system,
        userText: userText.toString(),
      );
      final String jsonStr = _extractJson(raw);
      final Map<String, dynamic> parsed =
          jsonDecode(jsonStr) as Map<String, dynamic>;
      final MaterialTags tags = MaterialTags.fromJson(parsed);
      AppLogger.instance.info(
        '[Classify] 分类完成: 学科=${tags.subject} | 类型=${tags.materialType} | 知识点=${tags.knowledgePoints}',
      );
      return tags;
    } catch (e) {
      AppLogger.instance.error('[Classify] 分类失败: $e');
      debugPrint('[Classify] 失败: $e');
      return null;
    }
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…(已截断)';

  /// 从大模型响应中提取 JSON（复刻 ProfileBuilderService._extractJson）
  ///
  /// 兼容三种情况：纯 JSON、```json 代码块、JSON 前后带说明文字
  String _extractJson(String content) {
    final RegExp jsonBlockReg = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final RegExpMatch? blockMatch = jsonBlockReg.firstMatch(content);
    String candidate = blockMatch != null && blockMatch.groupCount >= 1
        ? blockMatch.group(1)!
        : content;
    final int start = candidate.indexOf('{');
    final int end = candidate.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return candidate.substring(start, end + 1);
    }
    return candidate.trim();
  }
}
