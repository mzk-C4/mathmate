import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GeogebraCommandSearchService {
  GeogebraCommandSearchService._();

  static final GeogebraCommandSearchService instance =
      GeogebraCommandSearchService._();

  Future<Map<String, dynamic>>? _index;

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 8,
  }) async {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <Map<String, dynamic>>[];

    final Map<String, dynamic> index = await (_index ??= _loadIndex());
    final List<String> terms = normalized
        .split(RegExp(r'\s+'))
        .where((String term) => term.isNotEmpty)
        .toList(growable: false);
    final List<({int score, Map<String, dynamic> value})> matches = [];

    for (final MapEntry<String, dynamic> entry in index.entries) {
      final String key = entry.key.toLowerCase();
      int score = 0;
      for (final String term in terms) {
        final int termScore = _score(key, term);
        score = score > termScore ? score : termScore;
      }
      if (score == 0 || entry.value is! Map) continue;
      matches.add((
        score: score,
        value: Map<String, dynamic>.from(entry.value as Map),
      ));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches
        .take(limit)
        .map((match) => match.value)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _loadIndex() async {
    final String source = await rootBundle.loadString(
      'assets/geogebra/commands_index.json',
    );
    return compute(_decodeCommandIndex, source);
  }

  static int _score(String command, String query) {
    if (command == query) return 1000;
    if (command.startsWith(query)) return 700 - (command.length - query.length);
    if (command.contains(query)) return 500 - command.indexOf(query);

    int queryIndex = 0;
    int gaps = 0;
    int previousMatch = -1;
    for (int i = 0; i < command.length && queryIndex < query.length; i++) {
      if (command[i] != query[queryIndex]) continue;
      if (previousMatch >= 0) gaps += i - previousMatch - 1;
      previousMatch = i;
      queryIndex++;
    }
    return queryIndex == query.length ? 200 - gaps.clamp(0, 199) : 0;
  }
}

Map<String, dynamic> _decodeCommandIndex(String source) {
  return Map<String, dynamic>.from(jsonDecode(source) as Map);
}
