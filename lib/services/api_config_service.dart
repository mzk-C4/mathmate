import 'package:shared_preferences/shared_preferences.dart';

enum ApiProvider { deepseek, qwen, volc }

extension ApiProviderInfo on ApiProvider {
  String get storageId => name;

  String get displayName => switch (this) {
    ApiProvider.deepseek => 'DeepSeek',
    ApiProvider.qwen => '通义千问',
    ApiProvider.volc => '火山 Ark',
  };

  String get defaultBaseUrl => switch (this) {
    ApiProvider.deepseek => 'https://api.deepseek.com/chat/completions',
    ApiProvider.qwen =>
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    ApiProvider.volc =>
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
  };

  String get defaultModelId => switch (this) {
    ApiProvider.deepseek => 'deepseek-chat',
    ApiProvider.qwen => 'qwen-plus',
    ApiProvider.volc => 'deepseek-v4-flash',
  };
}

class ApiProviderConfig {
  const ApiProviderConfig({
    required this.enabled,
    required this.apiKey,
    required this.baseUrl,
    required this.modelId,
    this.visionModelId = '',
    this.requestFormat = 'auto',
  });

  final bool enabled;
  final String apiKey;
  final String baseUrl;
  final String modelId;
  final String visionModelId;
  final String requestFormat;

  bool get isComplete =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      modelId.trim().isNotEmpty;
}

class ResolvedApiConfig {
  const ResolvedApiConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.modelId,
    required this.requestFormat,
    required this.isCustom,
  });

  final String apiKey;
  final String baseUrl;
  final String modelId;
  final String requestFormat;
  final bool isCustom;
}

class ApiConfigService {
  ApiConfigService._();

  static final ApiConfigService instance = ApiConfigService._();
  static const String _prefix = 'custom_ai_api';

  String _key(ApiProvider provider, String field) =>
      '${_prefix}_${provider.storageId}_$field';

  Future<ApiProviderConfig> load(ApiProvider provider) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ApiProviderConfig(
      enabled: prefs.getBool(_key(provider, 'enabled')) ?? false,
      apiKey: prefs.getString(_key(provider, 'api_key')) ?? '',
      baseUrl:
          prefs.getString(_key(provider, 'base_url')) ??
          provider.defaultBaseUrl,
      modelId:
          prefs.getString(_key(provider, 'model_id')) ??
          provider.defaultModelId,
      visionModelId: prefs.getString(_key(provider, 'vision_model_id')) ?? '',
      requestFormat:
          prefs.getString(_key(provider, 'request_format')) ?? 'auto',
    );
  }

  Future<void> save(ApiProvider provider, ApiProviderConfig config) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.setBool(_key(provider, 'enabled'), config.enabled),
      prefs.setString(_key(provider, 'api_key'), config.apiKey.trim()),
      prefs.setString(_key(provider, 'base_url'), config.baseUrl.trim()),
      prefs.setString(_key(provider, 'model_id'), config.modelId.trim()),
      prefs.setString(
        _key(provider, 'vision_model_id'),
        config.visionModelId.trim(),
      ),
      prefs.setString(
        _key(provider, 'request_format'),
        config.requestFormat.trim().toLowerCase(),
      ),
    ]);
  }

  Future<void> clear(ApiProvider provider) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.remove(_key(provider, 'enabled')),
      prefs.remove(_key(provider, 'api_key')),
      prefs.remove(_key(provider, 'base_url')),
      prefs.remove(_key(provider, 'model_id')),
      prefs.remove(_key(provider, 'vision_model_id')),
      prefs.remove(_key(provider, 'request_format')),
    ]);
  }

  Future<void> clearAll() async {
    for (final ApiProvider provider in ApiProvider.values) {
      await clear(provider);
    }
  }

  Future<ResolvedApiConfig> resolve({
    required ApiProvider provider,
    required String fallbackApiKey,
    required String fallbackBaseUrl,
    required String fallbackModelId,
    String fallbackRequestFormat = 'auto',
    bool useVisionModel = false,
  }) async {
    final ApiProviderConfig custom = await load(provider);
    if (custom.enabled && custom.isComplete) {
      final String selectedModel =
          useVisionModel && custom.visionModelId.isNotEmpty
          ? custom.visionModelId
          : custom.modelId;
      return ResolvedApiConfig(
        apiKey: custom.apiKey.trim(),
        baseUrl: custom.baseUrl.trim(),
        modelId: selectedModel.trim(),
        requestFormat: custom.requestFormat.trim().toLowerCase(),
        isCustom: true,
      );
    }

    return ResolvedApiConfig(
      apiKey: fallbackApiKey.trim(),
      baseUrl: fallbackBaseUrl.trim(),
      modelId: fallbackModelId.trim(),
      requestFormat: fallbackRequestFormat.trim().toLowerCase(),
      isCustom: false,
    );
  }
}
