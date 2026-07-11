import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelService extends ChangeNotifier {
  static final ModelService instance = ModelService._();
  ModelService._();

  static const List<Map<String, String>> availableModels = <Map<String, String>>[
    <String, String>{'id': 'deepseek-chat', 'name': 'DeepSeek Chat'},
    <String, String>{'id': 'deepseek-reasoner', 'name': 'DeepSeek Reasoner'},
    <String, String>{'id': 'qwen3.6-flash-2026-04-16', 'name': 'Qwen 3.6 Flash'},
  ];

  String _currentModelId = 'deepseek-chat';
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
        (saved != null && validIds.contains(saved)) ? saved : 'deepseek-chat';
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
