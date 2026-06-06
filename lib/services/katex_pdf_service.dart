import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// KaTeX HTML 导出服务
/// 使用内嵌 KaTeX 渲染公式（无需网络），生成自包含 HTML 文件保存到文档目录
class KatexPdfService {
  static String? _cachedJs;
  static String? _cachedCss;

  /// 导出 HTML 文件 - 保存到文档目录并通过分享/打开
  Future<KatexPdfResult> exportToPdf({
    required String title,
    required String content,
    String subtitle = '由 MathMate 生成',
    String? geometrySvg,
  }) async {
    try {
      await _ensureKatexLoaded();

      final String htmlContent = _generateHtml(title, subtitle, content, geometrySvg);
      final String filePath = await _saveHtmlFile(title, htmlContent);
      await _openAndShareFile(filePath);

      return KatexPdfResult(success: true, filePath: filePath);
    } catch (e) {
      return KatexPdfResult(success: false, error: e.toString());
    }
  }

  /// 从 assets 加载 KaTeX JS 和 CSS（仅加载一次，全局缓存）
  Future<void> _ensureKatexLoaded() async {
    if (_cachedJs != null && _cachedCss != null) return;
    _cachedJs ??= await rootBundle.loadString('assets/katex/katex.min.js');
    String rawCss = await rootBundle.loadString('assets/katex/katex.min.css');
    // 移除 @font-face 规则——本地 HTML 没有字体文件路径
    _cachedCss = rawCss.replaceAll(RegExp(r'@font-face\{[^}]*\}'), '');
  }

  /// 保存 HTML 到文档目录（持久化存储，不会被系统清理）
  Future<String> _saveHtmlFile(String title, String htmlContent) async {
    final Directory docDir = await getApplicationDocumentsDirectory();
    final String safeName = title.replaceAll(RegExp(r'[^\w一-鿿\- ]'), '').trim();
    final String fileName = safeName.isNotEmpty ? '$safeName.html' : 'mathmate_export.html';
    final File file = File('${docDir.path}/$fileName');
    await file.writeAsString(htmlContent);
    return file.path;
  }

  /// 打开 HTML 文件并通过分享对话框分享
  Future<void> _openAndShareFile(String filePath) async {
    await OpenFile.open(filePath, type: 'text/html');
    await Share.shareXFiles(
      <XFile>[XFile(filePath, mimeType: 'text/html')],
      subject: 'MathMate 数学解答',
    );
  }

  /// 生成 HTML 内容（KaTeX 内嵌，零外部依赖）
  String _generateHtml(String title, String subtitle, String content, String? geometrySvg) {
    final String processedContent = _processMarkdownLatex(content);
    final String geometrySection = geometrySvg != null
        ? '<h2>几何图形</h2><div style="text-align:center;margin:16px 0">$geometrySvg</div>'
        : '';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>$_cachedCss</style>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      font-size: 14px;
      line-height: 1.7;
      color: #333;
      max-width: 800px;
      margin: 0 auto;
      padding: 24px;
      background: #fff;
    }
    .header { text-align: center; border-bottom: 2px solid #3F51B5; padding-bottom: 16px; margin-bottom: 24px; }
    .header h1 { color: #3F51B5; font-size: 22px; margin: 0; }
    .header .subtitle { color: #999; font-size: 12px; margin-top: 4px; }
    h1 { font-size: 20px; color: #1A1A1A; margin: 20px 0 10px; padding-bottom: 6px; border-bottom: 1px solid #EEE; }
    h2 { font-size: 17px; color: #333; margin: 18px 0 8px; border-left: 4px solid #3F51B5; padding-left: 10px; }
    h3 { font-size: 15px; color: #555; margin: 14px 0 6px; }
    p { margin: 6px 0; }
    .math-display { margin: 12px 0; overflow-x: auto; padding: 8px 0; text-align: center; }
    .math-display .katex { font-size: 1.1em; }
    pre { background: #F5F5F5; padding: 12px; border-radius: 6px; overflow-x: auto; font-size: 13px; line-height: 1.5; }
    code { background: #F5F5F5; padding: 2px 6px; border-radius: 4px; font-family: 'Consolas', 'Monaco', monospace; font-size: 13px; }
    blockquote { border-left: 3px solid #3F51B5; margin: 12px 0; padding: 8px 16px; background: #F5F7FF; color: #555; }
    ul, ol { padding-left: 24px; }
    li { margin-bottom: 4px; }
    .step-label { font-weight: bold; color: #3F51B5; margin-top: 12px; }
    .conclusion-box { background: #E8F5E9; border-left: 4px solid #4CAF50; padding: 12px 16px; margin: 16px 0; border-radius: 0 8px 8px 0; }
    .conclusion-box strong { color: #2E7D32; }
    .warning-box { background: #FFF3E0; border-left: 4px solid #FF9800; padding: 12px 16px; margin: 16px 0; border-radius: 0 8px 8px 0; }
    .analysis-box { background: #E3F2FD; border-left: 4px solid #2196F3; padding: 12px 16px; margin: 16px 0; border-radius: 0 8px 8px 0; }
    .render-error { color: #999; font-style: italic; }
    .katex-display { overflow-x: auto; overflow-y: hidden; }
    .katex-display > .katex { white-space: nowrap; }
    pre { overflow-x: auto; white-space: pre-wrap; word-break: break-all; }
    pre code { white-space: pre-wrap; }
    table { display: block; max-width: 100%; overflow-x: auto; }
    code { white-space: break-spaces; }
    @page { margin: 15mm; }
    @media print {
      body { padding: 0; max-width: none; }
      .no-print { display: none; }
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>$title</h1>
    <div class="subtitle">$subtitle</div>
  </div>
  $processedContent
  $geometrySection
  <script>$_cachedJs</script>
  <script>
    (function() {
      var errors = [];
      document.querySelectorAll('.math-tex').forEach(function(el) {
        try {
          katex.render(el.textContent, el, {
            throwOnError: false,
            displayMode: el.classList.contains('math-display')
          });
        } catch (e) {
          errors.push(el.textContent.substring(0, 80));
          el.innerHTML = '<span class="render-error">[公式渲染失败]</span>';
        }
      });
    })();
  </script>
</body>
</html>
''';
  }

  /// 处理 Markdown 和 LaTeX 内容
  String _processMarkdownLatex(String content) {
    String text = content;

    // 代码块（最高优先级）
    text = text.replaceAllMapped(
      RegExp(r'```(\w*)\n?([\s\S]*?)```'),
      (Match m) => '<pre><code>${_escapeHtml((m.group(2) ?? '').trim())}</code></pre>',
    );

    // 行内代码
    text = text.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (Match m) => '<code>${_escapeHtml(m.group(1) ?? '')}</code>',
    );

    // $$...$$ 展示公式
    text = text.replaceAllMapped(
      RegExp(r'\$\$([\s\S]*?)\$\$'),
      (Match m) => '<div class="math-display"><span class="math-tex math-display">${_escapeHtml((m.group(1) ?? '').trim())}</span></div>',
    );

    // $...$ 内联公式
    text = text.replaceAllMapped(
      RegExp(r'\$([^\$\n]+?)\$'),
      (Match m) => '<span class="math-tex">${_escapeHtml((m.group(1) ?? '').trim())}</span>',
    );

    // 标题
    text = text.replaceAllMapped(RegExp(r'^### (.+)$', multiLine: true), (Match m) => '<h3>${m.group(1)}</h3>');
    text = text.replaceAllMapped(RegExp(r'^## (.+)$', multiLine: true), (Match m) => '<h2>${m.group(1)}</h2>');
    text = text.replaceAllMapped(RegExp(r'^# (.+)$', multiLine: true), (Match m) => '<h1>${m.group(1)}</h1>');

    // 结论框
    text = text.replaceAllMapped(
      RegExp(r'\*\*(结论|关键|注意|总结|核心|重要)[：:]?\*\*\s*(.+?)(?=\n\n|\n\*\*|$)', multiLine: true),
      (Match m) {
        final String type = (m.group(1) ?? '').trim();
        final String body = (m.group(2) ?? '').trim();
        final String boxClass = type == '注意' ? 'warning-box' : 'conclusion-box';
        return '<div class="$boxClass"><strong>$type：</strong>$body</div>';
      },
    );

    // 分析框
    text = text.replaceAllMapped(
      RegExp(r'\*\*(分析|思路|解析)[：:]?\*\*\s*(.+?)(?=\n\n|\n\*\*|$)', multiLine: true),
      (Match m) {
        final String type = (m.group(1) ?? '').trim();
        final String body = (m.group(2) ?? '').trim();
        return '<div class="analysis-box"><strong>$type：</strong>$body</div>';
      },
    );

    // 加粗
    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (Match m) => '<strong>${m.group(1)}</strong>');
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (Match m) => '<em>${m.group(1)}</em>');

    // 步骤标签
    text = text.replaceAllMapped(
      RegExp(r'(第\s*[一二三四五六七八九十百\d]+\s*步|Step\s*\d+|步骤\s*\d+)', multiLine: true),
      (Match m) => '<span class="step-label">${m.group(1)}</span>',
    );

    // 列表
    text = text.replaceAllMapped(RegExp(r'^\s*[-*+]\s+(.+)$', multiLine: true), (Match m) => '<li>${m.group(1)}</li>');
    text = text.replaceAllMapped(RegExp(r'(<li>.*</li>\n?)+'), (Match m) => '<ul>${m.group(0)}</ul>');

    // 引用
    text = text.replaceAllMapped(RegExp(r'^>\s*(.+)$', multiLine: true), (Match m) => '<blockquote>${m.group(1)}</blockquote>');

    // 段落化
    final List<String> lines = text.split('\n');
    final StringBuffer buffer = StringBuffer();
    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('<h') ||
          trimmed.startsWith('<pre') ||
          trimmed.startsWith('<ul') ||
          trimmed.startsWith('<ol') ||
          trimmed.startsWith('<blockquote') ||
          trimmed.startsWith('<div ')) {
        buffer.write(trimmed);
      } else if (!trimmed.startsWith('</')) {
        buffer.write('<p>$trimmed</p>');
      } else {
        buffer.write(trimmed);
      }
    }

    return buffer.toString();
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 清理缓存的 KaTeX
  static void clearCache() {
    _cachedJs = null;
    _cachedCss = null;
  }
}

class KatexPdfResult {
  final bool success;
  final String? error;
  final String? filePath;

  KatexPdfResult({required this.success, this.error, this.filePath});
}
