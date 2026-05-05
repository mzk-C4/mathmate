import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mathmate/data/history_models.dart';
import 'package:mathmate/visualization/safe_json_parser.dart';

const String _kIsFirstLaunch = 'is_first_launch';
const String _kGradeLevel = 'grade_level';
const String _kTutorialCompleted = 'tutorial_completed';

class HistoryRepository {
  HistoryRepository._();

  static final HistoryRepository instance = HistoryRepository._();

  Isar? _isar;

  bool get isReady => _isar != null;

  Future<void> init() async {
    if (_isar != null) {
      return;
    }

    final Directory dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      <CollectionSchema>[MathHistorySchema],
      directory: dir.path,
      name: 'mathmate_history',
    );
  }

  Future<void> saveHistory({
    required File sourceImage,
    required String ocrContent,
    required String solutionMarkdown,
    required String latexResult,
    Map<String, dynamic>? sceneMap,
  }) async {
    await init();
    final Isar isar = _isar!;

    final File persistedImage = await _persistImage(sourceImage);
    final SafeJsonParser parser = const SafeJsonParser();

    // AI generated title
    final String title = await _generateTitle(ocrContent);

    final MathHistory entity = MathHistory()
      ..timestamp = DateTime.now()
      ..originalImagePath = persistedImage.path
      ..ocrContent = ocrContent
      ..solutionMarkdown = solutionMarkdown
      ..latexResult = latexResult
      ..title = title;

    if (sceneMap != null) {
      entity.geometryScene = GeometrySceneEmbedded.fromMap(sceneMap, parser);
    }

    await isar.writeTxn(() async {
      await isar.mathHistorys.put(entity);
    });
  }

  Stream<List<MathHistory>> watchHistories() async* {
    await init();
    final Isar isar = _isar!;

    yield* isar.mathHistorys
        .where()
        .sortByTimestampDesc()
        .watch(fireImmediately: true);
  }

  Future<void> deleteHistory(Id id) async {
    await init();
    final Isar isar = _isar!;

    final MathHistory? history = await isar.mathHistorys.get(id);
    if (history != null) {
      final File image = File(history.originalImagePath);
      if (await image.exists()) {
        try {
          await image.delete();
        } catch (e) {
          debugPrint('delete image failed: $e');
        }
      }
    }

    await isar.writeTxn(() async {
      await isar.mathHistorys.delete(id);
    });
  }

  /// Use AI to generate a short title for the history entry
  Future<String> _generateTitle(String ocrContent) async {
    const String apiKeyEnv = 'VIVO_API_KEY';
    const String modelEnv = 'VIVO_MODEL_ID';
    const String baseUrlEnv = 'VIVO_BASE_URL';
    const String defaultModel = 'qwen-plus';
    const String defaultBaseUrl =
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';

    try {
      await dotenv.load(fileName: '.env');
      final String apiKey = (dotenv.env[apiKeyEnv] ?? '').trim();
      if (apiKey.isEmpty) return '数学问题';

      final String modelId = (dotenv.env[modelEnv] ?? defaultModel).trim();
      final String baseUrl =
          (dotenv.env[baseUrlEnv] ?? defaultBaseUrl).trim();

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

  Future<File> _persistImage(File sourceImage) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final Directory imageDir = Directory(path.join(dir.path, 'history_images'));
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    final String ext = path.extension(sourceImage.path).isEmpty
        ? '.jpg'
        : path.extension(sourceImage.path);
    final String filename =
        'history_${DateTime.now().millisecondsSinceEpoch}$ext';
    final String targetPath = path.join(imageDir.path, filename);

    final File copied = await sourceImage.copy(targetPath);

    try {
      if (await sourceImage.exists()) {
        await sourceImage.delete();
      }
    } catch (e) {
      debugPrint('cleanup temp image failed: $e');
    }

    return copied;
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

  // 新手引导
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
