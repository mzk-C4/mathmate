import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/provider_config_service.dart';

class DeepSeekService {
  static bool _dotenvLoaded = false;

  http.Client _createClient() {
    final HttpClient client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    return IOClient(client);
  }

  Future<void> _ensureEnvLoaded() async {
    if (_dotenvLoaded) return;
    _dotenvLoaded = true;
  }

  Future<String> callTextPrompt({
    required String prompt,
    required String userText,
  }) async {
    await _ensureEnvLoaded();

    final pc = ProviderConfigService.instance;
    final String apiKey = pc.reasoningApiKey;
    final String modelId = pc.reasoningModelId;
    final String baseUrl = pc.reasoningBaseUrl;

    AppLogger.instance.info('[DeepSeek] 请求模型: $modelId');
    AppLogger.instance.info('[DeepSeek] 请求端点: $baseUrl');
    AppLogger.instance.info('[DeepSeek] system prompt 长度: ${prompt.length} 字符');
    AppLogger.instance.info('[DeepSeek] user text 长度: ${userText.length} 字符');
    if (userText.length <= 300) {
      AppLogger.instance.info('[DeepSeek] user text 内容: $userText');
    } else {
      AppLogger.instance.info('[DeepSeek] user text 预览(前300字): ${userText.substring(0, 300)}...');
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
    };

    final List<Map<String, String>> messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': prompt},
      <String, String>{'role': 'user', 'content': userText},
    ];

    final String body = jsonEncode(<String, dynamic>{
      'model': modelId,
      'messages': messages,
    });
    AppLogger.instance.info('[DeepSeek] POST $baseUrl, body: ${body.length} 字节');
    final http.Client client = _createClient();
    final Stopwatch sw = Stopwatch()..start();
    final http.Response response = await client.post(
      Uri.parse(baseUrl),
      headers: headers,
      body: body,
    ).catchError((Object e, StackTrace st) {
      sw.stop();
      AppLogger.instance.error('[DeepSeek] 网络异常 (${sw.elapsedMilliseconds}ms): ${e.runtimeType} - $e');
      throw e;
    }).timeout(const Duration(seconds: 120), onTimeout: () {
      sw.stop();
      final String msg = 'DeepSeek API 请求超时（120秒），已等待 ${sw.elapsedMilliseconds}ms';
      AppLogger.instance.error('[DeepSeek] $msg');
      throw Exception(msg);
    }).whenComplete(() => client.close());
    sw.stop();
    AppLogger.instance.info('[DeepSeek] 响应状态: ${response.statusCode}，耗时 ${sw.elapsedMilliseconds}ms');

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
      AppLogger.instance.info('[DeepSeek] 响应预览(前500字): ${parsed.substring(0, 500)}...');
    }

    if (parsed.isEmpty) {
      AppLogger.instance.warn('[DeepSeek] 返回空内容！原始响应: ${utf8.decode(response.bodyBytes)}');
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
