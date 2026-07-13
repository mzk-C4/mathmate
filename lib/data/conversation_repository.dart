import 'package:hive_flutter/hive_flutter.dart';
import 'package:mathmate/data/hive_conversation_models.dart';

const String _kConversationBoxName = 'math_conversation';

class ConversationRepository {
  ConversationRepository._();
  static final ConversationRepository instance = ConversationRepository._();

  Box<Conversation>? _box;

  bool get isReady => _box != null && _box!.isOpen;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(ChatMessageEmbeddedAdapter());
    }

    _box = await Hive.openBox<Conversation>(_kConversationBoxName);
  }

  Future<Conversation> createConversation(String title) async {
    await init();
    final Conversation conversation = Conversation.create(
      title: title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Hive int key 范围 0-0xFFFFFFFF，不能用毫秒时间戳（超范围导致 HiveError）
    conversation.id = 0; // 临时值（满足 Hive 序列化）
    final int hiveKey = await _box!.add(conversation); // Hive 自动递增 key（保证 < 0xFFFFFFFF）
    conversation.id = hiveKey;
    await _box!.put(hiveKey, conversation); // 更新 id 到持久化对象
    return conversation;
  }

  Future<void> addMessage(
    int conversationId,
    ChatMessageEmbedded message,
  ) async {
    await init();
    final Conversation? conversation = _box!.get(conversationId);
    if (conversation == null) return;

    conversation.messages = [...conversation.messages, message];
    conversation.updatedAt = message.timestamp;
    await conversation.save();
  }

  Future<void> updateTitle(int conversationId, String title) async {
    await init();
    final Conversation? conversation = _box!.get(conversationId);
    if (conversation == null) return;

    conversation.title = title;
    await conversation.save();
  }

  Stream<List<Conversation>> watchConversations() async* {
    await init();
    yield _box!.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await for (final _ in _box!.watch()) {
      yield _box!.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  Future<Conversation?> getConversation(int id) async {
    await init();
    return _box!.get(id);
  }

  Future<void> replaceMessages(
    int conversationId,
    List<ChatMessageEmbedded> messages,
  ) async {
    await init();
    final Conversation? conversation = _box!.get(conversationId);
    if (conversation == null) return;

    conversation.messages = messages;
    conversation.updatedAt = DateTime.now();
    await conversation.save();
  }

  Future<void> deleteConversation(int id) async {
    await init();
    await _box!.delete(id);
  }
}