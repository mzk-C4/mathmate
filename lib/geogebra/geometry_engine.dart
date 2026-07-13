class GeometryEngineCommandResult {
  const GeometryEngineCommandResult({
    required this.success,
    this.label,
    this.error,
  });

  final bool success;
  final String? label;
  final String? error;
}

/// Minimal engine contract used by the plan executor. Keeping WebView types
/// out of this interface makes the execution and rollback logic unit-testable.
abstract interface class GeometryEngine {
  Future<String> getXML();

  Future<bool> setXML(String xml);

  Future<bool> setUndoPoint();

  Future<GeometryEngineCommandResult> executeCommand(String command);
}
