import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mathmate/chat_page.dart';
import 'package:mathmate/data/hive_conversation_models.dart';
import 'package:mathmate/data/conversation_repository.dart';
import 'package:mathmate/responsive/breakpoints.dart';
import 'package:mathmate/services/model_service.dart';

class ChatHomePage extends StatefulWidget {
  final String? initialQuery;
  const ChatHomePage({super.key, this.initialQuery});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int? _currentConversationId;
  List<Conversation> _conversations = <Conversation>[];
  StreamSubscription<List<Conversation>>? _conversationSub;
  String _currentModel = 'deepseek-chat';
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _conversationSub = ConversationRepository.instance
        .watchConversations()
        .listen((List<Conversation> list) {
      if (mounted) {
        setState(() {
          _conversations = list;
        });
      }
    });
    _initModel();
  }

  Future<void> _initModel() async {
    await ModelService.instance.init();
    if (mounted) {
      setState(() {
        _currentModel = ModelService.instance.currentModelId;
      });
    }
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    super.dispose();
  }

  Future<void> _newConversation() async {
    setState(() {
      _currentConversationId = null;
    });
    // 窄屏需要关闭 Drawer；桌面端面板常驻，无需 pop。
    if (mounted && !context.isDesktop) {
      Navigator.of(context).pop();
    }
  }

  void _loadConversation(int id) {
    setState(() {
      _currentConversationId = id;
    });
    // 窄屏需要关闭 Drawer；桌面端面板常驻，无需 pop。
    if (!context.isDesktop) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _deleteConversation(int id) async {
    await ConversationRepository.instance.deleteConversation(id);
    if (_currentConversationId == id) {
      setState(() {
        _currentConversationId = null;
      });
    }
  }

  String _formatTime(DateTime time) {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isDesktop = context.isDesktop;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surface,
      appBar: AppBar(
        // 桌面端无 Drawer，leading 用返回按钮；窄屏用菜单按钮打开对话 Drawer。
        leading: isDesktop
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: cs.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              )
            : IconButton(
                icon: Icon(Icons.menu, color: cs.onSurface),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        title: const Text(
          'MathMate 助手',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: Icon(Icons.smart_toy_outlined, color: cs.onSurface),
            tooltip: '选择模型',
            onSelected: (String id) async {
              await ModelService.instance.setModel(id);
              if (mounted) {
                setState(() => _currentModel = id);
              }
            },
            itemBuilder: (BuildContext context) {
              return ModelService.availableModels.map((m) {
                final bool selected = m['id'] == _currentModel;
                return PopupMenuItem<String>(
                  value: m['id'],
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(m['name']!)),
                      if (selected) Icon(Icons.check, size: 16, color: cs.primary),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: cs.outlineVariant, height: 0.5),
        ),
      ),
      // 窄屏：对话列表放 Drawer；桌面：左侧常驻面板 + 右侧聊天区。
      drawer: isDesktop ? null : _buildDrawer(),
      body: isDesktop
          ? Row(
              children: <Widget>[
                SizedBox(width: 320, child: _buildConversationPanel()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildChatArea()),
              ],
            )
          : _buildChatArea(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(child: _buildConversationPanel());
  }

  /// 对话列表面板：窄屏作为 Drawer 内容，桌面作为左侧常驻栏复用。
  Widget _buildConversationPanel() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildDrawerHeader(),
          _buildSearchBox(),
          const Divider(height: 1),
          Expanded(child: _buildConversationList()),
        ],
      ),
    );
  }

  /// 聊天主区域，桌面与窄屏共用。
  Widget _buildChatArea() {
    return ChatPage(
      conversationId: _currentConversationId,
      initialQuery: widget.initialQuery,
      onConversationCreated: (int id) {
        _currentConversationId = id;
      },
    );
  }

  Widget _buildDrawerHeader() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 24,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'MathMate 助手',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '你的专属数学辅导老师',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _newConversation,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新对话'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按关键词过滤会话（NextChat 风格会话搜索）
  List<Conversation> get _filteredConversations {
    if (_searchKeyword.isEmpty) return _conversations;
    final String kw = _searchKeyword.toLowerCase();
    return _conversations
        .where((Conversation c) => c.title.toLowerCase().contains(kw))
        .toList();
  }

  Widget _buildSearchBox() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索对话...',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          suffixIcon: _searchKeyword.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _searchKeyword = ''),
                )
              : null,
        ),
        onChanged: (String v) => setState(() => _searchKeyword = v),
      ),
    );
  }

  /// 长按会话 → 重命名对话框（NextChat 风格会话重命名）
  Future<void> _showRenameDialog(Conversation conversation) async {
    final TextEditingController controller =
        TextEditingController(text: conversation.title);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != conversation.title) {
      await ConversationRepository.instance
          .updateTitle(conversation.id, result);
    }
  }

  Widget _buildConversationList() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Conversation> conversations = _filteredConversations;
    if (conversations.isEmpty) {
      return Center(
        child: Text(
          _searchKeyword.isNotEmpty ? '未找到匹配对话' : '暂无对话记录',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.4),
            fontSize: 13,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: conversations.length,
      itemBuilder: (BuildContext context, int index) {
        final Conversation conversation = conversations[index];
        final bool isActive = conversation.id == _currentConversationId;

        return Dismissible(
          key: Key('conv_${conversation.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red.shade50,
            child: const Icon(Icons.delete, color: Colors.red),
          ),
          confirmDismiss: (DismissDirection direction) async {
            await _deleteConversation(conversation.id);
            return true;
          },
          child: ListTile(
            selected: isActive,
            selectedTileColor: cs.primary.withValues(alpha: 0.08),
            title: Text(
              conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: cs.onSurface,
              ),
            ),
            subtitle: Text(
              _formatTime(conversation.updatedAt),
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
            trailing: isActive
                ? Icon(Icons.chat_bubble, size: 16, color: cs.primary)
                : null,
            onTap: () => _loadConversation(conversation.id),
            onLongPress: () => _showRenameDialog(conversation),
          ),
        );
      },
    );
  }
}
