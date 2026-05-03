import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/data/history_models.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:mathmate/models/pipeline_models.dart';
import 'package:mathmate/models/pipeline_stage.dart';
import 'package:mathmate/services/math_pipeline_service.dart';
import 'package:mathmate/visualization/geometry_validator.dart';
import 'package:mathmate/visualization_page.dart';
import 'package:mathmate/visualization/jxg_webview.dart';
import 'package:mathmate/visualization/safe_json_parser.dart';
import 'package:mathmate/services/katex_pdf_service.dart';

class BeautifulResultPage extends StatefulWidget {
  final File image;
  final MathHistory? history;
  final String? heroTag;

  const BeautifulResultPage({
    super.key,
    required this.image,
    this.history,
    this.heroTag,
  });

  @override
  State<BeautifulResultPage> createState() => _BeautifulResultPageState();
}

class _BeautifulResultPageState extends State<BeautifulResultPage> {
  final MathPipelineService _pipelineService = MathPipelineService();

  bool _isAnalyzing = true;
  String _statusMessage = '准备开始处理...';

  Uint8List? _imageBytes;
  String _questionMarkdown = '';
  String _solutionMarkdown = '';
  String? _formulaPreview;
  Map<String, dynamic>? _geometryScene;
  String? _geometryMessage;
  List<String> _stageErrors = <String>[];

  @override
  void initState() {
    super.initState();
    _loadImageBytes();
    _bootstrapPage();
  }

  Future<void> _bootstrapPage() async {
    if (widget.history != null) {
      _restoreFromHistory(widget.history!);
      return;
    }
    await _runPipeline();
  }

  Future<void> _loadImageBytes() async {
    try {
      if (!await widget.image.exists()) {
        debugPrint('Image file does not exist: ${widget.image.path}');
        return;
      }
      _imageBytes = await widget.image.readAsBytes();
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (e, stack) {
      debugPrint('Error loading image bytes: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _runPipeline() async {
    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'AI 正在解析题目...';
      _stageErrors = <String>[];
    });

    try {
      final PipelineResult result = await _pipelineService.runFromImage(
        XFile(widget.image.path),
        onStageChanged: (PipelineStage stage) {
          if (!mounted) {
            return;
          }
          setState(() {
            _statusMessage = _messageForStage(stage);
          });
        },
      );

      if (!mounted) {
        return;
      }

      final String questionMarkdown =
          result.recognize?.questionMarkdown.trim() ?? '';
      final String solutionMarkdown =
          result.solve?.solutionMarkdown.trim() ?? '';
      final String formulaPreview = _extractFormulaPreview(
        '$questionMarkdown\n$solutionMarkdown',
      );
      final String cleanedLatex = _cleanLatex(formulaPreview);

      final VisualizeResult? visualize = result.visualize;
      final String? geometryMessage = visualize?.scene != null
          ? null
          : visualize?.error ?? '当前未生成可视化数据。';

      setState(() {
        _isAnalyzing = false;
        _questionMarkdown = questionMarkdown;
        _solutionMarkdown = solutionMarkdown;
        _formulaPreview = cleanedLatex.isEmpty ? null : cleanedLatex;
        _geometryScene = visualize?.scene;
        _geometryMessage = geometryMessage;
        _stageErrors = List<String>.from(result.stageErrors);
        _statusMessage = _stageErrors.isEmpty ? '处理完成' : '部分阶段失败，请检查下方提示';
      });

      if (result.recognize != null) {
        _persistHistoryAsync();
      }
    } catch (e, stack) {
      debugPrint('Pipeline error: $e');
      debugPrint('$stack');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = '处理出错: $e';
          _stageErrors = <String>['系统错误: ${e.toString()}'];
        });
      }
    }
  }

  void _restoreFromHistory(MathHistory history) {
    final SafeJsonParser parser = const SafeJsonParser();

    final GeometrySceneEmbedded? scene = history.geometryScene;
    final Map<String, dynamic>? sceneMap = scene?.toMap();

    final String formulaPreview = _extractFormulaPreview(history.latexResult);
    final String cleanedLatex = _cleanLatex(formulaPreview);

    final Map<String, dynamic>? normalizedScene = sceneMap == null
        ? null
        : _normalizeSceneMap(sceneMap, parser);

    Map<String, dynamic>? validatedScene;
    String? geometryMessage;
    if (normalizedScene != null) {
      final GeometryValidationResult validation = const GeometryValidator()
          .validate(normalizedScene);
      if (validation.isValid && validation.scene != null) {
        validatedScene = validation.scene!.toJson();
      } else {
        geometryMessage = validation.error ?? '历史几何数据校验失败。';
      }
    }

    setState(() {
      _isAnalyzing = false;
      _statusMessage = '已加载历史记录';
      _questionMarkdown = history.ocrContent;
      _solutionMarkdown = history.solutionMarkdown;
      _formulaPreview = cleanedLatex.isEmpty ? null : cleanedLatex;
      _geometryScene = validatedScene;
      _geometryMessage =
          geometryMessage ?? (_geometryScene == null ? '历史记录中无可视化数据。' : null);
      _stageErrors = <String>[];
    });
  }

  Map<String, dynamic> _normalizeSceneMap(
    Map<String, dynamic> scene,
    SafeJsonParser parser,
  ) {
    final Map<String, dynamic> viewportRaw = parser.safeMap(
      parser.readValueCaseInsensitive(scene, <String>['viewport']) ??
          <String, dynamic>{},
    );
    final List<dynamic> elementsRaw = parser.safeList(
      parser.readValueCaseInsensitive(scene, <String>['elements']) ??
          <dynamic>[],
    );

    final Map<String, dynamic> normalizedViewport = <String, dynamic>{
      'xMin': parser.safeToDouble(
        parser.readValueCaseInsensitive(viewportRaw, <String>['xMin', 'xmin']),
        -5.0,
      ),
      'xMax': parser.safeToDouble(
        parser.readValueCaseInsensitive(viewportRaw, <String>['xMax', 'xmax']),
        5.0,
      ),
      'yMin': parser.safeToDouble(
        parser.readValueCaseInsensitive(viewportRaw, <String>['yMin', 'ymin']),
        -5.0,
      ),
      'yMax': parser.safeToDouble(
        parser.readValueCaseInsensitive(viewportRaw, <String>['yMax', 'ymax']),
        5.0,
      ),
    };

    final List<Map<String, dynamic>> normalizedElements = elementsRaw
        .map((dynamic e) => parser.safeMap(e))
        .toList();

    return <String, dynamic>{
      'viewport': normalizedViewport,
      'elements': normalizedElements,
    };
  }

  Future<void> _persistHistoryAsync() async {
    try {
      await HistoryRepository.instance.saveHistory(
        sourceImage: widget.image,
        ocrContent: _questionMarkdown,
        solutionMarkdown: _solutionMarkdown,
        latexResult: _cleanLatex(_formulaPreview ?? _solutionMarkdown),
        sceneMap: _geometryScene,
      );
    } catch (e) {
      debugPrint('save history failed: $e');
    }
  }

  String _cleanLatex(String input) {
    String text = input.trim();
    if (text.isEmpty) {
      return text;
    }

    text = text.replaceAllMapped(
      RegExp(r'\\\\(begin|end)\{'),
      (Match match) => '\\${match.group(1)}{',
    );

    text = text
        .replaceAll(r'\begin{cases}', r'\begin{aligned}')
        .replaceAll(r'\end{cases}', r'\end{aligned}');

    final List<String> rows = text.split(r'\\');
    if (rows.length > 1) {
      final List<String> normalizedRows = rows.map((String row) {
        final String cleaned = row.trim();
        if (cleaned.isEmpty || cleaned.contains('&')) {
          return cleaned;
        }
        return '& $cleaned';
      }).toList();
      text = normalizedRows.join(r'\\');
    }

    text = text.replaceFirst(RegExp(r'[，。；：、,.!?！？]+$'), '');
    return text;
  }

  String _messageForStage(PipelineStage stage) {
    switch (stage) {
      case PipelineStage.idle:
        return '等待开始';
      case PipelineStage.recognizing:
        return '正在识别题目文本...';
      case PipelineStage.solving:
        return '正在生成解答过程...';
      case PipelineStage.visualizing:
        return '正在生成可视化 JSON...';
      case PipelineStage.completed:
        return '处理完成';
      case PipelineStage.failed:
        return '流程失败';
    }
  }

  String _extractFormulaPreview(String input) {
    final RegExp displayMath = RegExp(r'\$\$([\s\S]*?)\$\$');
    final RegExp inlineMath = RegExp(r'\$([^\$\n]+)\$');

    final RegExpMatch? displayMatch = displayMath.firstMatch(input);
    if (displayMatch != null) {
      return (displayMatch.group(1) ?? '').trim();
    }

    final RegExpMatch? inlineMatch = inlineMath.firstMatch(input);
    if (inlineMatch != null) {
      return (inlineMatch.group(1) ?? '').trim();
    }

    final List<String> lines = input
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();

    for (final String line in lines) {
      if (_looksLikeFormula(line)) {
        return line;
      }
    }

    return '';
  }

  bool _looksLikeFormula(String text) {
    return text.contains(r'\') ||
        text.contains('_') ||
        text.contains('^') ||
        text.contains('{') ||
        text.contains('}') ||
        text.contains('=');
  }

  Future<void> _exportPdf() async {
    final StringBuffer content = StringBuffer();
    content.writeln('## 题目内容');
    content.writeln();
    content.writeln(_questionMarkdown.isNotEmpty ? _questionMarkdown : '（题目识别为空）');
    content.writeln();
    content.writeln('## 解答过程');
    content.writeln();
    content.writeln(_solutionMarkdown.isNotEmpty ? _solutionMarkdown : '（解题阶段未返回内容）');
    if (_formulaPreview != null && _formulaPreview!.isNotEmpty) {
      content.writeln();
      content.writeln('## 公式预览');
      content.writeln();
      final String ds = '\x24\x24';
      content.writeln('$ds$_formulaPreview$ds');
    }

    final KatexPdfService pdfService = KatexPdfService();
    final KatexPdfResult result = await pdfService.exportToPdf(
      title: 'MathMate 识别结果',
      content: content.toString(),
      context: context,
    );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF 生成完成，请在打印对话框中选择"另存为 PDF"'),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: ${result.error}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red.shade400,
        ),
      );
    }
  }


  void _copyFormula() {
    final String? formula = _formulaPreview;
    if (formula == null || formula.isEmpty) {
      return;
    }

    Clipboard.setData(ClipboardData(text: formula));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ 公式已复制')));
    }
  }

  void _showFullImageViewer() {
    if (_imageBytes == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (BuildContext context) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: Image.memory(_imageBytes!),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMarkdownBlock({
    required String title,
    required String content,
    String emptyText = '暂无内容',
    Color accentColor = const Color(0xFF3F51B5),
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (content.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                emptyText,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> blocks = _buildContentBlocks(content);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          blocks.length == 1 && blocks.first is Math
              ? Center(child: blocks.first)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _mergeBlocksIntoLines(blocks),
                ),
        ],
      ),
    );
  }

  /// Merge blocks into lines: each "第 X 步" starts a new line, otherwise wrap inline.
  List<Widget> _mergeBlocksIntoLines(List<Widget> blocks) {
    final List<Widget> lines = <Widget>[];
    List<Widget> currentLine = <Widget>[];

    for (final Widget block in blocks) {
      final String? label = _getStepLabel(block);
      if (label != null) {
        if (currentLine.isNotEmpty) {
          lines.add(_buildLineWrap(currentLine));
          currentLine = <Widget>[];
        }
        lines.add(SizedBox(height: 8));
        currentLine.add(block);
      } else {
        currentLine.add(block);
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(_buildLineWrap(currentLine));
    }

    return lines;
  }

  String? _getStepLabel(Widget w) {
    if (w is! Text) return null;
    final String t = (w.data ?? '').trim();
    // 第X步 / 第 X 步 / Step X / 步骤X / 【第X步】 / X.  / (X)
    if (RegExp(
            r'^(第\s*[一二三四五六七八九十百\d]+\s*步|Step\s*\d+|步骤\s*\d+|【第|\(\d+\)|\d+\.\s)')
        .hasMatch(t)) {
      return t;
    }
    return null;
  }

  Widget _buildLineWrap(List<Widget> children) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  List<Widget> _buildContentBlocks(String content) {
    final List<Widget> widgets = <Widget>[];
    final RegExp displayMathRegex = RegExp(r'\$\$([\s\S]*?)\$\$');

    int lastEnd = 0;
    for (final RegExpMatch match in displayMathRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        final String textBefore = content
            .substring(lastEnd, match.start)
            .trim();
        if (textBefore.isNotEmpty) {
          widgets.addAll(_buildInlineMathText(textBefore));
        }
      }

      final String latex = match.group(1)?.trim() ?? '';
      if (latex.isNotEmpty) {
        widgets.add(_buildMathWidget(latex, fontSize: 16));
      }

      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      final String textAfter = content.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.addAll(_buildInlineMathText(textAfter));
      }
    }

    if (widgets.isEmpty) {
      widgets.addAll(_buildInlineMathText(content));
    }

    return widgets;
  }

  Widget _buildMathWidget(String latex, {double fontSize = 15}) {
    // flutter_math_fork 遇到无效 LaTeX 会渲染黄色错误框而不是抛异常，
    // 所以先做语法检查，无效时直接显示原文
    Widget buildMath() {
      if (!_isValidLatex(latex)) {
        return Text(latex, style: TextStyle(fontSize: fontSize, fontFamily: 'monospace'));
      }
      try {
        return Math.tex(latex, textStyle: TextStyle(fontSize: fontSize));
      } catch (e) {
        return Text(latex, style: TextStyle(fontSize: fontSize, fontFamily: 'monospace'));
      }
    }

    // 长公式用 InteractiveViewer 支持缩放和平移
    final Widget mathWidget = buildMath();
    final double fontSizeValue = fontSize;
    final double estimatedWidth = latex.length * fontSizeValue * 0.6;

    if (estimatedWidth > 300) {
      return InteractiveViewer(
        panEnabled: true,
        scaleEnabled: true,
        minScale: 0.5,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(40),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: mathWidget,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: mathWidget,
    );
  }

  bool _isValidLatex(String latex) {
    // 检查花括号是否平衡
    int braceCount = 0;
    bool escaped = false;
    for (int i = 0; i < latex.length; i++) {
      final String c = latex[i];
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '{') braceCount++;
      if (c == '}') braceCount--;
      if (braceCount < 0) return false;
    }
    if (braceCount != 0) return false;
    // 检查方括号是否平衡（常见错误）
    int bracketCount = 0;
    escaped = false;
    for (int i = 0; i < latex.length; i++) {
      final String c = latex[i];
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '[') bracketCount++;
      if (c == ']') bracketCount--;
    }
    if (bracketCount != 0) return false;
    return true;
  }

  List<Widget> _buildInlineMathText(String text) {
    final List<Widget> widgets = <Widget>[];
    final RegExp inlineMathRegex = RegExp(r'\$([^\$\n]+)\$');

    int lastEnd = 0;
    for (final RegExpMatch match in inlineMathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        final String textBefore = text.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          widgets.add(_buildMarkdownText(textBefore));
        }
      }

      final String latex = match.group(1)?.trim() ?? '';
      if (latex.isNotEmpty) {
        widgets.add(_buildMathWidget(latex, fontSize: 15));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final String textAfter = text.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.add(_buildMarkdownText(textAfter));
      }
    }

    if (widgets.isEmpty && text.isNotEmpty) {
      widgets.add(_buildMarkdownText(text));
    }

    return widgets;
  }

  Widget _buildMarkdownText(String text) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 14, height: 1.45),
        h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        code: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        blockquote: const TextStyle(color: Colors.blueGrey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _imageBytes == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: _showFullImageViewer,
                    child: widget.heroTag == null
                        ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                        : Hero(
                            tag: widget.heroTag!,
                            child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                          ),
                  ),
          ),
          Container(color: Colors.black26),
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.2,
            maxChildSize: 0.92,
            builder: (BuildContext context, ScrollController controller) {
              return Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '识别结果',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage),
                      if (_stageErrors.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        ..._stageErrors.map(
                          (String error) => Text(
                            '• $error',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      if (_isAnalyzing)
                        const Center(child: CircularProgressIndicator())
                      else ...<Widget>[
                        _buildMarkdownBlock(
                          title: '题目内容',
                          content: _questionMarkdown,
                          emptyText: '题目识别为空',
                          accentColor: const Color(0xFF5C6BC0),
                        ),
                        const SizedBox(height: 16),
                        _buildMarkdownBlock(
                          title: '解答过程',
                          content: _solutionMarkdown,
                          emptyText: '解题阶段未返回内容',
                          accentColor: const Color(0xFF26A69A),
                        ),
                        const SizedBox(height: 20),
                        if (_formulaPreview != null) ...<Widget>[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E5F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFCE93D8), width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    const Icon(Icons.functions, size: 18, color: Color(0xFF7B1FA2)),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '公式预览',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: Color(0xFF7B1FA2),
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: _copyFormula,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Icon(Icons.copy, size: 14, color: Color(0xFF7B1FA2)),
                                            SizedBox(width: 4),
                                            Text('点击复制', style: TextStyle(fontSize: 12, color: Color(0xFF7B1FA2))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: InteractiveViewer(
                                    panEnabled: true,
                                    scaleEnabled: true,
                                    minScale: 0.5,
                                    maxScale: 3.0,
                                    boundaryMargin: const EdgeInsets.all(40),
                                    child: Math.tex(
                                      _formulaPreview!,
                                      textStyle: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_geometryScene != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 300,
                              child: JxgWebView(
                                scene: _geometryScene!,
                                onEngineError: (msg) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('可视化加载失败: $msg')),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => VisualizationPage(
                                      scene: _geometryScene!,
                                      title: '几何可视化',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.fullscreen, size: 18),
                              label: const Text('全屏查看'),
                            ),
                          ),
                        ] else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _geometryMessage ?? '暂未生成可视化数据。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _exportPdf,
                            icon: const Icon(Icons.picture_as_pdf, size: 22),
                            label: const Text('导出扫描锐化 PDF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFF3F51B5),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
