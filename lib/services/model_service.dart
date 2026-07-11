import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelService extends ChangeNotifier {
  static final ModelService instance = ModelService._();
  ModelService._();

  static const List<Map<String, String>> availableModels = <Map<String, String>>[
    // 火山 Ark（Doubao + DeepSeek-V4 + GLM）
    <String, String>{'id': 'deepseek-v4-flash', 'name': 'DeepSeek V4 Flash'},
    <String, String>{'id': 'deepseek-v4-pro', 'name': 'DeepSeek V4 Pro'},
    <String, String>{'id': 'glm-5-2-260617', 'name': 'GLM 5.2'},
    <String, String>{'id': 'doubao-seed-2-1-pro-260628', 'name': 'Doubao Seed 2.1 Pro'},
    <String, String>{'id': 'doubao-seed-2-1-turbo-260628', 'name': 'Doubao Seed 2.1 Turbo'},
    <String, String>{'id': 'doubao-seed-2-0-lite-260428', 'name': 'Doubao Seed 2.0 Lite'},
    <String, String>{'id': 'doubao-seed-1-8-251228', 'name': 'Doubao Seed 1.8'},
    // 阿里 DashScope
    <String, String>{'id': 'qwen3.7-plus', 'name': 'Qwen 3.7 Plus'},
    <String, String>{'id': 'qwen3.7-max', 'name': 'Qwen 3.7 Max'},
    <String, String>{'id': 'qwen3.6-max-preview', 'name': 'Qwen 3.6 Max Preview'},
    <String, String>{'id': 'qwen3.6-flash-2026-04-16', 'name': 'Qwen 3.6 Flash'},
  ];

  String _currentModelId = 'deepseek-v4-flash';
  String get currentModelId => _currentModelId;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('model_id');
    // 旧的 vivo/qwen model id 不再有效，回退默认（deepseek-chat）
    final Set<String> validIds =
        availableModels.map((Map<String, String> m) => m['id']!).toSet();
    _currentModelId =
        (saved != null && validIds.contains(saved)) ? saved : 'deepseek-v4-flash';
    _initialized = true;
  }

  Future<void> setModel(String modelId) async {
    if (_currentModelId == modelId) return;
    _currentModelId = modelId;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('model_id', modelId);
    notifyListeners();
  }
}
