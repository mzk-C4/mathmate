import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/data/conversation_models.dart';
import 'package:mathmate/data/conversation_repository.dart';
import 'package:mathmate/services/latex_compiler.dart';
import 'package:mathmate/services/vivo_chat_service.dart';

class ChatPage extends StatefulWidget {
  final int? conversationId;

  const ChatPage({super.key, this.conversationId});

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
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: content));
      _isLoading = true;
    });
    _scrollToBottom();

    _historyMessages.add(VivoChatMessage(role: 'user', content: content));

    final String title = content.length > 20
        ? '${content.substring(0, 20)}...'
        : content;

    // auto-create conversation on first message
    if (_conversationId == null) {
      final Conversation conversation =
          await ConversationRepository.instance.createConversation(title);
      _conversationId = conversation.id;
    } else if (!_titleSet) {
      _titleSet = true;
      await ConversationRepository.instance.updateTitle(
        _conversationId!,
        title,
      );
    } else {
      _titleSet = true; // mark as set so we don't update again
    }

    final DateTime now = DateTime.now();
    await ConversationRepository.instance.addMessage(
      _conversationId!,
      ChatMessageEmbedded()
        ..role = 'user'
        ..content = content
        ..timestamp = now,
    );

    // 只保留 system prompt + 最近 6 轮对话，减少请求体加速
    final List<VivoChatMessage> trimmedHistory = _trimHistory(_historyMessages);

    try {
      final VivoChatResponse response =
          await _chatService.sendMessage(trimmedHistory);
      _historyMessages.add(
        VivoChatMessage(role: 'assistant', content: response.content),
      );

      await ConversationRepository.instance.addMessage(
        _conversationId!,
        ChatMessageEmbedded()
          ..role = 'assistant'
          ..content = response.content
          ..reasoning = response.reasoning
          ..timestamp = DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: response.content,
            reasoning: response.reasoning,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            action: SnackBarAction(label: '重试', onPressed: _sendMessage),
          ),
        );
      }
    }
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
          child: _messages.isEmpty && !_isLoading
              ? _buildWelcomeScreen()
              : _buildMessageList(),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildWelcomeScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 48),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 36,
              color: Color(0xFF3F51B5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '你好！我是蓝心数学助手',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '可以问我任何数学问题，我会一步步帮你解答',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          ..._suggestions.map(_buildSuggestionCard),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(String question) {
    return GestureDetector(
      onTap: () => _sendMessage(text: question),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.help_outline, size: 18, color: Color(0xFF3F51B5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                question,
                style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TypingDot(delayMs: 0),
            SizedBox(width: 4),
            _TypingDot(delayMs: 200),
            SizedBox(width: 4),
            _TypingDot(delayMs: 400),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final bool isUser = message.role == 'user';
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
              if (!isUser) const SizedBox(width: 4),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.82,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF3F51B5)
                        : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: isUser
                            ? const Color(0xFF3F51B5).withValues(alpha: 0.15)
                            : const Color(0x0A000000),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isUser
                      ? Text(
                          message.content,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.5,
                          ),
                        )
                      : _buildMarkdownContent(message.content),
                ),
              ),
              if (isUser) const SizedBox(width: 4),
            ],
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => _copyMessage(message.content),
                    child: const Icon(
                      Icons.content_copy,
                      size: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _compileLatex(message.content),
                    child: const Icon(
                      Icons.picture_as_pdf,
                      size: 14,
                      color: Colors.grey,
                    ),
                  ),
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

    final List<Widget> blocks = <Widget>[];
    final RegExp mathRegex = RegExp(r'\$\$(.+?)\$\$|\$(.+?)\$');
    final Iterable<RegExpMatch> matches = mathRegex.allMatches(processed);

    int lastEnd = 0;
    for (final RegExpMatch match in matches) {
      if (match.start > lastEnd) {
        final String plainText = processed.substring(lastEnd, match.start);
        if (plainText.trim().isNotEmpty) {
          blocks.add(_mdWidget(_restorePlaceholders(plainText, codeBlocks, inlineCodes)));
        }
      }

      final String? displayMath = match.group(1);
      final String? inlineMath = match.group(2);
      final String mathSource = (displayMath ?? inlineMath ?? '').trim();
      if (mathSource.isNotEmpty) {
        try {
          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Math.tex(
                mathSource,
                mathStyle: displayMath != null
                    ? MathStyle.display
                    : MathStyle.text,
                textStyle: const TextStyle(fontSize: 15),
              ),
            ),
          );
        } catch (_) {
          blocks.add(
            Text(mathSource, style: const TextStyle(fontFamily: 'monospace')),
          );
        }
      }
      lastEnd = match.end;
    }

    if (lastEnd < processed.length) {
      final String remaining = processed.substring(lastEnd);
      if (remaining.trim().isNotEmpty) {
        blocks.add(_mdWidget(_restorePlaceholders(remaining, codeBlocks, inlineCodes)));
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
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(fontSize: 15, height: 1.55, color: Color(0xFF333333)),
      code: const TextStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        backgroundColor: Color(0xFFF5F5F5),
      ),
      codeblockDecoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      h2: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A1A),
      ),
      h3: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A1A),
      ),
      blockquoteDecoration: const BoxDecoration(
        color: Color(0xFFF5F7FF),
        border: Border(left: BorderSide(color: Color(0xFF3F51B5), width: 3)),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '输入数学问题...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendMessage(),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isLoading
                      ? Colors.grey.shade300
                      : const Color(0xFF3F51B5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: _isLoading ? Colors.grey : Colors.white,
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
  const _TypingDot({required this.delayMs});

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
        decoration: const BoxDecoration(
          color: Color(0xFF3F51B5),
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
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: Color(0xFF9FA8DA), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.psychology_outlined,
                    size: 14, color: Color(0xFF5C6BC0)),
                const SizedBox(width: 6),
                const Text(
                  '思考过程',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5C6BC0),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: const Color(0xFF5C6BC0),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                widget.reasoning,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF555555),
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

  ChatMessage({
    required this.role,
    required this.content,
    this.reasoning,
  });
}
