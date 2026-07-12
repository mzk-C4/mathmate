import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/api_config_service.dart';
import 'package:mathmate/services/auth_service.dart';

class VolcAiClientService {
  static const String _apiKeyEnv = 'VOLC_API_KEY';
  static const String _baseUrlEnv = 'VOLC_BASE_URL';
  static const String _defaultModelEnv = 'VOLC_MODEL_ID';
  static const String _requestFormatEnv = 'VOLC_REQUEST_FORMAT';
  static const String _defaultBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions';

  static bool _dotenvLoaded = false;

  Future<void> _ensureEnvLoaded() async {
    if (_dotenvLoaded) {
      return;
    }
    await dotenv.load(fileName: '.env');
    _dotenvLoaded = true;
  }

  Future<String> callVisionPrompt({
    required XFile imageFile,
    required String prompt,
    required String modelEnv,
  }) async {
    final List<int> bytes = await imageFile.readAsBytes();
    final String base64Image = base64Encode(bytes);
    AppLogger.instance.info(
      '[VolcVision] 图片大小: ${bytes.length} 字节 (${(bytes.length / 1024).toStringAsFixed(1)} KB)',
    );
    AppLogger.instance.info('[VolcVision] base64 长度: ${base64Image.length} 字符');
    AppLogger.instance.info(
      '[VolcVision] system prompt 长度: ${prompt.length} 字符',
    );

    return _request(
      modelEnv: modelEnv,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': prompt},
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, String>{
                'url': 'data:image/jpeg;base64,$base64Image',
              },
            },
          ],
        },
      ],
    );
  }

  Future<String> callTextPrompt({
    required String prompt,
    required String userText,
    required String modelEnv,
  }) async {
    return _request(
      modelEnv: modelEnv,
      messages: <Map<String, String>>[
        <String, String>{'role': 'system', 'content': prompt},
        <String, String>{'role': 'user', 'content': userText},
      ],
    );
  }

  Future<String> _request({
    required String modelEnv,
    required List<Map<String, dynamic>> messages,
  }) async {
    await _ensureEnvLoaded();

    final ResolvedApiConfig config = await ApiConfigService.instance.resolve(
      provider: ApiProvider.volc,
      fallbackApiKey: dotenv.env[_apiKeyEnv] ?? '',
      fallbackModelId:
          dotenv.env[modelEnv] ?? dotenv.env[_defaultModelEnv] ?? '',
      fallbackBaseUrl: dotenv.env[_baseUrlEnv] ?? _defaultBaseUrl,
      fallbackRequestFormat: dotenv.env[_requestFormatEnv] ?? 'auto',
      useVisionModel: modelEnv != _defaultModelEnv,
    );
    final String apiKey = config.apiKey;
    final String modelId = config.modelId;
    final String baseUrl = config.baseUrl;
    final String requestFormat = config.requestFormat;

    AppLogger.instance.info('[Volc] 模型 env: $modelEnv，实际 modelId: $modelId');
    AppLogger.instance.info('[Volc] 端点: $baseUrl');
    AppLogger.instance.info('[Volc] 请求格式: $requestFormat');

    if (apiKey.isEmpty) {
      throw Exception('Missing env config: VOLC_API_KEY');
    }
    if (modelId.isEmpty) {
      throw Exception('Missing env config: $modelEnv or $_defaultModelEnv');
    }

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
      ...AuthService().proxyAuthHeaders,
    };

    final Stopwatch sw = Stopwatch()..start();
    late http.Response response;
    if (requestFormat == 'messages') {
      response = await _postMessages(baseUrl, headers, modelId, messages);
      AppLogger.instance.info('[Volc] messages 格式响应状态: ${response.statusCode}');
    } else if (requestFormat == 'input') {
      response = await _postInput(baseUrl, headers, modelId, messages);
      AppLogger.instance.info('[Volc] input 格式响应状态: ${response.statusCode}');
    } else {
      response = await _postMessages(baseUrl, headers, modelId, messages);
      AppLogger.instance.info(
        '[Volc] auto: 先尝试 messages 格式，状态=${response.statusCode}',
      );
      final String detail = utf8.decode(response.bodyBytes);
      final String normalizedDetail = detail.toLowerCase();
      final bool unknownMessagesField =
          normalizedDetail.contains('messages') &&
          (normalizedDetail.contains('unknown field') ||
              normalizedDetail.contains('unknownfield'));
      if (response.statusCode != 200 && unknownMessagesField) {
        AppLogger.instance.warn('[Volc] auto: messages 格式被拒，切换到 input 格式重试');
        response = await _postInput(baseUrl, headers, modelId, messages);
        AppLogger.instance.info(
          '[Volc] auto: input 格式响应状态=${response.statusCode}',
        );
      }
    }
    sw.stop();
    AppLogger.instance.info('[Volc] 请求耗时: ${sw.elapsedMilliseconds}ms');

    if (response.statusCode != 200) {
      final String detail = utf8.decode(response.bodyBytes);
      AppLogger.instance.error('[Volc] 错误响应体($modelEnv): $detail');
      throw Exception('Volc API error($modelEnv): $detail');
    }

    final String rawBody = utf8.decode(response.bodyBytes);
    AppLogger.instance.info('[Volc] 响应体长度: ${rawBody.length} 字符');
    final dynamic data = jsonDecode(rawBody);
    final String parsed = _extractContentFromResponse(data).trim();

    AppLogger.instance.info('[Volc] 提取内容长度: ${parsed.length} 字符');
    if (parsed.length <= 500) {
      AppLogger.instance.info('[Volc] 响应内容: $parsed');
    } else {
      AppLogger.instance.info(
        '[Volc] 响应预览(前500字): ${parsed.substring(0, 500)}...',
      );
    }

    if (parsed.isEmpty) {
      AppLogger.instance.warn('[Volc] 提取内容为空！原始响应: $rawBody');
      throw Exception('Volc API returned empty content ($modelEnv).');
    }
    return parsed;
  }

  Future<http.Response> _postMessages(
    String baseUrl,
    Map<String, String> headers,
    String modelId,
    List<Map<String, dynamic>> messages,
  ) {
    return http
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
            throw Exception('Volc API 请求超时（60秒）');
          },
        );
  }

  Future<http.Response> _postInput(
    String baseUrl,
    Map<String, String> headers,
    String modelId,
    List<Map<String, dynamic>> messages,
  ) {
    return http
        .post(
          Uri.parse(baseUrl),
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'model': modelId,
            'input': _toInputFormat(messages),
          }),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw Exception('Volc API 请求超时（60秒）');
          },
        );
  }

  List<Map<String, dynamic>> _toInputFormat(
    List<Map<String, dynamic>> messages,
  ) {
    return messages.map((Map<String, dynamic> message) {
      final String role = (message['role'] ?? 'user').toString();
      final dynamic content = message['content'];

      if (content is String) {
        return <String, dynamic>{
          'role': role,
          'content': <Map<String, String>>[
            <String, String>{'type': 'input_text', 'text': content},
          ],
        };
      }

      if (content is List) {
        final List<Map<String, dynamic>> mappedContent =
            <Map<String, dynamic>>[];
        for (final dynamic item in content) {
          if (item is! Map) {
            continue;
          }
          final dynamic type = item['type'];
          if (type == 'text') {
            mappedContent.add(<String, dynamic>{
              'type': 'input_text',
              'text': (item['text'] ?? '').toString(),
            });
          } else if (type == 'image_url') {
            final dynamic rawImageUrl = item['image_url'];
            String imageUrl = '';
            if (rawImageUrl is Map) {
              imageUrl = (rawImageUrl['url'] ?? '').toString();
            } else {
              imageUrl = (rawImageUrl ?? '').toString();
            }
            mappedContent.add(<String, dynamic>{
              'type': 'input_image',
              'image_url': imageUrl,
            });
          }
        }
        return <String, dynamic>{'role': role, 'content': mappedContent};
      }

      return <String, dynamic>{
        'role': role,
        'content': <Map<String, String>>[
          <String, String>{'type': 'input_text', 'text': content.toString()},
        ],
      };
    }).toList();
  }

  String _extractContentFromResponse(dynamic data) {
    final dynamic chatContent = data['choices']?[0]?['message']?['content'];
    final String fromChat = _extractContentAsText(chatContent).trim();
    if (fromChat.isNotEmpty) {
      return fromChat;
    }

    final dynamic outputText = data['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText;
    }

    final dynamic output = data['output'];
    if (output is List) {
      final StringBuffer buffer = StringBuffer();
      for (final dynamic item in output) {
        if (item is! Map) {
          continue;
        }
        final dynamic content = item['content'];
        if (content is List) {
          for (final dynamic c in content) {
            if (c is! Map) {
              continue;
            }
            final dynamic text = c['text'];
            if (text is String && text.trim().isNotEmpty) {
              buffer.writeln(text);
            }
          }
        }
      }
      final String parsed = buffer.toString().trim();
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    return '';
  }

  String _extractContentAsText(dynamic content) {
    if (content is String) {
      return content;
    }
    if (content is List) {
      final StringBuffer buffer = StringBuffer();
      for (final dynamic item in content) {
        if (item is Map && item['text'] is String) {
          buffer.writeln(item['text'] as String);
        }
      }
      return buffer.toString();
    }
    return '';
  }
}
