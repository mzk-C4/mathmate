import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/api_config_service.dart';
import 'package:mathmate/services/auth_service.dart';

class HandwritingOcrService {
  static const String _ocrModelEnv = 'VOLC_OCR_MODEL_ID';
  static const String _defaultModelEnv = 'VOLC_MODEL_ID';

  static const String _handwritingPrompt = '''
你是专业的手写数学公式识别工具，严格遵守以下规则：
1. 识别所有手写内容，包括文字、数字、符号、数学公式
2. 输出格式为纯LaTeX代码，不要任何包裹符号
3. 保持原有数学表达式结构，使用标准LaTeX语法
4. 颜色信息用 \\textcolor{颜色}{文字} 格式保留
5. 不输出任何解释或说明文字
6. 多个公式用空行分隔
''';

  Future<String> recognize(Uint8List imageBytes) async {
    await dotenv.load(fileName: '.env');

    final ResolvedApiConfig config = await ApiConfigService.instance.resolve(
      provider: ApiProvider.volc,
      fallbackApiKey: dotenv.env['VOLC_API_KEY'] ?? '',
      fallbackModelId:
          dotenv.env[_ocrModelEnv] ?? dotenv.env[_defaultModelEnv] ?? '',
      fallbackBaseUrl:
          dotenv.env['VOLC_BASE_URL'] ??
          'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      useVisionModel: true,
    );
    final String apiKey = config.apiKey;
    final String modelId = config.modelId;
    final String baseUrl = config.baseUrl;

    if (apiKey.isEmpty || modelId.isEmpty) {
      return '请配置 VOLC_API_KEY 和 VOLC_MODEL_ID';
    }

    final String base64Image = base64Encode(imageBytes);

    final response = await http
        .post(
          Uri.parse(baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
            ...AuthService().proxyAuthHeaders,
          },
          body: jsonEncode({
            'model': modelId,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': _handwritingPrompt},
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/png;base64,$base64Image'},
                  },
                ],
              },
            ],
          }),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw Exception('手写识别请求超时（60秒）');
          },
        );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      String result =
          (data['choices']?[0]?['message']?['content'] as String?) ?? '';
      return result
          .replaceAll('```latex', '')
          .replaceAll('```', '')
          .replaceAll(r'\(', '')
          .replaceAll(r'\)', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '')
          .trim();
    }

    return '识别失败: ${response.statusCode}';
  }
}
