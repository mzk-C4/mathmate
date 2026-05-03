import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseChatMessage {
  final String role;
  final String content;

  SupabaseChatMessage({required this.role, required this.content});

  Map<String, String> toMap() => <String, String>{
        'role': role,
        'content': content,
      };
}

class SupabaseChatResponse {
  final String content;
  final String? reasoning;

  SupabaseChatResponse({required this.content, this.reasoning});
}

class SupabaseChatService {
  static const String _functionName = 'math_solver';

  Future<SupabaseChatResponse> sendMessage({
    required List<SupabaseChatMessage> messages,
    required String provider,
  }) async {
    final SupabaseClient supabase = Supabase.instance.client;

    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInAnonymously();
    }

    final FunctionResponse response = await supabase.functions.invoke(
      _functionName,
      body: <String, dynamic>{
        'provider': provider,
        'messages': messages.map((m) => m.toMap()).toList(),
      },
    );

    final dynamic data = response.data;
    final dynamic message = data['choices']?[0]?['message'];
    final String content = (message?['content'] as String?)?.trim() ?? '';
    final String? reasoning =
        (message?['reasoning_content'] as String?)?.trim();

    return SupabaseChatResponse(content: content, reasoning: reasoning);
  }
}
