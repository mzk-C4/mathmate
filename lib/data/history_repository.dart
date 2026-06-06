import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/services/provider_config_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mathmate/data/hive_models.dart';

const String _kIsFirstLaunch = 'is_first_launch';
const String _kGradeLevel = 'grade_level';
const String _kTutorialCompleted = 'tutorial_completed';
const String _kHistoryBoxName = 'math_history';

class HistoryRepository {
  HistoryRepository._();

  static final HistoryRepository instance = HistoryRepository._();

  Box<MathHistory>? _box;

  bool get isReady => _box != null && _box!.isOpen;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) {
      return;
    }

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(MathHistoryAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(GeometrySceneEmbeddedAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ViewportEmbeddedAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(GeometryElementEmbeddedAdapter());
    }

    _box = await Hive.openBox<MathHistory>(_kHistoryBoxName);
  }

  Future<void> saveHistory({
    required XFile sourceImage,
    required String ocrContent,
    required String solutionMarkdown,
    required String latexResult,
    Map<String, dynamic>? sceneMap,
  }) async {
    await init();

    final String imagePath = await _persistImage(sourceImage);
    final String title = await _generateTitle(ocrContent);

    final MathHistory entity = MathHistory.create(
      timestamp: DateTime.now(),
      originalImagePath: imagePath,
      ocrContent: ocrContent,
      solutionMarkdown: solutionMarkdown,
      latexResult: latexResult,
      title: title,
    );

    if (sceneMap != null) {
      entity.geometryScene = GeometrySceneEmbedded.fromMap(sceneMap, null);
    }

    entity.id = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
    await _box!.put(entity.id, entity);
  }

  Stream<List<MathHistory>> watchHistories() async* {
    await init();
    yield _box!.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    await for (final _ in _box!.watch()) {
      yield _box!.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
  }

  Future<void> deleteHistory(int id) async {
    await init();
    final MathHistory? history = _box!.get(id);
    if (history != null) {
      try {
        final File image = File(history.originalImagePath);
        if (await image.exists()) {
          await image.delete();
        }
      } catch (e) {
        debugPrint('delete image failed: $e');
      }
      await _box!.delete(id);
    }
  }

  Future<String> _generateTitle(String ocrContent) async {
    try {
      final pc = ProviderConfigService.instance;
      final String apiKey = pc.chatApiKey;
      if (apiKey.isEmpty) return '数学问题';

      final String modelId = pc.chatModelId;
      final String baseUrl = pc.chatBaseUrl;

      const String prompt = '请根据以下数学题目内容，总结一个简洁的标题（不超过20个字），概括这道题目的知识点或题型。\n\n题目内容：\n';

      final String fullPrompt = '$prompt$ocrContent\n\n标题：';

      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
      };

      final Map<String, dynamic> body = <String, dynamic>{
        'model': modelId,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': fullPrompt},
        ],
        'temperature': 0.7,
        'max_tokens': 50,
      };

      final http.Response response = await http.post(
        Uri.parse(baseUrl),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String content = data['choices']?[0]?['message']?['content'] ?? '';
        if (content.trim().isNotEmpty) {
          String title = content.trim();
          if (title.startsWith('"') && title.endsWith('"')) {
            title = title.substring(1, title.length - 1);
          }
          if (title.length > 20) {
            title = title.substring(0, 20);
          }
          return title;
        }
      }
    } catch (e) {
      debugPrint('_generateTitle error: $e');
    }
    return '数学问题';
  }

  Future<String> _persistImage(XFile sourceImage) async {
    if (kIsWeb) {
      return sourceImage.path;
    }

    final Directory dir = await getApplicationDocumentsDirectory();
    final Directory imageDir = Directory(path.join(dir.path, 'history_images'));
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    // XFile 没有 copy/exists/delete，转换为 File 操作（仅 native 有效）
    final File source = File(sourceImage.path);
    final String ext = path.extension(sourceImage.path).isEmpty
        ? '.jpg'
        : path.extension(sourceImage.path);
    final String filename =
        'history_${DateTime.now().millisecondsSinceEpoch}$ext';
    final String targetPath = path.join(imageDir.path, filename);

    final File copied = await source.copy(targetPath);

    try {
      if (await source.exists()) {
        await source.delete();
      }
    } catch (e) {
      debugPrint('cleanup temp image failed: $e');
    }

    return copied.path;
  }

  Future<bool> isFirstLaunch() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIsFirstLaunch) ?? true;
  }

  Future<void> setFirstLaunchComplete() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsFirstLaunch, false);
  }

  Future<int?> getGradeLevel() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kGradeLevel);
  }

  Future<void> setGradeLevel(int grade) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGradeLevel, grade);
  }

  Future<bool> isTutorialCompleted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTutorialCompleted) ?? false;
  }

  Future<void> setTutorialCompleted() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTutorialCompleted, true);
  }

  Future<void> resetTutorial() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTutorialCompleted);
  }
}