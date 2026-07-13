import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mathmate/wrong_book/models/wrong_question.dart';

class WrongQuestionRepository {
  WrongQuestionRepository._();
  static final WrongQuestionRepository instance = WrongQuestionRepository._();

  static const String _boxName = 'wrong_questions_v1';
  Box<String>? _box;
  final Map<String, WrongQuestion> _cache = <String, WrongQuestion>{};

  Future<void> init() async {
    if (_box != null) return;
    if (!kIsWeb) {
      await Hive.initFlutter();
      _box = await Hive.openBox<String>(_boxName);
      for (final dynamic key in _box!.keys) {
        try {
          final String? raw = _box!.get(key);
          if (raw != null) {
            final WrongQuestion item = WrongQuestion.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            );
            _cache[item.id] = item;
          }
        } catch (_) {}
      }
    }
  }

  List<WrongQuestion> all({bool includeMastered = false}) =>
      _cache.values
          .where((WrongQuestion item) => includeMastered || !item.mastered)
          .toList()
        ..sort(
          (WrongQuestion a, WrongQuestion b) =>
              b.recordedAt.compareTo(a.recordedAt),
        );

  Future<int> importReport(Map<String, dynamic> report) async {
    final List<dynamic> raw =
        report['wrong_questions'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic value in raw) {
      if (value is! Map) continue;
      final WrongQuestion incoming = WrongQuestion.fromReport(
        Map<String, dynamic>.from(value),
      );
      final WrongQuestion stored =
          _cache[incoming.id]?.recordAgain(incoming) ?? incoming;
      _cache[stored.id] = stored;
      await _box?.put(stored.id, stored.encode());
    }
    return raw.length;
  }

  Future<void> setMastered(String id, bool mastered) async {
    final WrongQuestion? item = _cache[id];
    if (item == null) return;
    final WrongQuestion updated = item.copyWith(mastered: mastered);
    _cache[id] = updated;
    await _box?.put(id, updated.encode());
  }
}
