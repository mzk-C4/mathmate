import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/provider_config_service.dart';
import 'package:mathmate/services/vivo_chat_service.dart';

class StreamChunk {
  final String? content;
  final String? reasoning;
  final bool isDone;
  final String? error;

  StreamChunk({this.content, this.reasoning, this.isDone = false, this.error});
}

/// 通用 SSE 流式请求。
/// [chunkTimeout] 无新 chunk 超时，默认 30s（vision 建议 120s）。
/// [extraBody] 合并进请求体的额外字段（如 Kimi 的 `thinking: {type: "disabled"}`）。
Stream<StreamChunk> streamFromRequest({
  required String baseUrl,
  required String apiKey,
  required String modelId,
  required List<Map<String, dynamic>> messages,
  double temperature = 0.7,
  int maxTokens = 4096,
  Duration chunkTimeout = const Duration(seconds: 30),
  Map<String, dynamic>? extraBody,
  bool Function()? cancelled,
}) async* {
  final http.Client client = http.Client();
  try {
    final Map<String, dynamic> body = <String, dynamic>{
      'model': modelId,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    };
    if (extraBody != null) { body.addAll(extraBody); }

    final http.Request request = http.Request('POST', Uri.parse(baseUrl))
      ..headers.addAll(<String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode(body);

    final http.StreamedResponse response = await client.send(request).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw http.ClientException(
        '连接超时（15s），请检查网络或 API 地址',
      ),
    );

    if (response.statusCode != 200) {
      final String body = await response.stream.bytesToString();
      debugPrint('streamFromRequest error: $body');
      yield StreamChunk(error: 'API error: ${response.statusCode}');
      return;
    }

    final Stream<String> lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    // 过滤 SSE 注释行（keep-alive: `: heartbeat`）和空行，避免 reset chunk timeout
    final Stream<String> contentLines = lines.where(
      (String line) => line.isNotEmpty && !line.startsWith(':'),
    );

    await for (final String line in contentLines.timeout(
      chunkTimeout,
      onTimeout: (EventSink<String> sink) {
        sink.add('data:TIMEOUT');
        sink.close();
      },
    )) {
      if (cancelled != null && cancelled()) break;
      if (line == 'data:TIMEOUT') {
        yield StreamChunk(error: '请求超时：${chunkTimeout.inSeconds}秒未收到新数据');
        return;
      }
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
      } catch (_) {}
    }
  } on http.ClientException catch (e) {
    if (cancelled == null || !cancelled()) {
      yield StreamChunk(error: '网络连接失败: $e');
    }
  } catch (e) {
    if (cancelled == null || !cancelled()) {
      yield StreamChunk(error: '请求失败: $e');
    }
  } finally {
    try { client.close(); } catch (_) {}
  }
}

class ChatStreamService {
  http.Client? _client;
  bool _cancelled = false;

  Stream<StreamChunk> sendMessageStream({
    required List<VivoChatMessage> messages,
    String? modelId,
  }) async* {
    _cancelled = false;

    final pc = ProviderConfigService.instance;
    final String apiKey = pc.chatApiKey;
    final String model = modelId ?? pc.chatModelId;
    final String baseUrl = pc.chatBaseUrl;

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

      // 过滤 SSE 注释行（keep-alive），但不加超时——聊天场景下用户可能思考很久
      final Stream<String> contentLines = lines.where(
        (String line) => line.isNotEmpty && !line.startsWith(':'),
      );

      await for (final String line in contentLines) {
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
