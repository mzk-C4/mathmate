import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class GeochatSessionSnapshot {
  const GeochatSessionSnapshot({
    required this.canvasXml,
    required this.messages,
    required this.updatedAt,
  });

  final String canvasXml;
  final List<Map<String, dynamic>> messages;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'canvasXml': canvasXml,
    'messages': messages,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory GeochatSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawMessages =
        json['messages'] as List<dynamic>? ?? const <dynamic>[];
    return GeochatSessionSnapshot(
      canvasXml: json['canvasXml'] as String? ?? '',
      messages: rawMessages
          .whereType<Map>()
          .map((Map value) => Map<String, dynamic>.from(value))
          .toList(growable: false),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime(0),
    );
  }
}

class GeochatSessionStore {
  GeochatSessionStore({Directory? baseDirectory})
    : _baseDirectory = baseDirectory;

  final Directory? _baseDirectory;

  Future<GeochatSessionSnapshot?> load() async {
    final File file = await _sessionFile();
    if (!await file.exists()) return null;
    try {
      final Object? value = jsonDecode(await file.readAsString());
      if (value is! Map) return null;
      return GeochatSessionSnapshot.fromJson(Map<String, dynamic>.from(value));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(GeochatSessionSnapshot snapshot) async {
    final File file = await _sessionFile();
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    final File file = await _sessionFile();
    if (await file.exists()) await file.delete();
  }

  Future<File> _sessionFile() async {
    final Directory root =
        _baseDirectory ?? await getApplicationDocumentsDirectory();
    return File('${root.path}/geochat/last_session.json');
  }
}
