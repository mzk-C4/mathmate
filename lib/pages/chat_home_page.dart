import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mathmate/chat_page.dart';
import 'package:mathmate/data/conversation_models.dart';
import 'package:mathmate/data/conversation_repository.dart';

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int? _currentConversationId;
  List<Conversation> _conversations = <Conversation>[];
  StreamSubscription<List<Conversation>>? _conversationSub;

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
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _loadConversation(int id) {
    setState(() {
      _currentConversationId = id;
    });
    Navigator.of(context).pop();
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
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          '蓝心数学助手',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: Colors.grey.shade200, height: 0.5),
        ),
      ),
      drawer: _buildDrawer(),
      body: ChatPage(
        conversationId: _currentConversationId,
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildDrawerHeader(),
            const Divider(height: 1),
            Expanded(child: _buildConversationList()),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 24,
              color: Color(0xFF3F51B5),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '蓝心数学助手',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '你的专属数学辅导老师',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _newConversation,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新对话'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3F51B5),
                side: const BorderSide(color: Color(0xFF3F51B5)),
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

  Widget _buildConversationList() {
    if (_conversations.isEmpty) {
      return const Center(
        child: Text(
          '暂无对话记录',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _conversations.length,
      itemBuilder: (BuildContext context, int index) {
        final Conversation conversation = _conversations[index];
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
            selectedTileColor:
                const Color(0xFF3F51B5).withValues(alpha: 0.08),
            title: Text(
              conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              _formatTime(conversation.updatedAt),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            trailing: isActive
                ? const Icon(Icons.chat_bubble, size: 16,
                    color: Color(0xFF3F51B5))
                : null,
            onTap: () => _loadConversation(conversation.id),
          ),
        );
      },
    );
  }
}
