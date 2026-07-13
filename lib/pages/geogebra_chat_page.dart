// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/geogebra/geochat_history_builder.dart';
import 'package:mathmate/geogebra/geogebra_web_engine.dart';
import 'package:mathmate/geogebra/geometry_plan_tool_handler.dart';
import 'package:mathmate/services/geogebra_agent_service.dart';
import 'package:mathmate/visualization/geogebra_web_renderer.dart';

/// GeoGebra Agent 聊天页面 —— Web 端专用。
///
/// 全屏 GeoGebra 画布 + 悬浮对话面板。用户通过自然语言描述几何需求，
/// AI Agent 通过工具调用操控 GeoGebra 画布绘制图形。
class GeogebraChatPage extends StatefulWidget {
  const GeogebraChatPage({super.key});

  @override
  State<GeogebraChatPage> createState() => _GeogebraChatPageState();
}

class _GeogebraChatPageState extends State<GeogebraChatPage> {
  final GeogebraAgentService _agent = GeogebraAgentService();
  final GeochatHistoryBuilder _historyBuilder = const GeochatHistoryBuilder();
  final GeometryPlanToolHandler _planToolHandler = GeometryPlanToolHandler(
    engine: const GeogebraWebEngine(),
  );
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<ChatBubble> _bubbles = <ChatBubble>[];

  bool _isLoading = false;
  bool _ggbReady = false;

  @override
  void initState() {
    super.initState();
    // 监听 GeoGebra ready 事件
    html.window.onMessage.listen(_onWindowMessage);
    // 注入工具执行回调
    _agent.onToolCall = _executeTool;
  }

  void _onWindowMessage(html.MessageEvent event) {
    final data = event.data;
    if (data is Map && data['type'] == 'ggb-ready') {
      if (mounted) setState(() => _ggbReady = true);
    }
  }

  /// 工具执行回调 —— 桥接 Agent Service 与 GeoGebra JS Bridge。
  Future<String> _executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (toolName) {
        case 'getCanvasContext':
          final xml = await GeogebraJSBridge.getXML();
          final objects = await GeogebraJSBridge.getSelectedObjects();
          return _summarizeXML(xml, objects);

        case 'executeGeoGebraCommand':
          final cmd = args['command'] as String? ?? '';
          if (cmd.isEmpty) return 'Error: empty command';
          final result = await GeogebraJSBridge.evalCommand(cmd);
          if (result['success'] == true) {
            return '成功: ${result['label'] ?? "OK"}';
          } else {
            return '失败: ${result['error'] ?? "未知错误"}';
          }

        case 'executeGeoGebraPlan':
          return _planToolHandler.execute(args);

        case 'deleteGeoGebraObject':
          final label = args['label'] as String? ?? '';
          final ok = await GeogebraJSBridge.deleteObject(label);
          return ok ? '已删除 $label' : '删除 $label 失败';

        case 'setUndoPoint':
          final ok = await GeogebraJSBridge.setUndoPoint();
          return ok ? '撤销点已设置' : '设置撤销点失败';

        case 'undo':
          final ok = await GeogebraJSBridge.undo();
          return ok ? '已撤销' : '撤销失败';

        case 'setPerspective':
          final mode = args['mode'] as String? ?? 'G';
          final ok = await GeogebraJSBridge.setPerspective(mode);
          return ok ? '视图已切换为 $mode' : '切换视图失败';

        case 'getSelectedObjects':
          final objects = await GeogebraJSBridge.getSelectedObjects();
          return objects.isEmpty ? '无选中对象' : '选中: ${objects.join(", ")}';

        default:
          return '未知工具: $toolName';
      }
    } catch (e) {
      return '工具执行异常: $e';
    }
  }

  /// 简化 XML → 可读摘要（类似 GeoChat 的 getCanvasContext）。
  String _summarizeXML(String xml, List<String> selected) {
    if (xml.isEmpty) return '{}';
    // 提取 construction 中的 element 标签
    final elementExp = RegExp(r'<element[^>]*type="(\w+)"[^>]*label="([^"]*)"');
    final matches = elementExp.allMatches(xml);
    final elements = matches.map((m) => '${m.group(1)}:${m.group(2)}').toList();

    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln(
      '  "elements": ${elements.isNotEmpty ? elements.toString() : "[]"},',
    );
    buffer.writeln('  "selectedObjects": ${selected.toString()}');
    buffer.writeln('}');
    return buffer.toString();
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    _inputCtrl.clear();
    setState(() {
      _bubbles.add(ChatBubble(role: 'user', content: text));
      _bubbles.add(
        ChatBubble(role: 'assistant', content: '', isStreaming: true),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    final List<Map<String, String>> history = _historyBuilder.build(
      _bubbles.map(
        (ChatBubble bubble) => GeochatHistoryEntry(
          role: bubble.role,
          content: bubble.content,
          isStreaming: bubble.isStreaming,
        ),
      ),
    );

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
        } else if (chunk.toolResult != null) {
          if (pendingTool.isNotEmpty) {
            final String displayedResult = pendingTool == 'executeGeoGebraPlan'
                ? GeometryPlanToolHandler.describeResult(chunk.toolResult!)
                : chunk.toolResult!;
            fullContent += '\n\n🔧 `$pendingTool` → $displayedResult';
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

  void _clearCanvas() {
    GeogebraJSBridge.reset();
    setState(() => _bubbles.clear());
  }

  void _undoLast() {
    GeogebraJSBridge.undo();
  }

  @override
  void dispose() {
    _agent.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // 全屏 GeoGebra 画布
          const Positioned.fill(child: GeogebraWebRenderer(interactive: true)),

          // 顶部工具栏
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            right: 8,
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black38),
                ),
                const Spacer(),
                if (!_ggbReady)
                  const Chip(
                    label: Text(
                      '加载中...',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    backgroundColor: Colors.black38,
                  ),
                IconButton(
                  onPressed: _undoLast,
                  icon: const Icon(Icons.undo, color: Colors.white),
                  tooltip: '撤销',
                  style: IconButton.styleFrom(backgroundColor: Colors.black38),
                ),
                IconButton(
                  onPressed: _clearCanvas,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: '清空画布',
                  style: IconButton.styleFrom(backgroundColor: Colors.black38),
                ),
              ],
            ),
          ),

          // 悬浮对话面板
          Positioned(
            right: 8,
            bottom: 8,
            width: 380,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.55,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.draw, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'GeoGebra 助手',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _ggbReady ? Colors.green : Colors.orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _ggbReady ? '就绪' : '等待...',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 消息列表
                  Expanded(
                    child: _bubbles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
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
                                _buildSuggestions(),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(12),
                            itemCount: _bubbles.length,
                            itemBuilder: (_, i) => _buildBubble(_bubbles[i]),
                          ),
                  ),

                  // 输入栏
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            minLines: 1,
                            maxLines: 3,
                            enabled: !_isLoading && _ggbReady,
                            decoration: InputDecoration(
                              hintText: _ggbReady
                                  ? '描述你要画的图形...'
                                  : '等待 GeoGebra 就绪...',
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
                          onPressed: _isLoading || !_ggbReady
                              ? null
                              : _sendMessage,
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
                          style: IconButton.styleFrom(
                            backgroundColor: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      '画一个以A为圆心，半径为3的圆',
      '画一个三角形ABC',
      '画椭圆 x²/4 + y²/9 = 1',
      '画双曲线 x²/4 - y²/9 = 1',
      '画出 y = x² 和它的切线',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: suggestions
          .map(
            (s) => ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 11)),
              onPressed: () {
                _inputCtrl.text = s;
                _sendMessage();
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildBubble(ChatBubble bubble) {
    final cs = Theme.of(context).colorScheme;
    final isUser = bubble.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            constraints: BoxConstraints(maxWidth: 320),
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
                : _buildMarkdown(bubble.content),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdown(String text) {
    // 简化渲染 —— 处理工具调用标记和 LaTeX
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
      } else if (line.contains(r'$$')) {
        // 提取 LaTeX
        final regex = RegExp(r'\$\$([^$]+)\$\$');
        for (final match in regex.allMatches(line)) {
          final latex = match.group(1) ?? '';
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Math.tex(latex, textStyle: const TextStyle(fontSize: 14)),
            ),
          );
        }
      } else if (line.trim().isNotEmpty) {
        // 处理行内公式 $...$
        final inlineRegex = RegExp(r'\$([^$]+)\$');
        if (inlineRegex.hasMatch(line)) {
          final spans = <InlineSpan>[];
          int lastEnd = 0;
          for (final m in inlineRegex.allMatches(line)) {
            if (m.start > lastEnd) {
              spans.add(TextSpan(text: line.substring(lastEnd, m.start)));
            }
            final latex = m.group(1) ?? '';
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Math.tex(
                  latex,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            );
            lastEnd = m.end;
          }
          if (lastEnd < line.length) {
            spans.add(TextSpan(text: line.substring(lastEnd)));
          }
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13, height: 1.5),
                  children: spans,
                ),
              ),
            ),
          );
        } else {
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
    }

    if (widgets.isEmpty) {
      return const Text('', style: TextStyle(fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
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
