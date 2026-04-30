import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/data/conversation_models.dart';
import 'package:mathmate/data/conversation_repository.dart';
import 'package:mathmate/services/chat_stream_service.dart';
import 'package:mathmate/services/latex_compiler.dart';
import 'package:mathmate/services/model_service.dart';
import 'package:mathmate/services/vivo_chat_service.dart';

enum ChatState { idle, streaming, error }

class ChatPage extends StatefulWidget {
  final int? conversationId;

  const ChatPage({super.key, this.conversationId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatStreamService _streamService = ChatStreamService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<VivoChatMessage> _historyMessages = <VivoChatMessage>[];

  ChatState _chatState = ChatState.idle;
  String _streamingContent = '';
  String? _streamingReasoning;
  final FocusNode _inputFocus = FocusNode();
  bool _titleSet = false;
  int? _conversationId;

  static const String _systemPrompt =
      '你是数学解题助手。规则：1.用LaTeX输出公式(行内\$...\$,独立\$\$...\$\$)；'
      '2.分步骤编号解答；3.重点加粗；4.最终答案放最后。中文回答。非数学问题请引导回数学。';

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
    if (content.isEmpty || _chatState == ChatState.streaming) return;

    _inputController.clear();
    final DateTime now = DateTime.now();
    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        content: content,
        timestamp: now,
      ));
      _chatState = ChatState.streaming;
      _streamingContent = '';
      _streamingReasoning = null;
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

    try {
      final Stream<StreamChunk> stream = _streamService.sendMessageStream(
        messages: trimmedHistory,
        modelId: ModelService.instance.currentModelId,
      );

      await for (final StreamChunk chunk in stream) {
        if (!mounted || _chatState != ChatState.streaming) break;
        if (chunk.error != null) {
          _historyMessages.removeLast(); // remove user msg
          setState(() { _chatState = ChatState.error; });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('发送失败: ${chunk.error}'),
                action: SnackBarAction(label: '重试', onPressed: _sendMessage),
              ),
            );
          }
          return;
        }
        if (chunk.isDone) break;
        if (chunk.content != null) _streamingContent += chunk.content!;
        if (chunk.reasoning != null) {
          _streamingReasoning = (_streamingReasoning ?? '') + chunk.reasoning!;
        }
        setState(() {});
        _scrollToBottom();
      }

      if (!mounted) return;
      if (_chatState != ChatState.streaming) return;

      final DateTime assistantNow = DateTime.now();
      _historyMessages.add(
        VivoChatMessage(role: 'assistant', content: _streamingContent),
      );

      await ConversationRepository.instance.addMessage(
        _conversationId!,
        ChatMessageEmbedded()
          ..role = 'assistant'
          ..content = _streamingContent
          ..reasoning = _streamingReasoning
          ..timestamp = assistantNow,
      );

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: _streamingContent,
            reasoning: _streamingReasoning,
            timestamp: assistantNow,
          ));
          _chatState = ChatState.idle;
          _streamingContent = '';
          _streamingReasoning = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _chatState = ChatState.error; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            action: SnackBarAction(label: '重试', onPressed: _sendMessage),
          ),
        );
      }
    }
  }

  void _stopGeneration() {
    _streamService.cancel();
    final String partial = _streamingContent;
    if (partial.isNotEmpty) {
      _historyMessages.add(
        VivoChatMessage(role: 'assistant', content: partial),
      );
      final DateTime now = DateTime.now();
      ConversationRepository.instance.addMessage(
        _conversationId!,
        ChatMessageEmbedded()
          ..role = 'assistant'
          ..content = partial
          ..reasoning = _streamingReasoning
          ..timestamp = now,
      );
      _messages.add(ChatMessage(
        role: 'assistant',
        content: partial,
        reasoning: _streamingReasoning,
        timestamp: now,
      ));
    }
    setState(() {
      _chatState = ChatState.idle;
      _streamingContent = '';
      _streamingReasoning = null;
    });
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
    if (full.length <= 13) return full; // system + 6 rounds = 13 max
    return <VivoChatMessage>[
      full.first, // system prompt
      ...full.sublist(full.length - 12), // last 6 rounds
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
        content: Text('正在编译 LaTeX...'),
        duration: Duration(seconds: 1),
      ),
    );

    final LatexCompiler compiler = LatexCompiler();
    final LatexCompileResult result = await compiler.compile(content);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result.success) {
      await compiler.openPdf(result.pdfPath!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF 编译完成'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('编译失败: ${result.error}'),
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
          child: _messages.isEmpty && _chatState == ChatState.idle
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
      itemCount: _messages.length + (_chatState == ChatState.streaming ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == _messages.length) {
          return _buildStreamingBubble();
        }
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildStreamingBubble() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (_streamingContent.isEmpty) {
      return _buildTypingIndicator();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 16, color: cs.primary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildMarkdownContent(_streamingContent),
                  const SizedBox(height: 2),
                  _StreamingCursor(color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
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
        _chatState != ChatState.streaming;
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
    // 保护代码块，避免 $ 被误识别为数学公式
    final List<String> codeBlocks = <String>[];
    String processed = text.replaceAllMapped(
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

    // Two-pass: first split by $$...$$ (display math), then split text segments by $...$ (inline math)
    final List<Widget> blocks = <Widget>[];
    final RegExp displayMathRegex = RegExp(r'\$\$([\s\S]*?)\$\$');

    int lastEnd = 0;
    for (final RegExpMatch match in displayMathRegex.allMatches(processed)) {
      if (match.start > lastEnd) {
        final String textBefore = processed.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          blocks.addAll(_buildInlineContent(textBefore, codeBlocks, inlineCodes));
        }
      }

      final String latex = (match.group(1) ?? '').trim();
      if (latex.isNotEmpty) {
        try {
          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  latex,
                  mathStyle: MathStyle.display,
                  textStyle: const TextStyle(fontSize: 15),
                ),
              ),
            ),
          );
        } catch (_) {
          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(latex, style: const TextStyle(fontFamily: 'monospace')),
            ),
          );
        }
      }
      lastEnd = match.end;
    }

    if (lastEnd < processed.length) {
      final String remaining = processed.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        blocks.addAll(_buildInlineContent(remaining, codeBlocks, inlineCodes));
      }
    }

    if (blocks.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.55,
          color: Color(0xFF333333),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  List<Widget> _buildInlineContent(String text, List<String> codeBlocks, List<String> inlineCodes) {
    final List<Widget> widgets = <Widget>[];
    final RegExp inlineMathRegex = RegExp(r'\$([^\$\n]+)\$');

    int lastEnd = 0;
    for (final RegExpMatch match in inlineMathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        final String textBefore = text.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          widgets.add(_mdWidget(_restorePlaceholders(textBefore, codeBlocks, inlineCodes)));
        }
      }

      final String latex = (match.group(1) ?? '').trim();
      if (latex.isNotEmpty) {
        try {
          widgets.add(
            Math.tex(
              latex,
              mathStyle: MathStyle.text,
              textStyle: const TextStyle(fontSize: 15),
            ),
          );
        } catch (_) {
          widgets.add(
            Text(latex, style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
          );
        }
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final String textAfter = text.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.add(_mdWidget(_restorePlaceholders(textAfter, codeBlocks, inlineCodes)));
      }
    }

    if (widgets.isEmpty && text.isNotEmpty) {
      widgets.add(_mdWidget(_restorePlaceholders(text, codeBlocks, inlineCodes)));
    }

    return <Widget>[
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: widgets,
      ),
    ];
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
      p: TextStyle(fontSize: 15, height: 1.55, color: cs.onSurface),
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
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      h3: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
    );
  }

  Widget _buildInputBar() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool streaming = _chatState == ChatState.streaming;
    final bool hasText = _inputController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  readOnly: streaming,
                  style: TextStyle(color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: '输入数学问题...',
                    hintStyle: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.4)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (streaming)
              GestureDetector(
                onTap: _stopGeneration,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.stop_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: hasText ? () => _sendMessage() : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasText
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: hasText
                        ? cs.onPrimary
                        : cs.onSurface.withValues(alpha: 0.3),
                    size: 20,
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

class _StreamingCursor extends StatefulWidget {
  final Color color;
  const _StreamingCursor({this.color = const Color(0xFF3F51B5)});

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _controller.value,
          child: child,
        );
      },
      child: Container(
        width: 2,
        height: 18,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
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
