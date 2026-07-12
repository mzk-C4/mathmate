import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/services/api_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('uses fallback values when custom provider is disabled', () async {
    final ResolvedApiConfig resolved = await ApiConfigService.instance.resolve(
      provider: ApiProvider.deepseek,
      fallbackApiKey: 'fallback-key',
      fallbackBaseUrl: 'https://fallback.example/chat',
      fallbackModelId: 'fallback-model',
    );

    expect(resolved.apiKey, 'fallback-key');
    expect(resolved.modelId, 'fallback-model');
    expect(resolved.isCustom, isFalse);
  });

  test('uses saved custom provider and vision model', () async {
    await ApiConfigService.instance.save(
      ApiProvider.volc,
      const ApiProviderConfig(
        enabled: true,
        apiKey: 'custom-key',
        baseUrl: 'https://custom.example/chat',
        modelId: 'text-model',
        visionModelId: 'vision-model',
        requestFormat: 'messages',
      ),
    );

    final ResolvedApiConfig resolved = await ApiConfigService.instance.resolve(
      provider: ApiProvider.volc,
      fallbackApiKey: 'fallback-key',
      fallbackBaseUrl: 'https://fallback.example/chat',
      fallbackModelId: 'fallback-model',
      useVisionModel: true,
    );

    expect(resolved.apiKey, 'custom-key');
    expect(resolved.modelId, 'vision-model');
    expect(resolved.requestFormat, 'messages');
    expect(resolved.isCustom, isTrue);
  });

  test('clear restores default disabled configuration', () async {
    await ApiConfigService.instance.save(
      ApiProvider.qwen,
      const ApiProviderConfig(
        enabled: true,
        apiKey: 'custom-key',
        baseUrl: 'https://custom.example/chat',
        modelId: 'custom-model',
      ),
    );

    await ApiConfigService.instance.clear(ApiProvider.qwen);
    final ApiProviderConfig config = await ApiConfigService.instance.load(
      ApiProvider.qwen,
    );

    expect(config.enabled, isFalse);
    expect(config.apiKey, isEmpty);
    expect(config.baseUrl, ApiProvider.qwen.defaultBaseUrl);
  });
}
