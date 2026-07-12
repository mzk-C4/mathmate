import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/api_config_service.dart';

class FormulaAnalysisResult {
  final String explanation;
  final String visualization;

  FormulaAnalysisResult({
    required this.explanation,
    required this.visualization,
  });
}

class FormulaAnalysisService {
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await dotenv.load(fileName: '.env');
    _initialized = true;
  }

  Future<FormulaAnalysisResult> analyze(String formula) async {
    await ensureInitialized();

    final ResolvedApiConfig config = await ApiConfigService.instance.resolve(
      provider: ApiProvider.volc,
      fallbackApiKey: dotenv.env['VOLC_API_KEY'] ?? '',
      fallbackModelId: dotenv.env['VOLC_MODEL_ID'] ?? '',
      fallbackBaseUrl:
          dotenv.env['VOLC_BASE_URL'] ??
          'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    );

    if (config.apiKey.isEmpty || config.modelId.isEmpty) {
      return FormulaAnalysisResult(
        explanation: '请配置 VOLC_API_KEY 和 VOLC_MODEL_ID',
        visualization: '',
      );
    }

    final prompt =
        '''你是一个数学公式可视化专家。分析以下 LaTeX 公式，返回 JSON：
{
  "explanation": "公式含义的中文解释（Markdown格式，可包含内嵌LaTeX）",
  "visualization": "完整的HTML代码，包含交互式Canvas/SVG可视化，暗色主题，参数可调节"
}

公式：$formula

只返回 JSON，不要其他文字。visualization 字段中必须是完整可独立运行的 HTML。''';

    final response = await http.post(
      Uri.parse(config.baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.modelId,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );

    if (response.statusCode != 200) {
      return FormulaAnalysisResult(
        explanation: '分析失败: ${response.statusCode}',
        visualization: '',
      );
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final content =
        (data['choices']?[0]?['message']?['content'] as String?) ?? '';
    final jsonStr = _extractJson(content);

    try {
      final analysis = jsonDecode(jsonStr);
      return FormulaAnalysisResult(
        explanation: analysis['explanation'] as String? ?? '',
        visualization: analysis['visualization'] as String? ?? '',
      );
    } catch (e) {
      return FormulaAnalysisResult(explanation: content, visualization: '');
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    if (start < 0) return text;
    int depth = 0;
    for (int i = start; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
    return text;
  }
}
