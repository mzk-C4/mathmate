import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelService extends ChangeNotifier {
  static final ModelService instance = ModelService._();
  ModelService._();

  static const List<Map<String, String>> availableModels = <Map<String, String>>[
    <String, String>{'id': 'qwen-plus', 'name': 'Qwen Plus'},
    <String, String>{'id': 'qwen-turbo', 'name': 'Qwen Turbo'},
    <String, String>{'id': 'qwen-max', 'name': 'Qwen Max'},
    <String, String>{'id': 'qwen3.6-flash-2026-04-16', 'name': 'Qwen 3.6 Flash'},
    <String, String>{'id': 'deepseek-v4-flash', 'name': 'DeepSeek V4 Flash'},
  ];

  String _currentModelId = 'qwen-plus';
  String get currentModelId => _currentModelId;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _currentModelId = prefs.getString('model_id') ?? 'qwen-plus';
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
