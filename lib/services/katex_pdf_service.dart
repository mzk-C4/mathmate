import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// KaTeX + WebView PDF 导出服务
/// 使用内嵌 KaTeX 渲染公式（无需网络），通过系统打印对话框导出 PDF
class KatexPdfService {
  static String? _cachedJs;
  static String? _cachedCss;

  /// 导出 PDF - 在 WebView 中预览，点击打印按钮触发系统打印
  Future<KatexPdfResult> exportToPdf({
    required String title,
    required String content,
    required BuildContext context,
    String subtitle = '由 MathMate 生成',
  }) async {
    try {
      // 确保 KaTeX JS/CSS 已缓存
      await _ensureKatexLoaded();

      // 生成 HTML 内容（内嵌 KaTeX）
      final String htmlContent = _generateHtml(title, subtitle, content);

      if (context.mounted) {
        await _openPrintDialog(context, htmlContent);
      }

      return KatexPdfResult(success: true);
    } catch (e) {
      return KatexPdfResult(success: false, error: e.toString());
    }
  }

  /// 从 assets 加载 KaTeX JS 和 CSS（仅加载一次，全局缓存）
  Future<void> _ensureKatexLoaded() async {
    if (_cachedJs != null && _cachedCss != null) return;
    _cachedJs ??= await rootBundle.loadString('assets/katex/katex.min.js');
    _cachedCss ??= await rootBundle.loadString('assets/katex/katex.min.css');
  }

  /// 生成 HTML 内容（KaTeX 内嵌，零外部依赖）
  String _generateHtml(String title, String subtitle, String content) {
    final String processedContent = _processMarkdownLatex(content);

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
      // KaTeX 渲染完成后设置就绪标志
      requestAnimationFrame(function() {
        requestAnimationFrame(function() {
          document.body.setAttribute('data-ready', 'true');
        });
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

    // 结论框：**结论** 或 **关键** 开头的内容
    text = text.replaceAllMapped(
      RegExp(r'\*\*(结论|关键|注意|总结|核心|重要)[：:]?\*\*\s*(.+?)(?=\n\n|\n\*\*|$)', multiLine: true),
      (Match m) {
        final String type = (m.group(1) ?? '').trim();
        final String body = (m.group(2) ?? '').trim();
        final String boxClass = type == '注意' ? 'warning-box' : 'conclusion-box';
        return '<div class="$boxClass"><strong>$type：</strong>$body</div>';
      },
    );

    // 分析框：**分析** 或 **思路** 开头的内容
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

    // 步骤标签（第X步 / Step X / 步骤X）
    text = text.replaceAllMapped(
      RegExp(r'(第\s*[一二三四五六七八九十百\d]+\s*步|Step\s*\d+|步骤\s*\d+)', multiLine: true),
      (Match m) => '<span class="step-label">${m.group(1)}</span>',
    );

    // 列表
    text = text.replaceAllMapped(RegExp(r'^\s*[-*+]\s+(.+)$', multiLine: true), (Match m) => '<li>${m.group(1)}</li>');
    text = text.replaceAllMapped(RegExp(r'(<li>.*</li>\n?)+'), (Match m) => '<ul>${m.group(0)}</ul>');

    // 引用
    text = text.replaceAllMapped(RegExp(r'^>\s*(.+)$', multiLine: true), (Match m) => '<blockquote>${m.group(1)}</blockquote>');

    // 段落化：未包裹的纯文本
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

  /// 打开 WebView 打印对话框
  Future<void> _openPrintDialog(BuildContext context, String htmlContent) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _PdfExportDialog(htmlContent: htmlContent),
    );
  }

  /// 清理缓存的 KaTeX（可选，释放内存）
  static void clearCache() {
    _cachedJs = null;
    _cachedCss = null;
  }
}

class _PdfExportDialog extends StatefulWidget {
  final String htmlContent;

  const _PdfExportDialog({required this.htmlContent});

  @override
  State<_PdfExportDialog> createState() => _PdfExportDialogState();
}

class _PdfExportDialogState extends State<_PdfExportDialog> {
  late final WebViewController _controller;
  bool _isReady = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (_) {
            if (mounted) setState(() => _hasError = true);
          },
        ),
      )
      ..loadHtmlString(widget.htmlContent);
    _monitorReady();
  }

  Future<void> _monitorReady() async {
    for (int i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      try {
        final String? ready = await _controller.runJavaScriptReturningResult(
          'document.body.getAttribute("data-ready")',
        ) as String?;
        if (ready == 'true') {
          if (mounted) setState(() => _isReady = true);
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isReady = true); // 超时后也显示内容
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: <Widget>[
            const Text('导出 PDF'),
            const Spacer(),
            if (_hasError)
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.75,
          child: Stack(
            children: <Widget>[
              WebViewWidget(controller: _controller),
              if (!_isReady)
                const Center(child: CircularProgressIndicator()),
              if (_hasError && _isReady)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.orange.shade50,
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.info_outline, color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '部分资源加载失败，但公式仍会尽力渲染。请点击下方打印按钮。',
                            style: TextStyle(fontSize: 13, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await _controller.runJavaScript('window.print();');
            },
            icon: const Icon(Icons.print),
            label: const Text('打印/导出 PDF'),
          ),
        ],
      ),
    );
  }
}

class KatexPdfResult {
  final bool success;
  final String? error;

  KatexPdfResult({required this.success, this.error});
}
