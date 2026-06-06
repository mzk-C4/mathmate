import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 预设 AI 提供商列表（参考 Gugugaga 的 PRESET_PROVIDERS）
const List<Map<String, String>> kProviderPresets = <Map<String, String>>[
  <String, String>{'id': 'deepseek', 'name': 'DeepSeek', 'baseUrl': 'https://api.deepseek.com/chat/completions'},
  <String, String>{'id': 'qwen', 'name': '通义千问 (Qwen)', 'baseUrl': 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'},
  <String, String>{'id': 'volcengine', 'name': '火山引擎 (豆包)', 'baseUrl': 'https://ark.cn-beijing.volces.com/api/v3/chat/completions'},
  <String, String>{'id': 'openai', 'name': 'OpenAI', 'baseUrl': 'https://api.openai.com/v1/chat/completions'},
  <String, String>{'id': 'anthropic', 'name': 'Anthropic Claude', 'baseUrl': 'https://api.anthropic.com/v1/messages'},
  <String, String>{'id': 'moonshot', 'name': '月之暗面 (Kimi)', 'baseUrl': 'https://api.moonshot.cn/v1/chat/completions'},
  <String, String>{'id': 'zhipu', 'name': '智谱 AI (GLM)', 'baseUrl': 'https://open.bigmodel.cn/api/paas/v4/chat/completions'},
  <String, String>{'id': 'siliconflow', 'name': '硅基流动', 'baseUrl': 'https://api.siliconflow.cn/v1/chat/completions'},
  <String, String>{'id': 'ollama', 'name': 'Ollama (本地)', 'baseUrl': 'http://localhost:11434/v1/chat/completions'},
  <String, String>{'id': 'custom', 'name': '自定义', 'baseUrl': ''},
];

/// 三个固定用途的 AI 服务槽位
enum ProviderSlot { vision, reasoning, chat }

/// 槽位默认预设 ID
const Map<ProviderSlot, String> kSlotDefaultPreset = <ProviderSlot, String>{
  ProviderSlot.vision: 'volcengine',
  ProviderSlot.reasoning: 'deepseek',
  ProviderSlot.chat: 'qwen',
};

/// 槽位对应的 .env 变量名前缀（用于 fallback）
const Map<ProviderSlot, List<String>> kSlotEnvKeys = <ProviderSlot, List<String>>{
  ProviderSlot.vision: <String>['VOLC_API_KEY', 'VOLC_MODEL_ID', 'VOLC_BASE_URL'],
  ProviderSlot.reasoning: <String>['DEEPSEEK_API_KEY', 'DEEPSEEK_MODEL_ID', 'DEEPSEEK_BASE_URL'],
  ProviderSlot.chat: <String>['VIVO_API_KEY', 'VIVO_MODEL_ID', 'VIVO_BASE_URL'],
};

/// 统一管理三个 AI Provider 槽位的配置。
///
/// 每个槽位存储：providerId（预设标识）、apiKey、modelId、baseUrl。
/// 读取优先级：SharedPreferences → 预设默认值 → .env → 硬编码兜底。
class ProviderConfigService extends ChangeNotifier {
  static final ProviderConfigService instance = ProviderConfigService._();
  ProviderConfigService._();

  bool _initialized = false;
  bool get initialized => _initialized;

  // ---- 内部状态 ----

  // vision slot
  String _visionProviderId = 'volcengine';
  String _visionApiKey = '';
  String _visionModelId = '';
  String _visionBaseUrl = '';
  double _visionTemperature = 1.0;

  // reasoning slot
  String _reasoningProviderId = 'deepseek';
  String _reasoningApiKey = '';
  String _reasoningModelId = '';
  String _reasoningBaseUrl = '';
  double _reasoningTemperature = 1.0;

  // chat slot
  String _chatProviderId = 'qwen';
  String _chatApiKey = '';
  String _chatModelId = '';
  String _chatBaseUrl = '';
  double _chatTemperature = 0.7;

  // ---- Getter ----

  // vision
  String get visionProviderId => _visionProviderId;
  String get visionApiKey => _visionApiKey;
  String get visionModelId => _visionModelId;
  String get volcOcrModelId => _visionModelId; // OCR 共用 vision 模型
  String get visionBaseUrl => _visionBaseUrl;
  double get visionTemperature => _visionTemperature;
  bool get isVisionConfigured => _visionApiKey.isNotEmpty;

  // reasoning
  String get reasoningProviderId => _reasoningProviderId;
  String get reasoningApiKey => _reasoningApiKey;
  String get reasoningModelId => _reasoningModelId;
  String get reasoningBaseUrl => _reasoningBaseUrl;
  double get reasoningTemperature => _reasoningTemperature;
  bool get isReasoningConfigured => _reasoningApiKey.isNotEmpty;

  // chat
  String get chatProviderId => _chatProviderId;
  String get chatApiKey => _chatApiKey;
  String get chatModelId => _chatModelId;
  String get chatBaseUrl => _chatBaseUrl;
  double get chatTemperature => _chatTemperature;
  bool get isChatConfigured => _chatApiKey.isNotEmpty;

  // ---- 初始化 ----

  Future<void> init() async {
    if (_initialized) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    _loadSlot(prefs, ProviderSlot.vision);
    _loadSlot(prefs, ProviderSlot.reasoning);
    _loadSlot(prefs, ProviderSlot.chat);

    _initialized = true;
  }

  void _loadSlot(SharedPreferences prefs, ProviderSlot slot) {
    final String prefix = slot.name; // 'vision', 'reasoning', 'chat'
    final String defaultPresetId = kSlotDefaultPreset[slot]!;
    final List<String> envKeys = kSlotEnvKeys[slot]!;

    // providerId: SP → 默认预设
    final String spProviderId = prefs.getString('pc_${prefix}_provider_id') ?? '';
    final String providerId = spProviderId.isNotEmpty ? spProviderId : defaultPresetId;

    // apiKey: SP → .env → ''
    final String spApiKey = prefs.getString('pc_${prefix}_api_key') ?? '';
    final String apiKey = spApiKey.isNotEmpty
        ? spApiKey
        : (dotenv.isInitialized ? (dotenv.env[envKeys[0]] ?? '') : '').trim();

    // modelId: SP → .env → 硬编码兜底
    final String spModelId = prefs.getString('pc_${prefix}_model_id') ?? '';
    final String modelId = spModelId.isNotEmpty
        ? spModelId
        : _resolveDefaultModel(slot, envKeys[1]);

    // baseUrl: SP → 预设默认 → .env → 硬编码兜底
    final String spBaseUrl = prefs.getString('pc_${prefix}_base_url') ?? '';
    final String baseUrl = spBaseUrl.isNotEmpty
        ? spBaseUrl
        : _resolveBaseUrl(providerId, envKeys[2]);

    // temperature: SP → 默认值（K2=1.0, v1=0.6, 其他=0.7）
    final double spTemp = prefs.getDouble('pc_${prefix}_temperature') ?? -1;
    final double temperature = spTemp >= 0
        ? spTemp
        : _defaultTemperature(slot);

    // 赋值
    _setSlotFields(slot, providerId, apiKey, modelId, baseUrl, temperature);
  }

  double _defaultTemperature(ProviderSlot slot) {
    switch (slot) {
      case ProviderSlot.vision:
        return 1.0;
      case ProviderSlot.reasoning:
        return 1.0;
      case ProviderSlot.chat:
        return 0.7;
    }
  }

  String _resolveDefaultModel(ProviderSlot slot, String envKey) {
    final String envValue = (dotenv.isInitialized ? (dotenv.env[envKey] ?? '') : '').trim();
    if (envValue.isNotEmpty) return envValue;
    // 硬编码兜底
    switch (slot) {
      case ProviderSlot.vision:
        return ''; // 多模态模型需用户指定
      case ProviderSlot.reasoning:
        return 'deepseek-chat';
      case ProviderSlot.chat:
        return 'qwen-plus';
    }
  }

  String _resolveBaseUrl(String providerId, String envKey) {
    // 先查预设
    for (final Map<String, String> preset in kProviderPresets) {
      if (preset['id'] == providerId && (preset['baseUrl'] ?? '').isNotEmpty) {
        return preset['baseUrl']!;
      }
    }
    // 再查 .env
    final String envValue = (dotenv.isInitialized ? (dotenv.env[envKey] ?? '') : '').trim();
    if (envValue.isNotEmpty) return envValue;
    // 硬编码兜底
    return '';
  }

  void _setSlotFields(ProviderSlot slot, String providerId, String apiKey, String modelId, String baseUrl, double temperature) {
    switch (slot) {
      case ProviderSlot.vision:
        _visionProviderId = providerId;
        _visionApiKey = apiKey;
        _visionModelId = modelId;
        _visionBaseUrl = baseUrl;
        _visionTemperature = temperature;
      case ProviderSlot.reasoning:
        _reasoningProviderId = providerId;
        _reasoningApiKey = apiKey;
        _reasoningModelId = modelId;
        _reasoningBaseUrl = baseUrl;
        _reasoningTemperature = temperature;
      case ProviderSlot.chat:
        _chatProviderId = providerId;
        _chatApiKey = apiKey;
        _chatModelId = modelId;
        _chatBaseUrl = baseUrl;
        _chatTemperature = temperature;
    }
  }

  // ---- Setter ----

  Future<void> setVisionProviderId(String value) async => _setSlotValue(ProviderSlot.vision, 'provider_id', value, () => _visionProviderId = value);
  Future<void> setVisionApiKey(String value) async => _setSlotValue(ProviderSlot.vision, 'api_key', value, () => _visionApiKey = value);
  Future<void> setVisionModelId(String value) async => _setSlotValue(ProviderSlot.vision, 'model_id', value, () => _visionModelId = value);
  Future<void> setVisionBaseUrl(String value) async => _setSlotValue(ProviderSlot.vision, 'base_url', value, () => _visionBaseUrl = value);
  Future<void> setVisionTemperature(double value) async => _setSlotDouble(ProviderSlot.vision, 'temperature', value, () => _visionTemperature = value);

  Future<void> setReasoningProviderId(String value) async => _setSlotValue(ProviderSlot.reasoning, 'provider_id', value, () => _reasoningProviderId = value);
  Future<void> setReasoningApiKey(String value) async => _setSlotValue(ProviderSlot.reasoning, 'api_key', value, () => _reasoningApiKey = value);
  Future<void> setReasoningModelId(String value) async => _setSlotValue(ProviderSlot.reasoning, 'model_id', value, () => _reasoningModelId = value);
  Future<void> setReasoningBaseUrl(String value) async => _setSlotValue(ProviderSlot.reasoning, 'base_url', value, () => _reasoningBaseUrl = value);
  Future<void> setReasoningTemperature(double value) async => _setSlotDouble(ProviderSlot.reasoning, 'temperature', value, () => _reasoningTemperature = value);

  Future<void> setChatProviderId(String value) async => _setSlotValue(ProviderSlot.chat, 'provider_id', value, () => _chatProviderId = value);
  Future<void> setChatApiKey(String value) async => _setSlotValue(ProviderSlot.chat, 'api_key', value, () => _chatApiKey = value);
  Future<void> setChatModelId(String value) async => _setSlotValue(ProviderSlot.chat, 'model_id', value, () => _chatModelId = value);
  Future<void> setChatBaseUrl(String value) async => _setSlotValue(ProviderSlot.chat, 'base_url', value, () => _chatBaseUrl = value);
  Future<void> setChatTemperature(double value) async => _setSlotDouble(ProviderSlot.chat, 'temperature', value, () => _chatTemperature = value);

  Future<void> _setSlotValue(ProviderSlot slot, String key, String value, VoidCallback assign) async {
    final String trimmed = value.trim();
    assign();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove('pc_${slot.name}_$key');
    } else {
      await prefs.setString('pc_${slot.name}_$key', trimmed);
    }
    notifyListeners();
  }

  Future<void> _setSlotDouble(ProviderSlot slot, String key, double value, VoidCallback assign) async {
    assign();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pc_${slot.name}_$key', value);
    notifyListeners();
  }

  // ---- Reset ----

  Future<void> resetVision() async => _resetSlot(ProviderSlot.vision);
  Future<void> resetReasoning() async => _resetSlot(ProviderSlot.reasoning);
  Future<void> resetChat() async => _resetSlot(ProviderSlot.chat);

  Future<void> _resetSlot(ProviderSlot slot) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String prefix = 'pc_${slot.name}';
    await prefs.remove('${prefix}_provider_id');
    await prefs.remove('${prefix}_api_key');
    await prefs.remove('${prefix}_model_id');
    await prefs.remove('${prefix}_base_url');
    await prefs.remove('${prefix}_temperature');
    _loadSlot(prefs, slot);
    notifyListeners();
  }

  // ---- 查询预设 baseUrl ----

  /// 根据预设 ID 获取默认 baseUrl，找不到返回空串
  static String baseUrlForPreset(String presetId) {
    for (final Map<String, String> preset in kProviderPresets) {
      if (preset['id'] == presetId) return preset['baseUrl'] ?? '';
    }
    return '';
  }

  // ---- 动态模型获取 ----

  /// 从 API 获取可用模型列表。
  /// [baseUrl] 和 [apiKey] 使用当前的槽位配置。
  static Future<ModelFetchResult> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    // 默认硬编码推荐模型（按关键词匹配，更新至 2026年6月）
    const List<String> kRecommendKeywords = <String>[
      // OpenAI: gpt-5.5, gpt-5.4, gpt-5.2 (2026)
      'gpt-5',
      // Anthropic: Claude Opus 4.8, Sonnet 4.6, Haiku 4.5 (2026)
      'claude-opus', 'claude-sonnet', 'claude-haiku',
      // Google: Gemini 3.5 Flash/Pro, 2.5 Pro/Flash
      'gemini-3.5', 'gemini-3.1', 'gemini-2.5',
      // Qwen: 3.7 Max/Plus, 3.6 Plus, 3.6 Flash, Coder 30B
      'qwen3.7', 'qwen3.6', 'qwen3-coder', 'qwen3-32b', 'qwen-plus', 'qwen-max',
      // DeepSeek: V4 Pro/Flash (2026.04), 旧名 deepseek-chat/reasoner 已弃用
      'deepseek-v4-pro', 'deepseek-v4-flash', 'deepseek-v4',
      // Kimi: K2.6, K2.5, K2-Thinking (2026)
      'kimi-k2',
      // GLM: 5.1, 5 (2026)
      'glm-5',
    ];
    try {
      // 去除 /chat/completions 或 /completions 后缀，再拼 /models
      final String clean = baseUrl
          .replaceAll(RegExp(r'/chat/completions/?$'), '')
          .replaceAll(RegExp(r'/completions/?$'), '');
      final Uri modelsUri = Uri.parse('$clean/models');
      final bool isAnthropic = baseUrl.contains('anthropic.com');

      final Map<String, String> headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (isAnthropic) {
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final http.Response response = await http.get(modelsUri, headers: headers);
      if (response.statusCode != 200) {
        return ModelFetchResult(error: '获取模型列表失败 (HTTP ${response.statusCode})');
      }

      final dynamic data = json.decode(response.body);
      final List<String> allIds = _parseModelIds(data, baseUrl);

      if (allIds.isEmpty) {
        return ModelFetchResult(error: '未找到可用模型');
      }

      // 分类：推荐 vs 其他
      final List<String> recommended = <String>[];
      final List<String> others = <String>[];
      for (final String id in allIds) {
        final bool isRec = kRecommendKeywords.any(
          (String kw) => id.toLowerCase().contains(kw.toLowerCase()),
        );
        if (isRec) {
          recommended.add(id);
        } else {
          others.add(id);
        }
      }

      // 去重 + 排序
      return ModelFetchResult(
        recommended: recommended.toSet().toList()..sort(),
        others: others.toSet().toList()..sort(),
      );
    } catch (e) {
      return ModelFetchResult(error: '获取模型列表失败: $e');
    }
  }

  /// 解析不同 API 格式的模型列表
  static List<String> _parseModelIds(dynamic data, String baseUrl) {
    final List<String> ids = <String>[];
    if (data is Map<String, dynamic>) {
      // OpenAI 兼容: {"data": [{"id": "gpt-4", ...}, ...]}
      if (data['data'] is List) {
        for (final dynamic item in data['data']) {
          if (item is Map<String, dynamic> && item['id'] is String) {
            ids.add(item['id'] as String);
          }
        }
      }
      // Anthropic / Google: {"models": [...]}
      if (data['models'] is List) {
        for (final dynamic item in data['models']) {
          if (item is Map<String, dynamic>) {
            // Anthropic 格式
            if (item['id'] is String) {
              ids.add(item['id'] as String);
            } else if (item['model_id'] is String) {
              ids.add(item['model_id'] as String);
            }
            // Google 格式: "models/gemini-2.5-flash"
            if (item['name'] is String) {
              ids.add((item['name'] as String).replaceFirst('models/', ''));
            }
          }
        }
      }
    }
    return ids;
  }
}

/// 模型获取结果
class ModelFetchResult {
  final List<String> recommended;
  final List<String> others;
  final String? error;

  ModelFetchResult({this.recommended = const <String>[], this.others = const <String>[], this.error});

  bool get hasError => error != null && error!.isNotEmpty;
  List<String> get all => [...recommended, ...others];
  bool get isEmpty => recommended.isEmpty && others.isEmpty;
}
