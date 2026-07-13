import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geochat_session_store.dart';

void main() {
  late Directory directory;
  late GeochatSessionStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('geochat-session-');
    store = GeochatSessionStore(baseDirectory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('saves, loads and clears the latest session atomically', () async {
    final snapshot = GeochatSessionSnapshot(
      canvasXml: '<geogebra><construction /></geogebra>',
      messages: const <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': '画一个点 A'},
      ],
      updatedAt: DateTime.utc(2026, 7, 13),
    );

    await store.save(snapshot);
    final loaded = await store.load();

    expect(loaded?.canvasXml, snapshot.canvasXml);
    expect(loaded?.messages, snapshot.messages);
    expect(loaded?.updatedAt, snapshot.updatedAt);

    await store.clear();
    expect(await store.load(), isNull);
  });
}
