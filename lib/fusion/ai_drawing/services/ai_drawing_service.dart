import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'package:mathmate/fusion/ai_drawing/prompts/math_prompts.dart';
import 'package:mathmate/fusion/models/ai_models.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/api_config_service.dart';

/// AI 绘图服务
///
/// 使用 DeepSeek API 根据自然语言描述生成 Matplotlib 绘图代码。
/// 复用项目已有的 .env 配置（DEEPSEEK_API_KEY 等）。
class AIDrawingService {
  static const String _apiKeyEnv = 'DEEPSEEK_API_KEY';
  static const String _modelIdEnv = 'DEEPSEEK_MODEL_ID';
  static const String _baseUrlEnv = 'DEEPSEEK_BASE_URL';
  static const String _defaultBaseUrl =
      'https://api.deepseek.com/chat/completions';
  static const String _defaultModel = 'deepseek-v4-flash';

  static bool _dotenvLoaded = false;

  /// 请求超时时间
  static const Duration _timeout = Duration(seconds: 60);

  /// 确保 .env 已加载
  Future<void> _ensureEnvLoaded() async {
    if (_dotenvLoaded) return;
    await dotenv.load(fileName: '.env');
    _dotenvLoaded = true;
  }

  /// 通过自然语言生成可视化代码
  ///
  /// [description] 用户的自然语言描述
  /// [type] 可视化类型
  /// 返回生成的代码
  Future<AIGenerationResult> generateVisualization({
    required String description,
    VisualizationType type = VisualizationType.general,
    Map<String, String>? parameters,
  }) async {
    try {
      // 选择合适的 Prompt 模板
      final promptTemplate = _selectPromptTemplate(type);
      final systemPrompt = MathDrawingPrompts.systemPrompt;
      final userPrompt = MathDrawingPrompts.formatTemplate(
        promptTemplate,
        <String, String>{
          'description': description,
          if (parameters != null) ...parameters,
        },
      );

      // 调用 AI 生成代码
      final rawContent = await _callAI(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );

      // 从返回内容中提取 Python 代码
      final extractedCode = _extractCodeBlock(rawContent);

      if (extractedCode.isEmpty) {
        return AIGenerationResult.failure(
          errorMessage: 'AI 未返回有效代码，请尝试更详细的描述',
          promptType: type.toString(),
        );
      }

      return AIGenerationResult.success(
        code: extractedCode,
        promptType: type.toString(),
      );
    } catch (e) {
      AppLogger.instance.error('[AIDrawing] 生成失败: $e');
      return AIGenerationResult.failure(
        errorMessage: '生成失败: $e',
        promptType: type.toString(),
      );
    }
  }

  /// 优化现有可视化代码
  ///
  /// [currentCode] 当前需要优化的代码
  /// [instruction] 优化指令
  /// 返回优化后的代码
  Future<AIGenerationResult> optimizeCode({
    required String currentCode,
    required String instruction,
  }) async {
    try {
      final userPrompt = MathDrawingPrompts.formatTemplate(
        MathDrawingPrompts.optimizeTemplate,
        <String, String>{
          'current_code': currentCode,
          'instruction': instruction,
        },
      );

      final rawContent = await _callAI(
        systemPrompt: MathDrawingPrompts.systemPrompt,
        userPrompt: userPrompt,
      );

      final extractedCode = _extractCodeBlock(rawContent);

      if (extractedCode.isEmpty) {
        return AIGenerationResult.failure(
          errorMessage: 'AI 未返回有效代码',
          promptType: 'optimize',
        );
      }

      return AIGenerationResult.success(
        code: extractedCode,
        promptType: 'optimize',
      );
    } catch (e) {
      AppLogger.instance.error('[AIDrawing] 优化失败: $e');
      return AIGenerationResult.failure(
        errorMessage: '优化失败: $e',
        promptType: 'optimize',
      );
    }
  }

  /// 修复代码错误
  ///
  /// [currentCode] 当前有错误的代码
  /// [errorText] 错误信息
  /// 返回修复后的代码
  Future<AIGenerationResult> repairCode({
    required String currentCode,
    required String errorText,
  }) async {
    try {
      final userPrompt = MathDrawingPrompts.formatTemplate(
        MathDrawingPrompts.repairTemplate,
        <String, String>{'current_code': currentCode, 'error_text': errorText},
      );

      final rawContent = await _callAI(
        systemPrompt: MathDrawingPrompts.systemPrompt,
        userPrompt: userPrompt,
      );

      final extractedCode = _extractCodeBlock(rawContent);

      if (extractedCode.isEmpty) {
        return AIGenerationResult.failure(
          errorMessage: 'AI 未返回有效代码',
          promptType: 'repair',
        );
      }

      return AIGenerationResult.success(
        code: extractedCode,
        promptType: 'repair',
      );
    } catch (e) {
      AppLogger.instance.error('[AIDrawing] 修复失败: $e');
      return AIGenerationResult.failure(
        errorMessage: '修复失败: $e',
        promptType: 'repair',
      );
    }
  }

  /// 调用 AI 接口（DeepSeek API，OpenAI 兼容格式）
  ///
  /// [systemPrompt] 系统 Prompt
  /// [userPrompt] 用户 Prompt
  /// 返回 AI 生成的原始文本
  Future<String> _callAI({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    await _ensureEnvLoaded();

    final ResolvedApiConfig config = await ApiConfigService.instance.resolve(
      provider: ApiProvider.deepseek,
      fallbackApiKey: dotenv.env[_apiKeyEnv] ?? '',
      fallbackModelId: dotenv.env[_modelIdEnv] ?? _defaultModel,
      fallbackBaseUrl: dotenv.env[_baseUrlEnv] ?? _defaultBaseUrl,
    );
    final String apiKey = config.apiKey;
    final String modelId = config.modelId;
    final String baseUrl = config.baseUrl;

    AppLogger.instance.info('[AIDrawing] 请求模型: $modelId');
    AppLogger.instance.info('[AIDrawing] 请求端点: $baseUrl');

    if (apiKey.isEmpty) {
      throw Exception('缺少环境变量配置: DEEPSEEK_API_KEY，请在 .env 中配置');
    }

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final List<Map<String, String>> messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': systemPrompt},
      <String, String>{'role': 'user', 'content': userPrompt},
    ];

    final Stopwatch sw = Stopwatch()..start();
    final http.Response response = await http
        .post(
          Uri.parse(baseUrl),
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'model': modelId,
            'messages': messages,
            'temperature': 0.3,
            'max_tokens': 2000,
          }),
        )
        .timeout(
          _timeout,
          onTimeout: () {
            throw Exception('AI 请求超时（${_timeout.inSeconds}秒）');
          },
        );
    sw.stop();

    AppLogger.instance.info(
      '[AIDrawing] 响应状态: ${response.statusCode}，耗时 ${sw.elapsedMilliseconds}ms',
    );

    if (response.statusCode != 200) {
      final String detail = utf8.decode(response.bodyBytes);
      AppLogger.instance.error('[AIDrawing] API 错误响应体: $detail');
      throw Exception('AI 接口错误: $detail');
    }

    final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
    final String parsed = _extractContentFromResponse(data).trim();

    if (parsed.isEmpty) {
      throw Exception('AI 返回空内容');
    }

    return parsed;
  }

  /// 从 API 响应中提取内容
  String _extractContentFromResponse(dynamic data) {
    final dynamic chatContent = data['choices']?[0]?['message']?['content'];
    if (chatContent is String && chatContent.trim().isNotEmpty) {
      return chatContent.trim();
    }
    return '';
  }

  /// 从 AI 返回的文本中提取 Python 代码块
  ///
  /// 支持 markdown 代码块 (```python ... ```) 或纯代码
  String _extractCodeBlock(String content) {
    // 尝试匹配 ```python ... ``` 或 ``` ... ```
    final RegExp codeBlockRegex = RegExp(
      r'```(?:python|py)?\s*\n([\s\S]*?)```',
      caseSensitive: false,
    );
    final RegExpMatch? match = codeBlockRegex.firstMatch(content);

    if (match != null && match.groupCount >= 1) {
      return match.group(1)!.trim();
    }

    // 如果没有代码块，检查整个内容是否像代码（包含 import 或 plt）
    if (content.contains('import') || content.contains('plt.')) {
      return content.trim();
    }

    return '';
  }

  /// 选择合适的 Prompt 模板
  String _selectPromptTemplate(VisualizationType type) {
    switch (type) {
      case VisualizationType.function:
        return MathDrawingPrompts.functionPlotTemplate;
      case VisualizationType.geometry:
        return MathDrawingPrompts.geometryPlotTemplate;
      case VisualizationType.dataChart:
        return MathDrawingPrompts.dataVisualizationTemplate;
      case VisualizationType.general:
        return MathDrawingPrompts.visualizeTemplate;
    }
  }

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      final result = await generateVisualization(description: '画一条简单的直线');
      return result.isSuccess;
    } catch (e) {
      debugPrint('[AIDrawing] 连接测试失败: $e');
      return false;
    }
  }
}
