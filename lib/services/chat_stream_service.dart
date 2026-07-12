import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/api_config_service.dart';

/// API 消息（发给 LLM 的消息，去 vivo 品牌，替代 VivoChatMessage）
///
/// 注意：和 hive_conversation_models.dart 的 ChatMessage（UI 模型）不同，
/// 这里用 LlmMessage 避免命名冲突。
class LlmMessage {
  final String role;
  final String content;
  const LlmMessage({required this.role, required this.content});
  Map<String, String> toMap() => <String, String>{
    'role': role,
    'content': content,
  };
}

class StreamChunk {
  final String? content;
  final String? reasoning;
  final bool isDone;
  final String? error;

  const StreamChunk({
    this.content,
    this.reasoning,
    this.isDone = false,
    this.error,
  });
}

/// 聊天流式服务（DeepSeek，SSE 流式打字机效果）
///
/// 接 MathMate 主力 LLM DeepSeek（DEEPSEEK_API_KEY/MODEL_ID/BASE_URL）。
/// 兼容任何 OpenAI 协议的 chat/completions 端点（stream=true，SSE data: 解析）。
class ChatStreamService {
  // DeepSeek 端点
  static const String _deepseekApiKeyEnv = 'DEEPSEEK_API_KEY';
  static const String _deepseekBaseUrlEnv = 'DEEPSEEK_BASE_URL';
  static const String _defaultDeepseekBaseUrl =
      'https://api.deepseek.com/chat/completions';
  // Qwen 端点（DashScope OpenAI 兼容模式）
  static const String _qwenApiKeyEnv = 'QWEN_API_KEY';
  static const String _qwenBaseUrlEnv = 'QWEN_BASE_URL';
  static const String _defaultQwenBaseUrl =
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';
  // 火山 Ark 端点（Doubao-Seed + DeepSeek-V4 系列）
  static const String _volcApiKeyEnv = 'VOLC_API_KEY';
  static const String _volcBaseUrlEnv = 'VOLC_BASE_URL';
  static const String _defaultVolcBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions';

  static bool _dotenvLoaded = false;
  http.Client? _client;
  bool _cancelled = false;

  Future<void> _ensureEnvLoaded() async {
    if (_dotenvLoaded) return;
    await dotenv.load(fileName: '.env');
    _dotenvLoaded = true;
  }

  /// 流式发送消息，逐 chunk yield（content/reasoning 增量，最后 isDone）
  Stream<StreamChunk> sendMessageStream({
    required List<LlmMessage> messages,
    String? modelId,
  }) async* {
    await _ensureEnvLoaded();
    _cancelled = false;

    // 按 modelId 选端点：qwen-* → QWEN_*，doubao-*/deepseek-v4-* → VOLC_*(Ark)，其余 → DEEPSEEK_*
    final String requestedModel = (modelId ?? 'deepseek-v4-flash').trim();
    final String m = requestedModel.toLowerCase();
    final bool isQwen = m.startsWith('qwen');
    final bool isArk =
        m.startsWith('doubao') ||
        m.startsWith('deepseek-v4') ||
        m.startsWith('glm-');
    final String apiKeyEnv = isQwen
        ? _qwenApiKeyEnv
        : (isArk ? _volcApiKeyEnv : _deepseekApiKeyEnv);
    final String baseUrlEnv = isQwen
        ? _qwenBaseUrlEnv
        : (isArk ? _volcBaseUrlEnv : _deepseekBaseUrlEnv);
    final String defaultBaseUrl = isQwen
        ? _defaultQwenBaseUrl
        : (isArk ? _defaultVolcBaseUrl : _defaultDeepseekBaseUrl);
    final ApiProvider provider = isQwen
        ? ApiProvider.qwen
        : (isArk ? ApiProvider.volc : ApiProvider.deepseek);
    final ResolvedApiConfig config = await ApiConfigService.instance.resolve(
      provider: provider,
      fallbackApiKey: dotenv.env[apiKeyEnv] ?? '',
      fallbackBaseUrl: dotenv.env[baseUrlEnv] ?? defaultBaseUrl,
      fallbackModelId: requestedModel,
    );
    final String apiKey = config.apiKey;
    final String baseUrl = config.baseUrl;
    final String model = config.modelId;

    if (apiKey.isEmpty) {
      yield StreamChunk(error: 'Missing env config: $apiKeyEnv');
      return;
    }

    final List<Map<String, String>> formattedMessages = messages
        .map((LlmMessage m) => m.toMap())
        .toList();

    final http.Request request = http.Request('POST', Uri.parse(baseUrl))
      ..headers.addAll(<String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode(<String, dynamic>{
        'model': model,
        'messages': formattedMessages,
        'temperature': 0.7,
        'max_tokens': 2048,
        'stream': true,
      });

    _client = http.Client();

    try {
      final http.StreamedResponse response = await _client!.send(request);

      if (response.statusCode != 200) {
        final String body = await response.stream.bytesToString();
        debugPrint('ChatStreamService error: $body');
        yield StreamChunk(error: 'API error: ${response.statusCode}');
        return;
      }

      final Stream<String> lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final String line in lines) {
        if (_cancelled) break;
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final String data = line.substring(5).trim();
        if (data == '[DONE]') {
          yield const StreamChunk(isDone: true);
          break;
        }

        try {
          final Map<String, dynamic> json = jsonDecode(data);
          final dynamic delta = json['choices']?[0]?['delta'];
          if (delta == null) continue;

          final String? content = delta['content'] as String?;
          final String? reasoning = delta['reasoning_content'] as String?;

          if (content != null || reasoning != null) {
            yield StreamChunk(content: content, reasoning: reasoning);
          }
        } catch (_) {
          // Skip malformed chunks
        }
      }
    } on http.ClientException catch (e) {
      if (!_cancelled) {
        yield StreamChunk(error: '网络连接失败: $e');
      }
    } catch (e) {
      if (!_cancelled) {
        yield StreamChunk(error: '请求失败: $e');
      }
    } finally {
      _closeClient();
    }
  }

  void cancel() {
    _cancelled = true;
    _closeClient();
  }

  void _closeClient() {
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }
}
