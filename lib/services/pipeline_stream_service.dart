import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mathmate/models/pipeline_stream_event.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/chat_stream_service.dart';
import 'package:mathmate/services/prompts/ocr_prompt.dart';
import 'package:mathmate/services/prompts/solve_prompt.dart';
import 'package:mathmate/services/provider_config_service.dart';
import 'package:mathmate/visualization/response_extractor.dart';

/// 两模型流式 Pipeline：
/// - [recognizeStream]: vision 模型看图 → 题目文字 + 几何 JSON
/// - [solveStream]: reasoning 模型读题 → 解答步骤
class PipelineStreamService {
  bool _cancelled = false;

  /// 阶段 1: vision 模型看图，流式输出题目文字 + 几何 JSON。
  ///
  /// 返回的 Stream 中：ocrText 事件逐 token 出现，geometryJson 在流结束后一次性输出。
  Stream<PipelineStreamEvent> recognizeStream(Uint8List imageBytes) async* {
    _cancelled = false;
    final pc = ProviderConfigService.instance;

    // ---- pre-flight 校验 ----
    if (pc.visionApiKey.isEmpty) {
      yield PipelineStreamEvent.errorEvent('请先配置多模态识别的 API Key');
      return;
    }
    if (pc.visionBaseUrl.isEmpty) {
      yield PipelineStreamEvent.errorEvent('请先配置多模态识别的接口地址');
      return;
    }
    if (pc.visionModelId.isEmpty) {
      yield PipelineStreamEvent.errorEvent('请先配置多模态识别的模型 ID');
      return;
    }

    // ---- 图片压缩 ----
    final img.Image? decoded = img.decodeImage(imageBytes);
    List<int> bytes = imageBytes;
    if (decoded != null && (decoded.width > 1024 || decoded.height > 1024)) {
      final img.Image resized = img.copyResize(decoded, width: 1024, height: 1024);
      bytes = img.encodeJpg(resized, quality: 75);
      AppLogger.instance.info('[StreamPipeline] 压缩: ${imageBytes.length} → ${bytes.length} 字节');
    }
    final String base64Image = base64Encode(bytes);

    final bool isKimiVision = pc.visionBaseUrl.contains('moonshot');
    final List<Map<String, dynamic>> messages;
    if (isKimiVision) {
      // Kimi vision API 拒绝 system role，合并到 user text
      final String userPrompt = '$ocrPrompt\n\n请识别图片中的数学题。';
      messages = <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, String>{'type': 'text', 'text': userPrompt},
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, String>{'url': 'data:image/jpeg;base64,$base64Image'},
            },
          ],
        },
      ];
    } else {
      // OpenAI/Qwen 等：标准 system + user 格式
      messages = <Map<String, dynamic>>[
        <String, String>{'role': 'system', 'content': ocrPrompt},
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, String>{'type': 'text', 'text': '请识别图片中的数学题。'},
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, String>{'url': 'data:image/jpeg;base64,$base64Image'},
            },
          ],
        },
      ];
    }

    yield PipelineStreamEvent.status('AI 正在识别题目...');

    // Kimi 特有参数：禁用思考模式；其他 provider 不传避免兼容性问题
    final bool isKimi = pc.visionBaseUrl.contains('moonshot');
    final Map<String, dynamic>? extraBody = isKimi
        ? const <String, dynamic>{'thinking': <String, dynamic>{'type': 'disabled'}}
        : null;

    AppLogger.instance.info('[StreamPipeline] 阶段1 model=${pc.visionModelId}, temp=${pc.visionTemperature}, isKimi=$isKimi');

    final StringBuffer buffer = StringBuffer();
    int chunkCount = 0;
    final DateTime t0 = DateTime.now();

    await for (final StreamChunk chunk in streamFromRequest(
      baseUrl: pc.visionBaseUrl,
      apiKey: pc.visionApiKey,
      modelId: pc.visionModelId,
      messages: messages,
      temperature: pc.visionTemperature,
      maxTokens: 16384,
      chunkTimeout: const Duration(seconds: 120),
      extraBody: extraBody,
      cancelled: () => _cancelled,
    )) {
      if (_cancelled) { yield PipelineStreamEvent.cancelled(); return; }
      if (chunk.error != null) { yield PipelineStreamEvent.errorEvent(chunk.error!); return; }
      if (chunk.isDone) break;

      // 只用 content，忽略 reasoning_content（思考内容不作为题目文本）
      final String text = chunk.content ?? '';
      if (text.isEmpty) continue;

      chunkCount++;
      buffer.write(text);
      yield PipelineStreamEvent.text(text, StreamContentType.ocrText);
    }

    if (_cancelled) { yield PipelineStreamEvent.cancelled(); return; }

    final int elapsedMs = DateTime.now().difference(t0).inMilliseconds;
    AppLogger.instance.info('[StreamPipeline] OCR 完成: ${buffer.length} 字符, $chunkCount chunks, ${elapsedMs}ms, 平均 ${elapsedMs > 0 && chunkCount > 0 ? (elapsedMs ~/ chunkCount) : 0}ms/chunk');

    // 尝试提取 geometryjson
    final String fullText = buffer.toString();
    final String? geometryJsonStr = ResponseExtractor.extractGeometryJsonText(fullText);
    if (geometryJsonStr != null) {
      AppLogger.instance.info('[StreamPipeline] 提取到 geometryjson: ${geometryJsonStr.length} 字符');
      AppLogger.instance.info('[StreamPipeline] geometryjson 内容: $geometryJsonStr');
      yield PipelineStreamEvent.text(geometryJsonStr, StreamContentType.geometryJson);
    } else {
      AppLogger.instance.info('[StreamPipeline] 未提取到 geometryjson');
    }

    yield PipelineStreamEvent.done();
  }

  /// 阶段 2: reasoning 模型读题，流式输出解答步骤。
  Stream<PipelineStreamEvent> solveStream(String ocrText) async* {
    _cancelled = false;
    final pc = ProviderConfigService.instance;

    // ---- pre-flight 校验 ----
    if (ocrText.trim().isEmpty) {
      yield PipelineStreamEvent.errorEvent('题目内容为空，无法解答');
      return;
    }
    if (pc.reasoningApiKey.isEmpty) {
      yield PipelineStreamEvent.errorEvent('请先配置解题推理的 API Key');
      return;
    }
    if (pc.reasoningBaseUrl.isEmpty) {
      yield PipelineStreamEvent.errorEvent('请先配置解题推理的接口地址');
      return;
    }
    if (pc.reasoningModelId.isEmpty) {
      yield PipelineStreamEvent.errorEvent('请先配置解题推理的模型 ID');
      return;
    }

    AppLogger.instance.info('[StreamPipeline] 阶段2 开始，题目长度: ${ocrText.length} 字符');
    AppLogger.instance.info('[StreamPipeline] 阶段2 model=${pc.reasoningModelId}, temp=${pc.reasoningTemperature}');

    final List<Map<String, String>> messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': solvePrompt},
      <String, String>{'role': 'user', 'content': ocrText},
    ];

    yield PipelineStreamEvent.status('AI 正在生成解答...');

    final List<Map<String, dynamic>> apiMessages = messages
        .map((m) => <String, dynamic>{'role': m['role'], 'content': m['content']})
        .toList();

    // Kimi 特有参数：禁用思考模式
    final bool isKimi = pc.reasoningBaseUrl.contains('moonshot');
    final Map<String, dynamic>? extraBody = isKimi
        ? const <String, dynamic>{'thinking': <String, dynamic>{'type': 'disabled'}}
        : null;

    int chunkCount2 = 0;
    int totalLen2 = 0;
    final DateTime t2 = DateTime.now();

    await for (final StreamChunk chunk in streamFromRequest(
      baseUrl: pc.reasoningBaseUrl,
      apiKey: pc.reasoningApiKey,
      modelId: pc.reasoningModelId,
      messages: apiMessages,
      temperature: pc.reasoningTemperature,
      maxTokens: 16384,
      chunkTimeout: const Duration(seconds: 60),
      extraBody: extraBody,
      cancelled: () => _cancelled,
    )) {
      if (_cancelled) { yield PipelineStreamEvent.cancelled(); return; }
      if (chunk.error != null) { yield PipelineStreamEvent.errorEvent(chunk.error!); return; }
      if (chunk.isDone) break;

      final String text = chunk.content ?? '';
      if (text.isEmpty) continue;

      chunkCount2++;
      totalLen2 += text.length;
      yield PipelineStreamEvent.text(text, StreamContentType.solutionText);
    }

    if (_cancelled) { yield PipelineStreamEvent.cancelled(); return; }

    final int e2 = DateTime.now().difference(t2).inMilliseconds;
    AppLogger.instance.info('[StreamPipeline] 阶段2 完成: $totalLen2 字符, $chunkCount2 chunks, ${e2}ms, 平均 ${e2 > 0 && chunkCount2 > 0 ? (e2 ~/ chunkCount2) : 0}ms/chunk');

    yield PipelineStreamEvent.done();
  }

  void cancel() { _cancelled = true; }
}
