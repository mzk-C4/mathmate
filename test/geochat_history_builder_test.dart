import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geochat_history_builder.dart';

void main() {
  test(
    'keeps the latest user request and removes only streaming placeholders',
    () {
      const GeochatHistoryBuilder builder = GeochatHistoryBuilder();
      final List<Map<String, String>> history = builder
          .build(const <GeochatHistoryEntry>[
            GeochatHistoryEntry(role: 'user', content: '上一条问题'),
            GeochatHistoryEntry(role: 'assistant', content: '上一条回答'),
            GeochatHistoryEntry(role: 'user', content: '画一个正六边形'),
            GeochatHistoryEntry(
              role: 'assistant',
              content: '',
              isStreaming: true,
            ),
          ]);

      expect(history, hasLength(3));
      expect(history.last, <String, String>{
        'role': 'user',
        'content': '画一个正六边形',
      });
    },
  );
}
