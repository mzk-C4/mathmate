import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/vivo_chat_service.dart';

class StreamChunk {
  final String? content;
  final String? reasoning;
  final bool isDone;
  final String? error;

  StreamChunk({this.content, this.reasoning, this.isDone = false, this.error});
}

class ChatStreamService {
  static const String _apiKeyEnv = 'VIVO_API_KEY';
  static const String _modelEnv = 'VIVO_MODEL_ID';
  static const String _baseUrlEnv = 'VIVO_BASE_URL';
  static const String _defaultModel = 'qwen-plus';
  static const String _defaultBaseUrl =
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';

  static bool _dotenvLoaded = false;
  http.Client? _client;
  bool _cancelled = false;

  Future<void> _ensureEnvLoaded() async {
    if (_dotenvLoaded) return;
    await dotenv.load(fileName: '.env');
    _dotenvLoaded = true;
  }

  Stream<StreamChunk> sendMessageStream({
    required List<VivoChatMessage> messages,
    String? modelId,
  }) async* {
    await _ensureEnvLoaded();
    _cancelled = false;

    final String apiKey = (dotenv.env[_apiKeyEnv] ?? '').trim();
    final String model = (modelId ?? dotenv.env[_modelEnv] ?? _defaultModel).trim();
    final String baseUrl =
        (dotenv.env[_baseUrlEnv] ?? _defaultBaseUrl).trim();

    if (apiKey.isEmpty) {
      yield StreamChunk(error: 'Missing env config: VIVO_API_KEY');
      return;
    }

    final List<Map<String, String>> formattedMessages =
        messages.map((VivoChatMessage m) => m.toMap()).toList();

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

      final Stream<String> lines =
          response.stream.transform(utf8.decoder).transform(const LineSplitter());

      await for (final String line in lines) {
        if (_cancelled) break;
        if (line.isEmpty || !line.startsWith('data:')) continue;

        final String data = line.substring(5).trim();
        if (data == '[DONE]') {
          yield StreamChunk(isDone: true);
          break;
        }

        try {
          final Map<String, dynamic> json = jsonDecode(data);
          final dynamic delta = json['choices']?[0]?['delta'];
          if (delta == null) continue;

          final String? content = (delta['content'] as String?);
          final String? reasoning = (delta['reasoning_content'] as String?);

          if (content != null || reasoning != null) {
            yield StreamChunk(content: content, reasoning: reasoning);
          }
        } catch (e) {
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
