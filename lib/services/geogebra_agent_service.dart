import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/provider_config_service.dart';

import 'prompts/geogebra_agent_prompt.dart';

/// Agent 流式响应块
class AgentStreamChunk {
  final String? textDelta;       // 文本增量
  final String? toolCallName;    // 工具调用名称（开始时）
  final String? toolCallArgs;    // 工具调用参数（完整 JSON）
  final String? toolResult;      // 工具执行结果描述
  final bool isDone;
  final String? error;

  AgentStreamChunk({
    this.textDelta,
    this.toolCallName,
    this.toolCallArgs,
    this.toolResult,
    this.isDone = false,
    this.error,
  });
}

/// 工具定义（发给 LLM）
class AgentTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema

  const AgentTool({required this.name, required this.description, required this.parameters});

  Map<String, dynamic> toOpenAITool() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// GeoGebra 7 个 MCP 工具定义
const List<AgentTool> geogebraTools = [
  AgentTool(
    name: 'getCanvasContext',
    description: '获取当前 GeoGebra 画布的完整状态，包括所有对象和表达式',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  ),
  AgentTool(
    name: 'executeGeoGebraCommand',
    description: '在 GeoGebra 画布中执行一条命令，返回执行结果',
    parameters: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string', 'description': '要执行的 GeoGebra 命令'},
      },
      'required': ['command'],
    },
  ),
  AgentTool(
    name: 'deleteGeoGebraObject',
    description: '从 GeoGebra 画布中删除指定标签的对象',
    parameters: {
      'type': 'object',
      'properties': {
        'label': {'type': 'string', 'description': '要删除的对象标签'},
      },
      'required': ['label'],
    },
  ),
  AgentTool(
    name: 'setUndoPoint',
    description: '在 GeoGebra 画布中设置一个撤销点',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  ),
  AgentTool(
    name: 'undo',
    description: '在 GeoGebra 画布中执行撤销操作',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  ),
  AgentTool(
    name: 'setPerspective',
    description: "切换 GeoGebra 视图模式：'G'=2D图形, 'T'=3D图形",
    parameters: {
      'type': 'object',
      'properties': {
        'mode': {'type': 'string', 'description': "视图模式：'G' 或 'T'"},
      },
      'required': ['mode'],
    },
  ),
  AgentTool(
    name: 'getSelectedObjects',
    description: '获取用户当前在 GeoGebra 画布中选中的对象标签列表',
    parameters: {
      'type': 'object',
      'properties': {},
    },
  ),
];

/// GeoGebra Agent 服务。
///
/// 使用 DeepSeek API 的 function calling 能力，让 LLM 通过工具调用
/// 操控 GeoGebra 画布。对外提供流式响应。
class GeogebraAgentService {
  /// 工具执行回调 —— 由外部注入，桥接 JS Bridge。
  Future<String> Function(String toolName, Map<String, dynamic> args)? onToolCall;

  GeogebraAgentService();

  http.Client? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _closeClient();
  }

  void _closeClient() {
    try { _client?.close(); } catch (_) {}
    _client = null;
  }

  /// 流式对话入口。
  /// [messages] 为历史对话，不含 system prompt（会自动添加）。
  /// 最多 [maxSteps] 轮工具调用。
  Stream<AgentStreamChunk> chat({
    required List<Map<String, String>> messages,
    int maxSteps = 10,
  }) async* {
    _cancelled = false;

    final pc = ProviderConfigService.instance;
    final apiKey = pc.reasoningApiKey;
    final model = pc.reasoningModelId;
    final baseUrl = pc.reasoningBaseUrl;

    if (apiKey.isEmpty) {
      yield AgentStreamChunk(error: '缺少 API Key: DEEPSEEK_API_KEY');
      return;
    }

    // 构建完整消息列表（含 system prompt）
    final fullMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': geogebraAgentSystemPrompt},
      ...messages.map((m) => {'role': m['role'], 'content': m['content']}),
    ];

    int stepCount = 0;
    while (stepCount < maxSteps && !_cancelled) {
      stepCount++;

      final response = await _sendRequest(
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
        messages: fullMessages,
      );

      if (response == null) {
        yield AgentStreamChunk(error: 'API 请求失败');
        return;
      }

      final choice = response['choices']?[0] as Map<String, dynamic>?;
      if (choice == null) {
        yield AgentStreamChunk(error: 'API 响应格式异常');
        return;
      }

      final message = choice['message'] as Map<String, dynamic>?;
      if (message == null) {
        yield AgentStreamChunk(error: '消息为空');
        return;
      }

      // 文本响应
      final content = (message['content'] as String?)?.trim() ?? '';
      if (content.isNotEmpty) {
        yield AgentStreamChunk(textDelta: content);
      }

      // 工具调用
      final toolCalls = message['tool_calls'] as List<dynamic>?;
      if (toolCalls == null || toolCalls.isEmpty) {
        // 无工具调用，对话结束
        fullMessages.add(message);
        yield AgentStreamChunk(isDone: true);
        return;
      }

      // 处理工具调用
      fullMessages.add(message); // 添加 assistant 消息（含 tool_calls）

      for (final tc in toolCalls) {
        if (_cancelled) break;
        final toolCall = tc as Map<String, dynamic>;
        final fn = toolCall['function'] as Map<String, dynamic>?;
        if (fn == null) continue;

        final toolName = (fn['name'] as String?) ?? '';
        final toolArgsStr = (fn['arguments'] as String?) ?? '{}';

        yield AgentStreamChunk(toolCallName: toolName, toolCallArgs: toolArgsStr);

        // 解析参数
        Map<String, dynamic> args;
        try {
          args = jsonDecode(toolArgsStr) as Map<String, dynamic>;
        } catch (_) {
          args = <String, dynamic>{};
        }

        // 执行工具
        String toolResult;
        if (onToolCall != null) {
          try {
            toolResult = await onToolCall!(toolName, args);
          } catch (e) {
            toolResult = 'Error: $e';
          }
        } else {
          toolResult = '工具未配置执行回调';
        }

        yield AgentStreamChunk(toolResult: toolResult);

        // 添加 tool 响应消息
        fullMessages.add({
          'role': 'tool',
          'tool_call_id': toolCall['id'] ?? '',
          'content': toolResult,
        });
      }
    }

    if (stepCount >= maxSteps) {
      yield AgentStreamChunk(textDelta: '\n\n已达到最大推理步数限制。');
    }
    yield AgentStreamChunk(isDone: true);
  }

  /// 发送一次请求（非流式，等完整响应后再处理，简化 tool calling 逻辑）。
  Future<Map<String, dynamic>?> _sendRequest({
    required String apiKey,
    required String model,
    required String baseUrl,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      final body = jsonEncode({
        'model': model,
        'messages': messages,
        'tools': geogebraTools.map((t) => t.toOpenAITool()).toList(),
        'tool_choice': 'auto',
        'temperature': 0.6,
      });

      _client = http.Client();
      final request = http.Request('POST', Uri.parse(baseUrl))
        ..headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $apiKey',
        })
        ..body = body;

      final streamedResponse = await _client!.send(request).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception('请求超时'),
      );

      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        debugPrint('[GeoAgent] API error: $responseBody');
        return null;
      }

      return jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[GeoAgent] Request error: $e');
      return null;
    } finally {
      _closeClient();
    }
  }
}
