import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/provider_config_service.dart';

class VivoChatMessage {
  final String role;
  final String content;

  VivoChatMessage({required this.role, required this.content});

  Map<String, String> toMap() => <String, String>{
    'role': role,
    'content': content,
  };
}

class VivoChatResponse {
  final String content;
  final String? reasoning;

  VivoChatResponse({required this.content, this.reasoning});
}

class VivoAiChatService {
  Future<VivoChatResponse> sendMessage(List<VivoChatMessage> messages, {String? modelId}) async {
    final pc = ProviderConfigService.instance;
    final String apiKey = pc.chatApiKey;
    final String resolvedModel = modelId ?? pc.chatModelId;
    final String baseUrl = pc.chatBaseUrl;

    if (apiKey.isEmpty) {
      throw Exception('Missing env config: VIVO_API_KEY');
    }

    final List<Map<String, String>> formattedMessages = messages
        .map((m) => m.toMap())
        .toList();

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer $apiKey',
    };

    final Map<String, dynamic> body = <String, dynamic>{
      'model': resolvedModel,
      'messages': formattedMessages,
      'temperature': 0.7,
      'max_tokens': 2048,
    };

    final http.Response response = await http
        .post(
          Uri.parse(baseUrl),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('请求超时，请重试'),
        );

    if (response.statusCode != 200) {
      final String detail = utf8.decode(response.bodyBytes);
      debugPrint('Vivo API error: $detail');
      throw Exception('Vivo API error: $detail');
    }

    final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
    return _extractResponse(data);
  }

  VivoChatResponse _extractResponse(dynamic data) {
    final dynamic message = data['choices']?[0]?['message'];
    final String content = (message?['content'] as String?)?.trim() ?? '';
    final String? reasoning =
        (message?['reasoning_content'] as String?)?.trim();

    return VivoChatResponse(content: content, reasoning: reasoning);
  }
}
