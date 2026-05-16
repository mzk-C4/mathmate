import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/data/conversation_models.dart';
import 'package:mathmate/data/conversation_repository.dart';
import 'package:mathmate/services/katex_pdf_service.dart';
import 'package:mathmate/services/model_service.dart';
import 'package:mathmate/services/vivo_chat_service.dart';

class ChatPage extends StatefulWidget {
  final int? conversationId;
  final String? initialQuery;
  final void Function(int)? onConversationCreated;

  const ChatPage({super.key, this.conversationId, this.initialQuery, this.onConversationCreated});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final VivoAiChatService _chatService = VivoAiChatService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<VivoChatMessage> _historyMessages = <VivoChatMessage>[];

  bool _isLoading = false;
  final FocusNode _inputFocus = FocusNode();
  bool _titleSet = false;
  int? _conversationId;

  static const String _systemPrompt =
      '你是数学解题助手。回答使用Markdown+LaTeX，严格遵守移动端排版规范：\n'
      '1. 强制块级公式：含 \\frac、\\sqrt、\\sum、复杂上下标的公式严禁用 \$...\$，'
      '必须用 \$\$...\$\$ 独占一行。简单方程表达式（如椭圆、直线方程）也独立成行用 \$\$...\$\$ 展示。'
      '对齐公式用 \$\$\\begin{aligned} ... \\end{aligned}\$\$。\n'
      '2. 公式前后各空一行，增加视觉呼吸感。块级公式与中文段落之间保持间距。\n'
      '3. 结构化拆解：已知条件用 - 列表逐条列出，公式也放入列表项中。'
      '已知条件与求解问题之间用 --- 分隔线区分。\n'
      '4. 每个小问用加粗序号 **(1)**、**(2)**，各自独占一行，不与正文混排。\n'
      '5. 关键数值加粗：**|AB|=√10**、**e=2√2/3**。\n'
      '6. 标题只用 ###，禁止使用 #### 或更多 # 号。列表用 -。\n'
      '7. 最终答案放在末尾，用 ### 标记。\n'
      '8. 中文回答，非数学问题引导回数学。';

  static const List<String> _suggestions = <String>[
    '如何解一元二次方程？',
    '什么是勾股定理？',
    '三角函数的基本关系有哪些？',
    '如何求函数的极值？',
  ];

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (_conversationId != null) {
      _loadConversation(_conversationId!);
    }
    _historyMessages.add(
      VivoChatMessage(role: 'system', content: _systemPrompt),
    );
    _inputController.addListener(_onInputChanged);
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendMessage(text: widget.initialQuery!);
      });
    }
  }

  void _onInputChanged() {
    setState(() {});
  }

  Future<void> _loadConversation(int id) async {
    final Conversation? conversation =
        await ConversationRepository.instance.getConversation(id);
    if (conversation == null || !mounted) return;

    final List<ChatMessage> loaded = <ChatMessage>[];
    for (final ChatMessageEmbedded msg in conversation.messages) {
      loaded.add(ChatMessage(
        role: msg.role,
        content: msg.content,
        reasoning: msg.reasoning,
        timestamp: msg.timestamp,
      ));
      _historyMessages.add(VivoChatMessage(role: msg.role, content: msg.content));
    }
    _titleSet = loaded.isNotEmpty;
    setState(() {
      _messages.addAll(loaded);
    });
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != oldWidget.conversationId) {
      _switchConversation(widget.conversationId);
    }
  }

  Future<void> _switchConversation(int? id) async {
    _messages.clear();
    _historyMessages.clear();
    _conversationId = id;
    _titleSet = false;
    _historyMessages.add(
      VivoChatMessage(role: 'system', content: _systemPrompt),
    );
    if (id != null) {
      await _loadConversation(id);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? text}) async {
    final String content = (text ?? _inputController.text).trim();
    if (content.isEmpty || _isLoading) return;

    _inputController.clear();
    final DateTime now = DateTime.now();
    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        content: content,
        timestamp: now,
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    _historyMessages.add(VivoChatMessage(role: 'user', content: content));

    final String title = content.length > 20
        ? '${content.substring(0, 20)}...'
        : content;

    if (_conversationId == null) {
      final Conversation conversation =
          await ConversationRepository.instance.createConversation(title);
      _conversationId = conversation.id;
      widget.onConversationCreated?.call(conversation.id);
    } else if (!_titleSet) {
      _titleSet = true;
      await ConversationRepository.instance.updateTitle(_conversationId!, title);
    } else {
      _titleSet = true;
    }

    await ConversationRepository.instance.addMessage(
      _conversationId!,
      ChatMessageEmbedded()
        ..role = 'user'
        ..content = content
        ..timestamp = now,
    );

    final List<VivoChatMessage> trimmedHistory = _trimHistory(_historyMessages);

    debugPrint('[ChatPage] 开始调用 chatService.sendMessage...');
    try {
      final VivoChatResponse response = await _chatService.sendMessage(
        trimmedHistory,
        modelId: ModelService.instance.currentModelId,
      );
      debugPrint('[ChatPage] 收到响应: ${response.content.length} 字符');
      // 调试：打印响应中所有 $ 包裹的内容
      final RegExp dollarPattern = RegExp(r'\$[^\$\n]+\$');
      final Iterable<Match> matches = dollarPattern.allMatches(response.content);
      if (matches.isEmpty) {
        debugPrint('[ChatPage] 响应中无不含换行的行内公式');
      } else {
        for (final Match m in matches) {
          final String f = m.group(0)!;
          if (f.length < 80) debugPrint('[ChatPage] 行内公式: $f');
        }
      }

      if (!mounted) return;

      final DateTime assistantNow = DateTime.now();
      final String assistantContent = response.content;

      _historyMessages.add(
        VivoChatMessage(role: 'assistant', content: assistantContent),
      );

      await ConversationRepository.instance.addMessage(
        _conversationId!,
        ChatMessageEmbedded()
          ..role = 'assistant'
          ..content = assistantContent
          ..reasoning = response.reasoning
          ..timestamp = assistantNow,
      );

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: assistantContent,
            reasoning: response.reasoning,
            timestamp: assistantNow,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            action: SnackBarAction(label: '重试', onPressed: _sendMessage),
          ),
        );
      }
    }
  }

  void _rebuildHistory() {
    _historyMessages.clear();
    _historyMessages.add(
      VivoChatMessage(role: 'system', content: _systemPrompt),
    );
    for (final ChatMessage msg in _messages) {
      _historyMessages.add(VivoChatMessage(role: msg.role, content: msg.content));
    }
  }

  List<ChatMessageEmbedded> _toEmbeddedList() {
    return _messages
        .map((ChatMessage m) => ChatMessageEmbedded()
          ..role = m.role
          ..content = m.content
          ..reasoning = m.reasoning
          ..timestamp = m.timestamp)
        .toList();
  }

  String _formatTimestamp(DateTime time) {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteMessageAt(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final ChatMessage target = _messages[index];
    if (target.role == 'user' &&
        index + 1 < _messages.length &&
        _messages[index + 1].role == 'assistant') {
      _messages.removeAt(index + 1);
      _messages.removeAt(index);
    } else {
      _messages.removeAt(index);
    }
    _rebuildHistory();
    if (_conversationId != null) {
      await ConversationRepository.instance
          .replaceMessages(_conversationId!, _toEmbeddedList());
    }
    if (mounted) setState(() {});
  }

  void _editMessageAt(int index) {
    if (index < 0 || index >= _messages.length) return;
    final ChatMessage target = _messages[index];
    if (target.role != 'user') return;
    _inputController.text = target.content;
    _inputFocus.requestFocus();
    // Remove from this index onward
    final int removeCount = _messages.length - index;
    for (int i = 0; i < removeCount; i++) {
      _messages.removeAt(index);
    }
    _rebuildHistory();
    if (_conversationId != null) {
      ConversationRepository.instance
          .replaceMessages(_conversationId!, _toEmbeddedList());
    }
    setState(() {});
  }

  Future<void> _regenerateLast() async {
    if (_messages.isEmpty) return;
    // Find last user message
    int userIndex = -1;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        userIndex = i;
        break;
      }
    }
    if (userIndex == -1) return;
    final String userContent = _messages[userIndex].content;
    // Remove last assistant message (and user message too, since sendMessage re-adds user)
    if (_messages.last.role == 'assistant') {
      _messages.removeLast();
    }
    _rebuildHistory();
    if (_conversationId != null && _messages.isNotEmpty) {
      await ConversationRepository.instance
          .replaceMessages(_conversationId!, _toEmbeddedList());
    }
    if (mounted) setState(() {});
    _sendMessage(text: userContent);
  }

  List<VivoChatMessage> _trimHistory(List<VivoChatMessage> full) {
    if (full.length <= 21) return full; // system + 10 rounds = 21 max
    return <VivoChatMessage>[
      full.first, // system prompt
      ...full.sublist(full.length - 20), // last 10 rounds
    ];
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _compileLatex(String content) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在生成 PDF...'),
        duration: Duration(seconds: 1),
      ),
    );

    final KatexPdfService pdfService = KatexPdfService();
    final KatexPdfResult result = await pdfService.exportToPdf(
      title: '蓝心数学助手 — 解答',
      content: content,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('HTML 文件已生成，请选择保存位置或浏览器打开'),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: ${result.error}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: _messages.isEmpty && !_isLoading
              ? _buildWelcomeScreen()
              : _buildMessageList(),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildWelcomeScreen() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 48),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 36,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '你好！我是蓝心数学助手',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '可以问我任何数学问题，我会一步步帮你解答',
            style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 32),
          ..._suggestions.map(_buildSuggestionCard),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(String question) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _sendMessage(text: question),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.help_outline, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                question,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
              ),
            ),
            Icon(Icons.chevron_right, size: 18,
                color: cs.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == _messages.length) {
          return _buildTypingIndicator();
        }
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildTypingIndicator() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TypingDot(delayMs: 0, color: cs.primary),
            const SizedBox(width: 4),
            _TypingDot(delayMs: 200, color: cs.primary),
            const SizedBox(width: 4),
            _TypingDot(delayMs: 400, color: cs.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isUser = message.role == 'user';
    final int msgIndex = _messages.indexOf(message);
    final bool isLastAi = !isUser && _messages.isNotEmpty && _messages.last == message &&
        !_isLoading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser && message.reasoning != null &&
              message.reasoning!.isNotEmpty)
            _buildReasoningCard(message.reasoning!),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: <Widget>[
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                  ),
                ),
              if (!isUser) const SizedBox(width: 8),
              Flexible(
                child: GestureDetector(
                  onLongPress: isUser
                      ? () => _editMessageAt(msgIndex)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? cs.primary : cs.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: isUser
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.shadow.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isUser
                        ? Text(
                            message.content,
                            style: TextStyle(
                              fontSize: 15,
                              color: cs.onPrimary,
                              height: 1.5,
                            ),
                          )
                        : _buildMarkdownContent(message.content),
                  ),
                ),
              ),
              if (isUser) const SizedBox(width: 8),
              if (isUser)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: cs.primary,
                    child: const Icon(Icons.person, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isUser ? 0 : 36,
              right: isUser ? 36 : 0,
              top: 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _formatTimestamp(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _copyMessage(message.content),
                  child: Icon(Icons.content_copy, size: 13,
                      color: cs.onSurface.withValues(alpha: 0.3)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _deleteMessageAt(msgIndex),
                  child: Icon(Icons.delete_outline, size: 13,
                      color: cs.onSurface.withValues(alpha: 0.3)),
                ),
                if (isLastAi) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _regenerateLast,
                    child: Icon(Icons.refresh, size: 13,
                        color: cs.onSurface.withValues(alpha: 0.3)),
                  ),
                ],
                if (!isUser) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _compileLatex(message.content),
                    child: Icon(Icons.picture_as_pdf, size: 13,
                        color: cs.onSurface.withValues(alpha: 0.3)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningCard(String reasoning) {
    return _ReasoningCard(reasoning: reasoning);
  }

  Widget _buildMarkdownContent(String text) {
    // 规范化标题层级：#### → ###，防止 h4+ 不被渲染
    String normalized = text.replaceAllMapped(
      RegExp(r'^#{4,6}\s+(.+)$', multiLine: true),
      (Match m) => '### ${m.group(1)}',
    );

    // 保护代码块，避免 $ 被误识别为数学公式
    final List<String> codeBlocks = <String>[];
    String processed = normalized.replaceAllMapped(
      RegExp(r'```[\s\S]*?```'),
      (Match m) {
        codeBlocks.add(m.group(0)!);
        return '\x00CODEBLOCK${codeBlocks.length - 1}\x00';
      },
    );

    // 保护行内代码
    final List<String> inlineCodes = <String>[];
    processed = processed.replaceAllMapped(
      RegExp(r'`[^`]+`'),
      (Match m) {
        inlineCodes.add(m.group(0)!);
        return '\x00INLINECODE${inlineCodes.length - 1}\x00';
      },
    );

    // 计算内容区可用宽度（气泡最大宽度 - 内边距）
    final double contentWidth = MediaQuery.of(context).size.width * 0.78 - 32;

    // 先按 $$...$$ 拆出展示公式块，剩余文本块再处理 $...$ 内联公式
    final List<Widget> blocks = <Widget>[];
    final RegExp displayMathRegex = RegExp(r'\$\$([\s\S]*?)\$\$');

    int lastEnd = 0;
    for (final RegExpMatch match in displayMathRegex.allMatches(processed)) {
      if (match.start > lastEnd) {
        final String textBefore = processed.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          blocks.addAll(_buildInlineContent(textBefore, codeBlocks, inlineCodes, contentWidth));
        }
      }

      final String latex = (match.group(1) ?? '').trim();
      if (latex.isNotEmpty) {
        try {
          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Math.tex(
                      latex,
                      mathStyle: MathStyle.display,
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          );
        } catch (_) {
          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(latex, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
            ),
          );
        }
      }
      lastEnd = match.end;
    }

    if (lastEnd < processed.length) {
      final String remaining = processed.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        blocks.addAll(_buildInlineContent(remaining, codeBlocks, inlineCodes, contentWidth));
      }
    }

    if (blocks.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF333333)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  /// 渲染两个展示公式之间的文本块。
  ///
  /// 核心策略：先按 \n\n 拆段落，然后每段整体渲染。段落内无 $...$ 公式的走
  /// [MarkdownBody]（保留完整 Markdown 格式）；段落内有 $...$ 公式的走
  /// [Text.rich] + [WidgetSpan]（保证公式与文字正确混排、不孤行、不破坏列表结构）。
  List<Widget> _buildInlineContent(String text, List<String> codeBlocks, List<String> inlineCodes, double maxWidth) {
    final String restored = _restorePlaceholders(text, codeBlocks, inlineCodes);
    final RegExp inlineMathRegex = RegExp(r'\$([^\$\n]+)\$');

    // 整个文本块都没有内联公式 → 单次 MarkdownBody（最优路径）
    if (!inlineMathRegex.hasMatch(restored)) {
      return <Widget>[_mdWidget(restored)];
    }

    // 调试：打印所有匹配到的内联公式
    for (final Match m in inlineMathRegex.allMatches(restored)) {
      final String latex = (m.group(1) ?? '').trim();
      if (latex.isNotEmpty && latex.length < 60) {
        debugPrint('[InlineMath] found: \$$latex\$');
      }
    }

    // 有内联公式 → 按段落拆分，每段独立渲染
    final List<String> paragraphs = restored.split(RegExp(r'\n\n+'));
    final List<Widget> result = <Widget>[];
    for (int i = 0; i < paragraphs.length; i++) {
      final String para = paragraphs[i].trim();
      if (para.isEmpty) continue;

      if (inlineMathRegex.hasMatch(para)) {
        result.add(_buildRichParagraph(para));
      } else {
        result.add(_mdWidget(para));
      }

      if (i < paragraphs.length - 1) {
        result.add(const SizedBox(height: 6));
      }
    }

    if (result.isEmpty && restored.isNotEmpty) {
      result.add(_mdWidget(restored));
    }
    return result;
  }

  /// 将含内联公式的单个段落渲染为 [Text.rich] + [WidgetSpan]，保证公式与文字正确混排。
  Widget _buildRichParagraph(String text) {
    final RegExp inlineMathRegex = RegExp(r'\$([^\$\n]+)\$');
    final List<InlineSpan> spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final RegExpMatch match in inlineMathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.addAll(_mdTextToSpans(text.substring(lastEnd, match.start)));
      }

      final String latex = (match.group(1) ?? '').trim();
      if (latex.isNotEmpty) {
        try {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              latex,
              mathStyle: MathStyle.text,
              textStyle: const TextStyle(fontSize: 15),
              onErrorFallback: (_) {
                debugPrint('[InlineMath] error: $latex');
                return Text(
                  latex,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                );
              },
            ),
          ));
        } catch (e) {
          debugPrint('[InlineMath] exception: $e for: $latex');
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Text(
              latex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ));
        }
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.addAll(_mdTextToSpans(text.substring(lastEnd)));
    }

    return SelectionArea(
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF333333)),
          children: spans,
        ),
      ),
    );
  }

  /// 将纯文本片段解析为 [InlineSpan]，支持 **加粗**、*斜体*、`行内代码`、###/## 标题。
  static final RegExp _mdTokenRegex = RegExp(
    r'(\*\*(.+?)\*\*)'       // **bold**
    r'|(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)' // *italic*
    r'|(`[^`]+`)'            // `code`
  );

  static List<InlineSpan> _mdTextToSpans(String text) {
    final List<InlineSpan> spans = <InlineSpan>[];
    const Color c = Color(0xFF333333);

    // 检测 ### / ## 标题行（段落级已在调用方处理，这里做兜底）
    String content = text;
    TextStyle? baseStyle;
    if (content.startsWith('### ')) {
      content = content.substring(4);
      baseStyle = const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.5, color: c);
    } else if (content.startsWith('## ')) {
      content = content.substring(3);
      baseStyle = const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.5, color: c);
    }

    int lastEnd = 0;
    for (final Match match in _mdTokenRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(2), style: (baseStyle ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: (baseStyle ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: c)));
      }
      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      spans.add(TextSpan(text: content.substring(lastEnd), style: baseStyle));
    }

    if (spans.isEmpty && text.isNotEmpty) {
      spans.add(TextSpan(text: text));
    }
    return spans;
  }

  String _restorePlaceholders(String text, List<String> codeBlocks, List<String> inlineCodes) {
    String result = text;
    for (int i = 0; i < codeBlocks.length; i++) {
      result = result.replaceAll('\x00CODEBLOCK$i\x00', codeBlocks[i]);
    }
    for (int i = 0; i < inlineCodes.length; i++) {
      result = result.replaceAll('\x00INLINECODE$i\x00', inlineCodes[i]);
    }
    return result;
  }

  Widget _mdWidget(String data) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: _mdStyle(context),
    );
  }

  static MarkdownStyleSheet _mdStyle(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(fontSize: 15, height: 1.7, color: cs.onSurface),
      code: TextStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        backgroundColor: cs.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      h2: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
        height: 1.5,
      ),
      h3: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
        height: 1.5,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
    );
  }

  Widget _buildInputBar() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool hasText = _inputController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: <Widget>[
            Icon(Icons.search, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                readOnly: _isLoading,
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: '输入数学问题...',
                  hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: hasText && !_isLoading ? () => _sendMessage() : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hasText && !_isLoading
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isLoading ? Icons.hourglass_top : Icons.send_rounded,
                  color: hasText && !_isLoading
                      ? cs.onPrimary
                      : cs.onSurface.withValues(alpha: 0.3),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int delayMs;
  final Color color;
  const _TypingDot({required this.delayMs, this.color = const Color(0xFF3F51B5)});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ReasoningCard extends StatefulWidget {
  final String reasoning;
  const _ReasoningCard({required this.reasoning});

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.psychology_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  '思考过程',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.primary,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                widget.reasoning,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  final String? reasoning;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.reasoning,
    required this.timestamp,
  });
}
