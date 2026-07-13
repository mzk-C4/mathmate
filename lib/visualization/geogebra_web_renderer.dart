// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

import 'geogebra_command_builder.dart';

/// GeoGebra JS Bridge — 通过 postMessage 与 iframe 内的 GeoGebra API 通信。
///
/// 在 Web 端提供与 GeoChat useGeoGebra hook 等价的 Dart API：
/// evalCommand, getXML, deleteObject, setUndoPoint, undo,
/// setPerspective, reset, getPNGBase64, getSelectedObjects。
class GeogebraJSBridge {
  static final Map<String, Completer<dynamic>> _pending =
      <String, Completer<dynamic>>{};
  static int _msgId = 0;
  static bool _listenerRegistered = false;
  static html.IFrameElement? _iframe;

  static void _ensureListener() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;
    html.window.onMessage.listen((html.MessageEvent event) {
      final data = event.data;
      if (data is Map && data['type'] != null && data['id'] != null) {
        final completer = _pending.remove(data['id'] as String);
        if (completer == null) return;
        final type = data['type'] as String;
        if (type == 'error') {
          completer.completeError(data['message'] ?? 'Unknown error');
        } else {
          completer.complete(data);
        }
      }
    });
  }

  static void bind(html.IFrameElement iframe) {
    _iframe = iframe;
    _ensureListener();
  }

  static Future<dynamic> _send(String type, [Map<String, dynamic>? payload]) {
    final id = 'ggb-${++_msgId}-${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final msg = <String, dynamic>{'id': id, 'type': type};
    if (payload != null) {
      msg.addAll(payload);
    }

    _iframe?.contentWindow?.postMessage(msg, '*');

    // 10 秒超时
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('GeoGebra bridge timeout: $type');
      },
    );
  }

  /// 执行一条 GeoGebra 命令，返回 {success, label, error}。
  static Future<Map<String, dynamic>> evalCommand(String command) async {
    final result = await _send('evalCommand', {'command': command});
    return {
      'success': result['success'] == true,
      'label': result['label'],
      'error': result['error'],
    };
  }

  /// 获取 GeoGebra XML 状态。
  static Future<String> getXML() async {
    final result = await _send('getXML');
    return result['xml'] as String? ?? '';
  }

  /// Replaces the current construction with a saved XML snapshot.
  static Future<bool> setXML(String xml) async {
    final result = await _send('setXML', {'xml': xml});
    return result['success'] == true;
  }

  /// 删除指定标签的对象。
  static Future<bool> deleteObject(String label) async {
    final result = await _send('deleteObject', {'label': label});
    return result['success'] == true;
  }

  /// 设置撤销点。
  static Future<bool> setUndoPoint() async {
    final result = await _send('setUndoPoint');
    return result['success'] == true;
  }

  /// 撤销。
  static Future<bool> undo() async {
    final result = await _send('undo');
    return result['success'] == true;
  }

  /// 切换视图模式。'G'=2D图形, 'T'=3D图形, 'A'=代数。
  static Future<bool> setPerspective(String mode) async {
    final result = await _send('setPerspective', {'mode': mode});
    return result['success'] == true;
  }

  /// 重置画布。
  static Future<bool> reset() async {
    final result = await _send('reset');
    return result['success'] == true;
  }

  /// 获取选中对象列表。
  static Future<List<String>> getSelectedObjects() async {
    final result = await _send('getSelectedObjects');
    final list = result['objects'] as List<dynamic>?;
    return list?.cast<String>() ?? <String>[];
  }

  /// 导出 PNG Base64。
  static Future<String> getPNGBase64({
    double scale = 1.0,
    bool transparent = false,
    int dpi = 96,
  }) async {
    final result = await _send('getPNGBase64', {
      'scale': scale,
      'transparent': transparent,
      'dpi': dpi,
    });
    return result['png'] as String? ?? '';
  }
}

/// Web 端 GeoGebra 可视化渲染组件。
///
/// 替代 [GeometryPainter] + [CustomPaint] 的方案：将 AI 生成的
/// [GeometryScene] JSON 转换为 GeoGebra 命令，通过 iframe 嵌入
/// GeoGebra 在线 API 进行交互式渲染。同时建立 JS Bridge 支持
/// 程序化命令执行。
class GeogebraWebRenderer extends StatefulWidget {
  final Map<String, dynamic>? scene;
  final bool interactive; // 是否启用程序化控制（Agent 模式）

  const GeogebraWebRenderer({super.key, this.scene, this.interactive = false});

  @override
  State<GeogebraWebRenderer> createState() => _GeogebraWebRendererState();
}

class _GeogebraWebRendererState extends State<GeogebraWebRenderer> {
  bool _loading = true;
  bool _hasError = false;
  late String _viewType;
  html.IFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    _viewType = 'ggb-scene-${identityHashCode(this)}';
    _createGeoGebraView();
  }

  void _createGeoGebraView() {
    try {
      // 构建初始命令
      String jsCommands = '';
      if (widget.scene != null) {
        final commands = GeoGebraCommandBuilder.buildFromMap(widget.scene!);
        final allCommands = <String>[
          ...commands.viewport,
          ...commands.constructions,
          ...commands.styles,
        ];
        jsCommands = allCommands
            .map((c) => '      api.evalCommand("${_escapeJs(c)}");')
            .join('\n');
      }

      final htmlContent = _buildHtml(jsCommands);

      // ignore: undefined_prefixed_name
      ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        _iframe = html.IFrameElement()
          ..srcdoc = htmlContent
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = 'none'
          ..style.overflow = 'hidden'
          ..allowFullscreen = true;

        // 绑定 JS Bridge
        if (widget.interactive) {
          GeogebraJSBridge.bind(_iframe!);
        }

        return _iframe!;
      });

      // 超时兜底
      Future<void>.delayed(const Duration(seconds: 12), () {
        if (mounted && _loading) {
          setState(() => _loading = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  /// 构建完整的 GeoGebra HTML 页面，包含 JS Bridge。
  String _buildHtml(String jsCommands) {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; }
  #ggb-element { width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="ggb-element"></div>
<script>
  var ggbLastCommandError = '';
  var selectedObjects = [];

  // === postMessage Bridge ===
  function postReply(id, data) {
    data.id = id;
    window.parent.postMessage(data, '*');
  }

  window.addEventListener('message', function(event) {
    var msg = event.data;
    if (!msg || !msg.type || !msg.id) return;
    var id = msg.id;

    try {
      switch(msg.type) {
        case 'evalCommand':
          var cmd = msg.command;
          ggbLastCommandError = '';
          window.ggbApplet.asyncEvalCommandGetLabels(cmd).then(function(label) {
            postReply(id, { type: 'commandResult', success: ggbLastCommandError === '', label: label || '', error: ggbLastCommandError });
            ggbLastCommandError = '';
          }).catch(function(e) {
            postReply(id, { type: 'commandResult', success: false, label: '', error: e.toString() });
          });
          break;
        case 'getXML':
          postReply(id, { type: 'xmlResult', xml: window.ggbApplet.getXML() || '' });
          break;
        case 'setXML':
          var restored = true;
          try { window.ggbApplet.setXML(msg.xml || ''); } catch(e) { restored = false; }
          postReply(id, { type: 'setXMLResult', success: restored });
          break;
        case 'deleteObject':
          var ok = true;
          try { window.ggbApplet.deleteObject(msg.label); } catch(e) { ok = false; }
          selectedObjects = selectedObjects.filter(function(l) { return l !== msg.label; });
          postReply(id, { type: 'deleteResult', success: ok });
          break;
        case 'setUndoPoint':
          window.ggbApplet.setUndoPoint();
          postReply(id, { type: 'undoPointResult', success: true });
          break;
        case 'undo':
          window.ggbApplet.undo();
          postReply(id, { type: 'undoResult', success: true });
          break;
        case 'setPerspective':
          window.ggbApplet.setPerspective(msg.mode);
          postReply(id, { type: 'perspectiveResult', success: true });
          break;
        case 'reset':
          window.ggbApplet.reset();
          selectedObjects = [];
          ggbLastCommandError = '';
          postReply(id, { type: 'resetResult', success: true });
          break;
        case 'getSelectedObjects':
          postReply(id, { type: 'selectedResult', objects: selectedObjects });
          break;
        case 'getPNGBase64':
          var png = window.ggbApplet.getPNGBase64(msg.scale || 1, msg.transparent || false, msg.dpi || 96);
          postReply(id, { type: 'pngResult', png: png || '' });
          break;
        default:
          postReply(id, { type: 'error', message: 'Unknown command: ' + msg.type });
      }
    } catch(e) {
      postReply(id, { type: 'error', message: e.toString() });
    }
  });

  function notifyReady() {
    window.parent.postMessage({ type: 'ggb-ready' }, '*');
  }

  var params = {
    "appName": "classic",
    "width": "100%",
    "height": "100%",
    "showToolBar": true,
    "showAlgebraInput": false,
    "showMenuBar": true,
    "enableShiftDragZoom": true,
    "enableRightClick": true,
    "showResetIcon": true,
    "enableLabelDrags": false,
    "errorDialogsActive": false,
    "language": "zh",
    "appletOnLoad": function(api) {
      try {
        // 注册选择事件监听
        api.registerClientListener(function(event) {
          if (event.type === 'select') {
            if (selectedObjects.indexOf(event.target) === -1) selectedObjects.push(event.target);
          } else if (event.type === 'deselect') {
            selectedObjects = selectedObjects.filter(function(l) { return l !== event.target; });
          }
        });

        // 执行初始命令
$jsCommands

        notifyReady();
      } catch(e) {
        window.parent.postMessage({ type: 'ggb-error', message: e.toString() }, '*');
      }
    }
  };

  function loadGeoGebra(src, codebase) {
    var script = document.createElement('script');
    script.src = src;
    script.onload = function() {
      try {
        var applet = new GGBApplet(params, true);
        applet.setHTML5Codebase(codebase);
        applet.inject('ggb-element');
      } catch(e) {
        window.parent.postMessage({ type: 'ggb-error', message: 'Inject failed: ' + e.message }, '*');
      }
    };
    script.onerror = function() { return false; };
    document.body.appendChild(script);
  }

  // 主 CDN
  var script = document.createElement('script');
  script.src = 'https://www.geogebra.org/apps/deployggb.js';
  script.onload = function() {
    try {
      var applet = new GGBApplet(params, true);
      applet.setHTML5Codebase('https://www.geogebra.org/apps/latest/web3d/');
      applet.inject('ggb-element');
    } catch(e) {
      window.parent.postMessage({ type: 'ggb-error', message: 'Inject failed: ' + e.message }, '*');
    }
  };
  script.onerror = function() {
    loadGeoGebra('https://cdn.geogebra.org/apps/deployggb.js', 'https://cdn.geogebra.org/apps/latest/web3d/');
  };
  document.body.appendChild(script);
</script>
</body>
</html>''';
  }

  void _retry() {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    final freshViewType =
        'ggb-scene-retry-${DateTime.now().millisecondsSinceEpoch}';
    _viewType = freshViewType;
    _createGeoGebraView();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        HtmlElementView(viewType: _viewType),
        if (_loading)
          Container(
            color: cs.surface,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 12),
                  Text(
                    'GeoGebra 加载中...',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_hasError)
          Container(
            color: cs.surface,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    color: cs.onSurface.withValues(alpha: 0.4),
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'GeoGebra 加载失败',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }
}
