import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:mathmate/geogebra/geometry_engine.dart';

/// GeoGebra 移动端 JS Bridge —— 通过 WebViewController 的 JavaScript channel
/// 与 GeoGebra applet 通信。替代 Web 端的 dart:html postMessage 方案。
class GeogebraMobileBridge implements GeometryEngine {
  final WebViewController _controller;
  int _msgId = 0;
  final Map<String, Completer<dynamic>> _pending = {};
  bool _ready = false;

  GeogebraMobileBridge(this._controller);

  bool get isReady => _ready;

  void markReady() => _ready = true;

  /// 处理来自 GeoGebra JS 的消息
  void handleMessage(String raw) {
    // 消息格式：type|id|jsonPayload
    final parts = raw.split('|');
    if (parts.length < 2) return;
    final type = parts[0];
    final msgId = parts[1];
    final payload = parts.length > 2 ? parts.sublist(2).join('|') : '{}';

    final completer = _pending.remove(msgId);
    if (completer == null) return;

    if (type == 'error') {
      completer.completeError(payload);
    } else {
      // JS 端使用 JSON.stringify 序列化，直接 jsonDecode 解析
      try {
        completer.complete(jsonDecode(payload));
      } catch (_) {
        completer.complete(payload);
      }
    }
  }

  Future<dynamic> _send(String type, [String? payload]) async {
    if (!_ready) throw Exception('GeoGebra 尚未就绪');
    final id = 'm${++_msgId}';
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final msg = '$type|$id|${payload ?? '{}'}';
    await _controller.runJavaScript(
      'window._ggbBridgeCallback(${jsonEncode(msg)});',
    );

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('GeoGebra bridge timeout: $type');
      },
    );
  }

  /// 执行一条 GeoGebra 命令，返回 {success, label, error}。
  Future<Map<String, dynamic>> evalCommand(String command) async {
    final result = await _send('evalCommand', command);
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'success': false, 'label': null, 'error': '解析失败'};
  }

  @override
  Future<GeometryEngineCommandResult> executeCommand(String command) async {
    final Map<String, dynamic> result = await evalCommand(command);
    return GeometryEngineCommandResult(
      success: result['success'] == true,
      label: result['label'] as String?,
      error: result['error'] as String?,
    );
  }

  /// 获取 GeoGebra XML 状态。
  @override
  Future<String> getXML() async {
    final result = await _send('getXML');
    return result is String ? result : '';
  }

  /// Replaces the current construction with a previously saved XML snapshot.
  @override
  Future<bool> setXML(String xml) async {
    final r = await _send('setXML', xml);
    return r == true || r == 'true';
  }

  /// 删除指定标签的对象。
  Future<bool> deleteObject(String label) async {
    final r = await _send('deleteObject', label);
    return r == true || r == 'true';
  }

  /// 设置撤销点。
  @override
  Future<bool> setUndoPoint() async {
    final r = await _send('setUndoPoint');
    return r == true || r == 'true';
  }

  /// 撤销。
  Future<bool> undo() async {
    final r = await _send('undo');
    return r == true || r == 'true';
  }

  /// 切换视图模式。
  Future<bool> setPerspective(String mode) async {
    final r = await _send('setPerspective', mode);
    return r == true || r == 'true';
  }

  /// 重置画布。
  Future<bool> reset() async {
    final r = await _send('reset');
    return r == true || r == 'true';
  }

  /// 获取选中的对象标签列表。
  Future<List<String>> getSelectedObjects() async {
    final r = await _send('getSelectedObjects');
    if (r == null) return [];
    if (r is List) return r.cast<String>();
    if (r is String) return r.split(',').where((s) => s.isNotEmpty).toList();
    return [];
  }

  /// 清理所有挂起的请求（页面销毁时调用）。
  void dispose() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError('Bridge disposed');
    }
    _pending.clear();
  }
}
