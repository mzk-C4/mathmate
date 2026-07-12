import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/api_config_service.dart';
import 'package:mathmate/services/auth_service.dart';

class DeepSeekService {
  static const String _apiKeyEnv = 'DEEPSEEK_API_KEY';
  static const String _modelIdEnv = 'DEEPSEEK_MODEL_ID';
  static const String _baseUrlEnv = 'DEEPSEEK_BASE_URL';
  static const String _defaultBaseUrl =
      'https://api.deepseek.com/chat/completions';

  static bool _dotenvLoaded = false;

  Future<void> _ensureEnvLoaded() async {
    if (_dotenvLoaded) return;
    await dotenv.load(fileName: '.env');
    _dotenvLoaded = true;
  }

  Future<String> callTextPrompt({
    required String prompt,
    required String userText,
  }) async {
    await _ensureEnvLoaded();

    final ResolvedApiConfig config = await ApiConfigService.instance.resolve(
      provider: ApiProvider.deepseek,
      fallbackApiKey: dotenv.env[_apiKeyEnv] ?? '',
      fallbackModelId: dotenv.env[_modelIdEnv] ?? '',
      fallbackBaseUrl: dotenv.env[_baseUrlEnv] ?? _defaultBaseUrl,
    );
    final String apiKey = config.apiKey;
    final String modelId = config.modelId;
    final String baseUrl = config.baseUrl;

    AppLogger.instance.info('[DeepSeek] 请求模型: $modelId');
    AppLogger.instance.info('[DeepSeek] 请求端点: $baseUrl');
    AppLogger.instance.info('[DeepSeek] system prompt 长度: ${prompt.length} 字符');
    AppLogger.instance.info('[DeepSeek] user text 长度: ${userText.length} 字符');
    if (userText.length <= 300) {
      AppLogger.instance.info('[DeepSeek] user text 内容: $userText');
    } else {
      AppLogger.instance.info(
        '[DeepSeek] user text 预览(前300字): ${userText.substring(0, 300)}...',
      );
    }

    if (apiKey.isEmpty) {
      throw Exception('Missing env config: DEEPSEEK_API_KEY');
    }
    if (modelId.isEmpty) {
      throw Exception('Missing env config: DEEPSEEK_MODEL_ID');
    }

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      ...AuthService().proxyAuthHeaders,
    };

    final List<Map<String, String>> messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': prompt},
      <String, String>{'role': 'user', 'content': userText},
    ];

    final Stopwatch sw = Stopwatch()..start();
    final http.Response response = await http
        .post(
          Uri.parse(baseUrl),
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'model': modelId,
            'messages': messages,
          }),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw Exception('DeepSeek API 请求超时（60秒）');
          },
        );
    sw.stop();
    AppLogger.instance.info(
      '[DeepSeek] 响应状态: ${response.statusCode}，耗时 ${sw.elapsedMilliseconds}ms',
    );

    if (response.statusCode != 200) {
      final String detail = utf8.decode(response.bodyBytes);
      AppLogger.instance.error('[DeepSeek] API 错误响应体: $detail');
      throw Exception('DeepSeek API error: $detail');
    }

    final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
    final String parsed = _extractContentFromResponse(data).trim();
    AppLogger.instance.info('[DeepSeek] 提取内容长度: ${parsed.length} 字符');
    if (parsed.length <= 500) {
      AppLogger.instance.info('[DeepSeek] 响应内容: $parsed');
    } else {
      AppLogger.instance.info(
        '[DeepSeek] 响应预览(前500字): ${parsed.substring(0, 500)}...',
      );
    }

    if (parsed.isEmpty) {
      AppLogger.instance.warn(
        '[DeepSeek] 返回空内容！原始响应: ${utf8.decode(response.bodyBytes)}',
      );
      throw Exception('DeepSeek API returned empty content.');
    }
    return parsed;
  }

  String _extractContentFromResponse(dynamic data) {
    final dynamic chatContent = data['choices']?[0]?['message']?['content'];
    if (chatContent is String && chatContent.trim().isNotEmpty) {
      return chatContent.trim();
    }
    return '';
  }
}
