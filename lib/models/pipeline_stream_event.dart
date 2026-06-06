/// 流式 Pipeline 输出内容分类。
enum StreamContentType {
  ocrText,
  solutionText,
  geometryJson,
  status,
  error,
}

/// 流式 Pipeline 的单个事件。
class PipelineStreamEvent {
  final String? content;
  final StreamContentType? type;
  final String? statusMessage;
  final String? error;
  final bool isDone;
  final bool isCancelled;

  const PipelineStreamEvent({
    this.content,
    this.type,
    this.statusMessage,
    this.error,
    this.isDone = false,
    this.isCancelled = false,
  });

  factory PipelineStreamEvent.status(String message) => PipelineStreamEvent(
        type: StreamContentType.status,
        statusMessage: message,
      );

  factory PipelineStreamEvent.text(String text, StreamContentType type) =>
      PipelineStreamEvent(content: text, type: type);

  factory PipelineStreamEvent.errorEvent(String message, {bool fatal = true}) =>
      PipelineStreamEvent(
        type: StreamContentType.error,
        error: message,
        isDone: fatal,
      );

  factory PipelineStreamEvent.done() => const PipelineStreamEvent(isDone: true);
  factory PipelineStreamEvent.cancelled() =>
      const PipelineStreamEvent(isCancelled: true, isDone: true);
}
