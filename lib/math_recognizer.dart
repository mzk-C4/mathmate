import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/services/provider_config_service.dart';

class MathRecognizer {
  Future<String?> recognizeFromImage(XFile imageFile) async {
    try {
      final pc = ProviderConfigService.instance;
      final apiKey = pc.visionApiKey;
      final modelId = pc.visionModelId;
      final baseUrl = pc.visionBaseUrl;

      if (apiKey.isEmpty || modelId.isEmpty) {
        return 'Missing env config: VOLC_API_KEY / VOLC_MODEL_ID';
      }

      final bytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          "model": modelId,
          "messages": [
            {
              "role": "user",
              "content": [
                {
                  "type": "text",
                  "text":
                      "你是专业的数学题目识别工具，严格遵守以下规则：\n"
                      "1. 只做图像文字与公式识别，绝对不解题、不解析、不计算、不生成答案。\n"
                      "2. 完整识别题干内容，包括中文、数字、符号、数学公式。\n"
                      "3. 输出格式严格为：\n"
                      "   - 所有纯文字题干部分，单独占多行（每个小问换行）\n"
                      "   - 所有数学公式部分，单独占一行，用标准LaTeX语法，不要用任何包裹符号\n"
                      "4. 文字和公式必须完全分离，文字行里绝对不能包含任何公式，公式行里绝对不能包含任何文字。\n"
                      "5. 多个小问（1）（2）（3）或①②③，每个小问单独换行。\n"
                      "6. 若题目可几何可视化，必须在输出末尾追加且仅追加一个代码块，使用 ```geometryjson 开头并以 ``` 结束。\n"
                      "7. geometryjson 必须满足：\n"
                      "   - 根节点必须包含 version、viewport、elements\n"
                      "   - version 固定为 \"1.0\"\n"
                      "   - viewport 必须包含 xMin/xMax/yMin/yMax，且全部为数字\n"
                      "   - elements 必须是数组，数组中每个元素都必须有非空字符串 id 和 type，且 id 全局唯一\n"
                      "   - type 仅允许 point、line、circle、dynamic_point\n"
                      "   - point.pos 与 circle.center 必须是长度为2的数字数组 [x, y]\n"
                      "   - circle.radius 必须是数字\n"
                      "   - line 必须包含 p1、p2（引用已定义点的 id）\n"
                      "   - dynamic_point 必须包含 targetId、constraint、initialT，其中 constraint 固定为 \"on_entity\"\n"
                      "   - 禁止 null、禁止注释、禁止尾逗号、禁止额外自然语言\n"
                      "8. 若题目不适合可视化，不要输出 geometryjson 代码块。\n"
                      "9. 除识别内容和可选 geometryjson 代码块外，不输出任何其它说明。",
                },
                {
                  "type": "image_url",
                  "image_url": {"url": "data:image/jpeg;base64,$base64Image"},
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String result = data['choices'][0]['message']['content'];

        result = result.replaceAll('```latex', '');
        result = result.replaceAll('\\(', '').replaceAll('\\)', '');
        result = result.replaceAll('\\[', '').replaceAll('\\]', '');
        result = result.replaceAll('\$', '');
        result = result.trim();

        return result;
      } else {
        final errorDetail = utf8.decode(response.bodyBytes);
        debugPrint('Volc API error: $errorDetail');
        return "接口报错: $errorDetail";
      }
    } catch (e) {
      debugPrint('识别错误: $e');
      return "识别出错: $e";
    }
  }
}
