import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mathmate/geogebra/geogebra_asset_manager.dart';
import 'package:mathmate/geogebra/geogebra_canvas_context.dart';
import 'package:mathmate/geogebra/offline_geometry_command_parser.dart';
import 'package:mathmate/geogebra/geochat_session_store.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:mathmate/services/geogebra_agent_service.dart';
import 'package:mathmate/visualization/geogebra_mobile_bridge.dart';

/// 原生 Flutter GeoGebra Chat 页面 —— 移动端专用。
///
/// 架构：
/// - 上半：GeoGebra 画布（WebView 加载本地 HTML + JS Bridge 注入）
/// - 下半：聊天对话面板（Agent 流式响应 + 工具调用）
class GeogebraChatPage extends StatefulWidget {
  const GeogebraChatPage({super.key});

  @override
  State<GeogebraChatPage> createState() => _GeogebraChatPageState();
}

class _GeogebraChatPageState extends State<GeogebraChatPage> {
  final GeogebraAgentService _agent = GeogebraAgentService();
  final GeogebraCanvasContextParser _contextParser =
      const GeogebraCanvasContextParser();
  final OfflineGeometryCommandParser _offlineParser =
      const OfflineGeometryCommandParser();
  final GeochatSessionStore _sessionStore = GeochatSessionStore();
  late GeogebraMobileBridge _bridge;

  WebViewController? _ggbController;
  bool _ggbReady = false;
  bool _ggbLoading = true;
  String? _ggbError;
  bool _sessionRestored = false;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<ChatBubble> _bubbles = [];
  bool _isLoading = false;
  double _chatHeightFraction = 4.0 / 7.0;

  @override
  void initState() {
    super.initState();
    _initGeoGebra();
  }

  Future<void> _initGeoGebra() async {
    if (_ggbController != null) {
      _bridge.dispose();
    }
    if (mounted) {
      setState(() {
        _ggbController = null;
        _ggbReady = false;
        _ggbLoading = true;
        _ggbError = null;
        _sessionRestored = false;
      });
    }

    try {
      final ctrl = WebViewController();
      ctrl.setJavaScriptMode(JavaScriptMode.unrestricted);
      ctrl.setBackgroundColor(const Color(0xFFFFFFFF));

      _bridge = GeogebraMobileBridge(ctrl);
      _ggbController = ctrl;
      _agent.onToolCall = _executeTool;

      ctrl.addJavaScriptChannel(
        'GgbBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          if (_ggbController != ctrl) return;
          if (msg.message.startsWith('ready|')) {
            _bridge.markReady();
            if (mounted) {
              setState(() {
                _ggbReady = true;
                _ggbLoading = false;
                _ggbError = null;
              });
            }
            unawaited(_restoreSession());
            return;
          }
          if (msg.message.startsWith('error|0|')) {
            _setGeoGebraLoadError('本地几何引擎启动超时，请重试。');
            return;
          }
          _bridge.handleMessage(msg.message);
        },
      );

      // 自动解压本地 GeoGebra 离线文件（与数学工具箱一致），不再依赖 CDN
      // GeoChat needs the full geometry command set (Rotate, Polygon, Tangent,
      // transformations, ...). The graphing app deliberately filters several
      // of those commands, so it remains suitable for the toolbox but not here.
      final localPath = await GeogebraAssetManager.htmlPath('geometry.html');

      ctrl.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            try {
              await _injectBridge(ctrl);
            } catch (error) {
              _setGeoGebraLoadError('本地几何引擎连接失败，请重试。');
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) return;
            _setGeoGebraLoadError('本地几何引擎页面加载失败：${error.description}');
          },
        ),
      );
      await ctrl.loadFile(localPath);
    } catch (e) {
      debugPrint('[GeoChat] Init error: $e');
      _setGeoGebraLoadError('本地几何引擎初始化失败，请重试。');
    }
  }

  void _setGeoGebraLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _ggbReady = false;
      _ggbLoading = false;
      _ggbError = message;
    });
  }

  /// 注入 JS Bridge —— 仅本地 GeoGebra 5.4 文件需要（CDN 版 HTML 已内置）
  Future<void> _injectBridge(WebViewController ctrl) async {
    const bridgeJs = '''
(function() {
  if (window._ggbBridgeReady) return;
  var ggb = null;
  function ready(api) {
    ggb = api;
    window._ggbBridgeReady = true;
    // 隐藏 GeoGebra 自带菜单栏、工具栏、代数输入（保持画布纯净）
    try { if (typeof ggb.setShowMenuBar === 'function') ggb.setShowMenuBar(false); } catch(e) {}
    try { if (typeof ggb.setShowToolBar === 'function') ggb.setShowToolBar(false); } catch(e) {}
    try { if (typeof ggb.setShowAlgebraInput === 'function') ggb.setShowAlgebraInput(false); } catch(e) {}
    window._ggbBridgeCallback = function(msg) {
      var p = msg.split('|'), t = p[0], id = p[1], pl = p.slice(2).join('|');
      try {
        var r = '';
        switch(t) {
          case 'evalCommand':
            // GeoGebra 5.x 用 evalCommand，6.x 用 evalCommandGetLabels
            if (typeof ggb.evalCommandGetLabels === 'function') {
              var lb = ggb.evalCommandGetLabels(pl);
              var er = '';
              try { er = ggb.getErrorString() || ''; } catch(e) {}
              r = JSON.stringify({success: !er, label: lb||null, error: er||null});
            } else if (typeof ggb.evalCommand === 'function') {
              var ok = ggb.evalCommand(pl);
              var err = '';
              try { err = ggb.getErrorString ? ggb.getErrorString() : ''; } catch(e) {}
              r = JSON.stringify({success: ok && !err, label: null, error: err||null});
            } else {
              r = JSON.stringify({success: false, label: null, error: 'no evalCommand API'});
            }
            break;
          case 'getXML':
            try { r = ggb.getXML ? ggb.getXML() : ''; } catch(e) { r = ''; }
            break;
          case 'setXML':
            try { if (ggb.setXML) ggb.setXML(pl); } catch(e) {}
            r = 'true';
            break;
          case 'deleteObject':
            try { ggb.deleteObject(pl); } catch(e) {}
            r = 'true';
            break;
          case 'setUndoPoint':
            try { ggb.setUndoPoint(); } catch(e) {}
            r = 'true';
            break;
          case 'undo':
            try { ggb.undo(); } catch(e) {}
            r = 'true';
            break;
          case 'setPerspective':
            try { ggb.setPerspective(pl); } catch(e) {}
            r = 'true';
            break;
          case 'reset':
            try { ggb.reset(); } catch(e) {}
            r = 'true';
            break;
          case 'getSelectedObjects':
            try { r = ggb.getSelectedObjects ? ggb.getSelectedObjects().join(',') : ''; } catch(e) { r = ''; }
            break;
        }
        GgbBridge.postMessage(t + '|' + id + '|' + r);
      } catch(e) { GgbBridge.postMessage('error|' + id + '|' + e.toString()); }
    };
    GgbBridge.postMessage('ready|0|{}');
  }
  if (window.ggbApplet) { ready(window.ggbApplet); return; }
  if (window.ggbApp && window.ggbApp.evalCommand) { ready(window.ggbApp); return; }
  var n = 0;
  var iv = setInterval(function() {
    n++;
    var api = window.ggbApplet || window.ggbApp || null;
    if (api && (typeof api.evalCommand === 'function' || typeof api.evalCommandGetLabels === 'function')) {
      clearInterval(iv); ready(api);
    } else if (n > 150) {
      clearInterval(iv);
      GgbBridge.postMessage('error|0|GeoGebra API not found after timeout');
    }
  }, 100);
})();
''';
    await ctrl.runJavaScript(bridgeJs);
  }

  /// 桥接 Agent 工具调用到 GeoGebra
  Future<String> _executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (toolName) {
        case 'getCanvasContext':
          final xml = await _bridge.getXML();
          final selected = await _bridge.getSelectedObjects();
          return _contextParser
              .parse(xml, selectedObjects: selected)
              .toString();

        case 'executeGeoGebraCommand':
          final cmd = args['command'] as String? ?? '';
          if (cmd.isEmpty) return 'Error: empty command';
          final result = await _bridge.evalCommand(cmd);
          if (result['success'] == true) {
            return '成功: ${result['label'] ?? "OK"}';
          }
          return '失败: ${result['error'] ?? "未知错误"}';

        case 'deleteGeoGebraObject':
          final label = args['label'] as String? ?? '';
          final ok = await _bridge.deleteObject(label);
          return ok ? '已删除 $label' : '删除 $label 失败';

        case 'setUndoPoint':
          final ok = await _bridge.setUndoPoint();
          return ok ? '撤销点已设置' : '设置撤销点失败';

        case 'undo':
          final ok = await _bridge.undo();
          return ok ? '已撤销' : '撤销失败';

        case 'setPerspective':
          final mode = args['mode'] as String? ?? 'G';
          final ok = await _bridge.setPerspective(mode);
          return ok ? '切换至 ${mode == 'T' ? '3D' : '2D'} 视图' : '切换视图失败';

        case 'getSelectedObjects':
          final objects = await _bridge.getSelectedObjects();
          return objects.isEmpty ? '无选中对象' : '选中: ${objects.join(", ")}';

        default:
          return '未知工具: $toolName';
      }
    } catch (e) {
      return '工具执行异常: $e';
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading || !_ggbReady) return;

    _inputCtrl.clear();
    setState(() {
      _bubbles.add(ChatBubble(role: 'user', content: text));
      _bubbles.add(
        ChatBubble(role: 'assistant', content: '', isStreaming: true),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    final OfflineGeometryPlan? localPlan = _offlineParser.parse(text);
    if (localPlan != null) {
      await _executeOfflinePlan(localPlan);
      return;
    }

    final history = <Map<String, String>>[];
    for (final b in _bubbles.where((b) => !b.isStreaming)) {
      history.add({'role': b.role, 'content': b.content});
    }

    try {
      final assistantIdx = _bubbles.length - 1;
      String fullContent = '';
      String pendingTool = '';

      await for (final chunk in _agent.chat(messages: history)) {
        if (!mounted) break;

        if (chunk.error != null) {
          fullContent += '\n\n> ⚠️ ${chunk.error}';
        } else if (chunk.toolCallName != null) {
          pendingTool = chunk.toolCallName!;
          // 立即显示工具调用状态
          fullContent += '\n\n⏳ 调用工具: `$pendingTool`...';
        } else if (chunk.toolResult != null) {
          // 替换掉之前的 ⏳ 占位为实际结果
          if (pendingTool.isNotEmpty) {
            final placeholder = '\n\n⏳ 调用工具: `$pendingTool`...';
            fullContent = fullContent.replaceFirst(
              placeholder,
              '\n\n✅ `$pendingTool` → ${chunk.toolResult}',
            );
            pendingTool = '';
          }
        } else if (chunk.textDelta != null) {
          fullContent += chunk.textDelta!;
        }

        if (mounted) {
          setState(() {
            _bubbles[assistantIdx] = ChatBubble(
              role: 'assistant',
              content: fullContent,
              isStreaming: !chunk.isDone,
            );
          });
          _scrollToBottom();
        }

        if (chunk.isDone) break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _bubbles.length - 1;
          _bubbles[idx] = ChatBubble(role: 'assistant', content: '请求失败: $e');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      unawaited(_persistSession());
    }
  }

  Future<void> _executeOfflinePlan(OfflineGeometryPlan plan) async {
    final int assistantIndex = _bubbles.length - 1;
    final List<String> failures = <String>[];
    try {
      await _bridge.setUndoPoint();
      for (final String command in plan.commands) {
        final Map<String, dynamic> result = await _bridge.evalCommand(command);
        if (result['success'] != true) {
          failures.add('$command: ${result['error'] ?? '命令执行失败'}');
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _bubbles[assistantIndex] = ChatBubble(
          role: 'assistant',
          content: failures.isEmpty
              ? '📱 ${plan.summary}\n\n本次使用 APP 本地解析，未请求大模型。'
              : '本地绘图失败：${failures.join('\n')}',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bubbles[assistantIndex] = ChatBubble(
          role: 'assistant',
          content: '本地绘图失败：$error',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
      unawaited(_persistSession());
    }
  }

  Future<void> _restoreSession() async {
    if (_sessionRestored || !_bridge.isReady) return;
    _sessionRestored = true;
    final GeochatSessionSnapshot? snapshot = await _sessionStore.load();
    if (snapshot == null) return;

    if (snapshot.canvasXml.isNotEmpty) {
      await _bridge.setXML(snapshot.canvasXml);
    }
    if (!mounted || snapshot.messages.isEmpty) return;
    setState(() {
      _bubbles
        ..clear()
        ..addAll(
          snapshot.messages.map(
            (Map<String, dynamic> message) => ChatBubble(
              role: message['role'] as String? ?? 'assistant',
              content: message['content'] as String? ?? '',
            ),
          ),
        );
    });
    _scrollToBottom();
  }

  Future<void> _persistSession() async {
    if (!_bridge.isReady) return;
    try {
      final String xml = await _bridge.getXML();
      await _sessionStore.save(
        GeochatSessionSnapshot(
          canvasXml: xml,
          messages: _bubbles
              .where((ChatBubble bubble) => !bubble.isStreaming)
              .map(
                (ChatBubble bubble) => <String, dynamic>{
                  'role': bubble.role,
                  'content': bubble.content,
                },
              )
              .toList(growable: false),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      debugPrint('[GeoChat] Failed to save session: $error');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearCanvas() async {
    if (_isLoading) {
      _agent.cancel();
      setState(() => _isLoading = false);
      return;
    }
    if (!_ggbReady) return;
    await _bridge.reset();
    await _sessionStore.clear();
    if (!mounted) return;
    setState(() => _bubbles.clear());
  }

  Future<void> _undoLast() async {
    if (!_ggbReady) return;
    try {
      final bool undone = await _bridge.undo();
      if (undone) await _persistSession();
    } catch (error) {
      debugPrint('[GeoChat] Undo failed: $error');
    }
  }

  @override
  void dispose() {
    _agent.cancel();
    if (_ggbController != null) {
      _bridge.dispose();
    }
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalHeight = constraints.maxHeight;
          const dividerHeight = 24.0;
          final availableHeight = (totalHeight - dividerHeight).clamp(
            0.0,
            totalHeight,
          );
          final canvasHeight = (availableHeight * (1 - _chatHeightFraction))
              .clamp(0.0, availableHeight);
          final chatHeight = (availableHeight * _chatHeightFraction).clamp(
            0.0,
            availableHeight,
          );

          return Column(
            children: [
              // GeoGebra 画布区域
              SizedBox(
                height: canvasHeight,
                child: Stack(
                  children: [
                    if (_ggbController != null)
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: WebViewWidget(controller: _ggbController!),
                        ),
                      ),
                    if (_ggbLoading)
                      const Center(child: CircularProgressIndicator()),
                    if (_ggbError != null)
                      Positioned.fill(
                        child: ColoredBox(
                          color: cs.surface,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 40,
                                    color: cs.error,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _ggbError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: cs.onSurface),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _initGeoGebra,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('重新加载'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // GeoGebra ready 标记
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 20,
                      left: 8,
                      right: 8,
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black38,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _ggbError != null
                                  ? Colors.red
                                  : _ggbReady
                                  ? Colors.green
                                  : Colors.orange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _ggbError != null
                                  ? '加载失败'
                                  : _ggbReady
                                  ? '就绪'
                                  : '等待...',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _ggbReady ? _undoLast : null,
                            icon: const Icon(Icons.undo, color: Colors.white),
                            tooltip: '撤销',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black38,
                            ),
                          ),
                          IconButton(
                            onPressed: _clearCanvas,
                            icon: Icon(
                              _isLoading ? Icons.stop : Icons.delete_outline,
                              color: Colors.white,
                            ),
                            tooltip: _isLoading ? '中止任务' : '清空画布',
                            style: IconButton.styleFrom(
                              backgroundColor: _isLoading
                                  ? Colors.red.withValues(alpha: 0.7)
                                  : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 可拖拽分隔栏
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (availableHeight <= 0) return;
                  setState(() {
                    _chatHeightFraction -= details.delta.dy / availableHeight;
                    _chatHeightFraction = _chatHeightFraction.clamp(0.15, 0.85);
                  });
                },
                child: Container(
                  height: dividerHeight,
                  color: cs.surface,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              // 聊天区域
              SizedBox(
                height: chatHeight,
                child: Column(
                  children: [
                    // 标题栏
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: cs.primaryContainer.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          Icon(Icons.draw, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            '对话绘图',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 消息列表
                    Expanded(
                      child: _bubbles.isEmpty
                          ? _buildEmptyState(cs)
                          : ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.all(12),
                              itemCount: _bubbles.length,
                              itemBuilder: (_, i) =>
                                  _buildBubble(_bubbles[i], cs),
                            ),
                    ),

                    // 输入栏
                    _buildInputBar(cs),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    final suggestions = [
      '画一个以A为圆心，半径为3的圆',
      '画一个三角形ABC',
      '画椭圆 x²/4 + y²/9 = 1',
      '画出 y = x² 和它的切线',
      '画一个正六边形',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: cs.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 8),
          Text(
            '描述你想绘制的图形',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: suggestions
                .map(
                  (s) => ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    onPressed: _ggbReady
                        ? () {
                            _inputCtrl.text = s;
                            _sendMessage();
                          }
                        : null,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatBubble bubble, ColorScheme cs) {
    final isUser = bubble.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: isUser
                ? Text(
                    bubble.content,
                    style: TextStyle(fontSize: 14, color: cs.onPrimary),
                  )
                : bubble.isStreaming && bubble.content.isEmpty
                ? SizedBox(
                    width: 40,
                    child: LinearProgressIndicator(
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                    ),
                  )
                : _buildAssistantContent(bubble.content),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantContent(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      if (line.startsWith('🔧')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      } else if (line.startsWith('> ⚠️')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        );
      } else if (line.trim().isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        );
      }
    }

    if (widgets.isEmpty) return const Text('');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 3,
                enabled: !_isLoading && _ggbReady,
                decoration: InputDecoration(
                  hintText: _ggbReady ? '描述你要画的图形...' : '等待 GeoGebra 就绪...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isLoading || !_ggbReady ? null : _sendMessage,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 18),
              style: IconButton.styleFrom(backgroundColor: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatBubble {
  final String role;
  final String content;
  final bool isStreaming;
  ChatBubble({
    required this.role,
    required this.content,
    this.isStreaming = false,
  });
}
