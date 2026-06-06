import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/data/hive_models.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:mathmate/models/pipeline_stream_event.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:mathmate/services/pipeline_stream_service.dart';
import 'package:mathmate/visualization/geometry_validator.dart';
import 'package:mathmate/visualization/geometry_painter.dart';
import 'package:mathmate/visualization/geometry_svg_renderer.dart';
import 'package:mathmate/visualization/response_extractor.dart';
import 'package:mathmate/visualization/safe_json_parser.dart';
import 'package:mathmate/visualization_page.dart';
import 'package:mathmate/services/katex_pdf_service.dart';

class BeautifulResultPage extends StatefulWidget {
  final XFile image;
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
  final PipelineStreamService _streamService = PipelineStreamService();
  StreamSubscription<PipelineStreamEvent>? _sub;

  bool _isAnalyzing = true;
  String _statusMessage = '准备开始处理...';

  Uint8List? _imageBytes;
  String _questionMarkdown = '';
  String _solutionMarkdown = '';
  String? _formulaPreview;
  Map<String, dynamic>? _geometryScene;
  String? _geometryMessage;
  List<String> _stageErrors = <String>[];

  // 流式缓冲区
  String _ocrBuffer = '';
  String _solutionBuffer = '';

  // setState 外执行标记
  bool _shouldStartStage2 = false;
  bool _shouldFinalize = false;

  // setState 节流：限制 ~15fps，避免每 token 都 rebuild
  DateTime _lastRebuild = DateTime.now();
  Timer? _throttleTimer;
  bool _pendingRebuild = false;

  @override
  void initState() {
    super.initState();
    _bootstrapPage();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _sub?.cancel();
    _streamService.cancel();
    super.dispose();
  }

  Future<void> _bootstrapPage() async {
    if (widget.history != null) {
      _restoreFromHistory(widget.history!);
      return;
    }
    await _loadImageBytes();
    _startStreaming();
  }

  Future<void> _loadImageBytes() async {
    try {
      AppLogger.instance.info('[ResultPage] 尝试加载图片: ${widget.image.path}');
      _imageBytes = await widget.image.readAsBytes();
      AppLogger.instance.info('[ResultPage] 图片加载成功: ${_imageBytes!.length} 字节');
      if (!mounted) return;
      setState(() {});
    } catch (e, stack) {
      AppLogger.instance.error('[ResultPage] 图片加载失败: $e');
      AppLogger.instance.error('[ResultPage] 堆栈: $stack');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = '图片加载失败';
          _stageErrors.add('图片加载失败: $e');
        });
      }
    }
  }

  void _startStreaming() {
    if (_imageBytes == null) {
      setState(() {
        _isAnalyzing = false;
        _statusMessage = '无法开始：图片数据为空';
        _stageErrors.add('图片数据为空，请返回重试');
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'AI 正在解析题目...';
      _stageErrors = <String>[];
      _ocrBuffer = '';
      _solutionBuffer = '';
    });

    // 阶段 1: vision 模型识别题目
    _sub = _streamService.recognizeStream(_imageBytes!).listen(
      (PipelineStreamEvent event) => _onStreamEvent(event, isStage1: true),
      onError: (Object e) => _onStreamError(e),
    );
  }

  void _startStage2() {
    // 剥离 geometryjson：先尝试代码块，再尝试裸 JSON
    String cleanQuestion = ResponseExtractor.removeGeometryJsonBlock(_questionMarkdown);
    // 兜底：如果 _geometryBuffer 中已提取到 JSON，直接移除
    if (_geometryBuffer.isNotEmpty && cleanQuestion.contains(_geometryBuffer)) {
      cleanQuestion = cleanQuestion.replaceFirst(_geometryBuffer, '').trim();
    }
    // 移除残留的空代码块标记
    cleanQuestion = cleanQuestion
        .replaceAll(RegExp(r'```geometryjson\s*```'), '')
        .replaceAll(RegExp(r'```json\s*```'), '')
        .trim();
    if (cleanQuestion != _questionMarkdown) {
      _questionMarkdown = cleanQuestion; // 更新显示也用清洁版
    }

    AppLogger.instance.info('[ResultPage] 阶段2 清洁题目: ${cleanQuestion.length} 字符 (原始 ${_questionMarkdown.length})');

    // 阶段 2: reasoning 模型解答
    _sub?.cancel();
    _sub = _streamService.solveStream(cleanQuestion).listen(
      (PipelineStreamEvent event) => _onStreamEvent(event, isStage1: false),
      onError: (Object e) => _onStreamError(e),
    );
  }

  /// 节流 rebuild：限制 ~30fps。
  void _throttledRebuild() {
    if (!mounted) return;
    final int elapsed = DateTime.now().difference(_lastRebuild).inMilliseconds;
    if (elapsed >= 33) {
      _lastRebuild = DateTime.now();
      _pendingRebuild = false;
      setState(() {});
      return;
    }
    if (!_pendingRebuild) {
      _pendingRebuild = true;
      _throttleTimer?.cancel();
      _throttleTimer = Timer(Duration(milliseconds: 33 - elapsed), () {
        if (!mounted) return;
        _lastRebuild = DateTime.now();
        _pendingRebuild = false;
        setState(() {});
      });
    }
  }

  /// 立即 flush 待执行的 rebuild（阶段切换时使用）
  void _flushRebuild() {
    _throttleTimer?.cancel();
    _pendingRebuild = false;
    if (mounted) setState(() {});
  }

  void _onStreamEvent(PipelineStreamEvent event, {required bool isStage1}) {
    if (!mounted) return;

    // 状态直写（不需要 setState 包裹）
    if (event.statusMessage != null) _statusMessage = event.statusMessage!;
    if (event.error != null) {
      _stageErrors.add(event.error!);
      if (event.isDone) _isAnalyzing = false;
      _flushRebuild(); // 错误立即显示
      return;
    }
    if (event.isCancelled) {
      _isAnalyzing = false;
      _flushRebuild();
      return;
    }

    if (event.content != null) {
      if (isStage1) {
        switch (event.type) {
          case StreamContentType.ocrText:
            _ocrBuffer += event.content!;
            _questionMarkdown = _ocrBuffer;
            break;
          case StreamContentType.geometryJson:
            _geometryBuffer = event.content!;
            break;
          default:
            _ocrBuffer += event.content!;
            _questionMarkdown = _ocrBuffer;
        }
      } else {
        _solutionBuffer += event.content!;
        _solutionMarkdown = _solutionBuffer;
      }
    }

    if (event.isDone) {
      if (isStage1) {
        _shouldStartStage2 = true;
      } else {
        _isAnalyzing = false;
        _statusMessage = _stageErrors.isEmpty ? '处理完成' : '部分阶段失败，请检查下方提示';
        _shouldFinalize = true;
      }
    }

    _throttledRebuild(); // 节流 UI 刷新

    // setState 之外执行副作用
    if (_shouldStartStage2) {
      _shouldStartStage2 = false;
      _parseGeometry();
      if (_questionMarkdown.trim().isEmpty) {
        AppLogger.instance.warn('[ResultPage] OCR 文本为空，跳过解题阶段');
        _isAnalyzing = false;
        _statusMessage = '未识别到题目文字，请确认图片清晰且包含数学题';
        _flushRebuild();
      } else {
        AppLogger.instance.info('[ResultPage] 阶段1完成，OCR ${_questionMarkdown.length} 字符，启动阶段2');
        _startStage2();
      }
    }
    if (_shouldFinalize) {
      _shouldFinalize = false;
      _finalize();
    }
  }

  void _onStreamError(Object e) {
    AppLogger.instance.error('[ResultPage] 流异常: $e');
    if (mounted) {
      setState(() { _isAnalyzing = false; _stageErrors.add('系统错误: $e'); });
    }
  }

  String _geometryBuffer = '';
  void _parseGeometry() {
    if (_geometryBuffer.isNotEmpty) {
      try {
        final Map<String, dynamic> scene = jsonDecode(_geometryBuffer) as Map<String, dynamic>;
        final validation = const GeometryValidator().validate(scene);
        _geometryScene = validation.isValid ? scene : null;
        _geometryMessage = validation.isValid ? null : (validation.error ?? '几何数据校验失败');
      } catch (e) {
        AppLogger.instance.error('[ResultPage] 几何 JSON 解析失败: $e');
        _geometryMessage = '几何 JSON 解析失败: $e';
      }
    }
  }

  void _finalize() {
    final combined = '$_questionMarkdown\n$_solutionMarkdown';
    _formulaPreview = _cleanLatex(_extractFormulaPreview(combined));
    if (_formulaPreview?.isEmpty ?? true) _formulaPreview = null;
    if (_questionMarkdown.isNotEmpty) _persistHistoryAsync();
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
      if (validation.isValid) {
        validatedScene = normalizedScene;
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
      AppLogger.instance.info('[ResultPage] 开始保存历史记录...');
      await HistoryRepository.instance.saveHistory(
        sourceImage: widget.image,
        ocrContent: _questionMarkdown,
        solutionMarkdown: _solutionMarkdown,
        latexResult: _cleanLatex(_formulaPreview ?? _solutionMarkdown),
        sceneMap: _geometryScene,
      );
      AppLogger.instance.info('[ResultPage] 历史记录保存成功');
    } catch (e, stack) {
      AppLogger.instance.error('[ResultPage] 历史记录保存失败: $e');
      AppLogger.instance.error('[ResultPage] 堆栈: $stack');
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
    // 防御：再次剥离可能残留的 geometryjson 和代码块
    String cleanQuestion = ResponseExtractor.removeGeometryJsonBlock(_questionMarkdown);
    String cleanSolution = ResponseExtractor.removeGeometryJsonBlock(_solutionMarkdown);
    // 兜底：移除残留在文本中的裸 JSON
    if (_geometryBuffer.isNotEmpty) {
      cleanQuestion = cleanQuestion.replaceAll(_geometryBuffer, '');
      cleanSolution = cleanSolution.replaceAll(_geometryBuffer, '');
    }
    // 移除残留的空代码块标记和 thinking 相关内容
    cleanQuestion = cleanQuestion
        .replaceAll(RegExp(r'```\w*\s*```'), '')
        .trim();
    cleanSolution = cleanSolution
        .replaceAll(RegExp(r'```\w*\s*```'), '')
        .trim();

    final StringBuffer content = StringBuffer();
    content.writeln('## 题目内容');
    content.writeln();
    content.writeln(cleanQuestion.isNotEmpty ? cleanQuestion : '（题目识别为空）');
    content.writeln();
    content.writeln('## 解答过程');
    content.writeln();
    content.writeln(cleanSolution.isNotEmpty ? cleanSolution : '（解题阶段未返回内容）');

    // 几何可视化 SVG
    String? geometrySvg;
    if (_geometryScene != null) {
      try {
        final scene = SafeJsonParser.parseSceneFromMap(_geometryScene!);
        const renderer = GeometrySvgRenderer();
        geometrySvg = renderer.render(scene);
      } catch (e) {
        AppLogger.instance.error('[ResultPage] SVG 生成失败: $e');
      }
    }

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
      geometrySvg: geometrySvg,
    );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('HTML 文件已生成，请选择保存位置或浏览器打开'),
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

  void _showLogViewer() {
    final String logContent = AppLogger.instance.export();
    final TextEditingController logController = TextEditingController(
      text: logContent,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.bug_report, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        '调试日志',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${logContent.length} 字符',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: '复制全部日志',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: logContent));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日志已复制到剪贴板')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: '清空日志',
                        onPressed: () {
                          AppLogger.instance.clear();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日志已清空')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: TextField(
                      controller: logController,
                      maxLines: null,
                      expands: true,
                      readOnly: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.3,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
    // 规范化标题层级：#### → ###
    final String normalized = content.replaceAllMapped(
      RegExp(r'^#{4,6}\s+(.+)$', multiLine: true),
      (Match m) => '### ${m.group(1)}',
    );
    final List<Widget> widgets = <Widget>[];
    final RegExp displayMathRegex = RegExp(r'\$\$([\s\S]*?)\$\$');

    int lastEnd = 0;
    for (final RegExpMatch match in displayMathRegex.allMatches(normalized)) {
      if (match.start > lastEnd) {
        final String textBefore = normalized
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

    if (lastEnd < normalized.length) {
      final String textAfter = normalized.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.addAll(_buildInlineMathText(textAfter));
      }
    }

    if (widgets.isEmpty) {
      widgets.addAll(_buildInlineMathText(normalized));
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
    final RegExp inlineMathRegex = RegExp(r'\$([^\$\n]+)\$');

    // 无不含换行的内联公式 → 单次 MarkdownBody（保留完整 Markdown 格式）
    if (!inlineMathRegex.hasMatch(text)) {
      return <Widget>[_buildMarkdownText(text)];
    }

    // 有内联公式 → 按段落拆分，段落级渲染（保护列表、标题等 Markdown 结构）
    final List<String> paragraphs = text.split(RegExp(r'\n\n+'));
    final List<Widget> result = <Widget>[];
    for (int i = 0; i < paragraphs.length; i++) {
      final String para = paragraphs[i].trim();
      if (para.isEmpty) continue;

      if (inlineMathRegex.hasMatch(para)) {
        result.add(_buildRichTextParagraph(para));
      } else {
        result.add(_buildMarkdownText(para));
      }

      if (i < paragraphs.length - 1) {
        result.add(const SizedBox(height: 6));
      }
    }

    if (result.isEmpty && text.isNotEmpty) {
      result.add(_buildMarkdownText(text));
    }
    return result;
  }

  /// 将含内联公式的段落渲染为 Text.rich + WidgetSpan，保证公式与文字正确混排而不破坏段落结构
  Widget _buildRichTextParagraph(String text) {
    final RegExp inlineMathRegex = RegExp(r'\$([^\$\n]+)\$');
    final List<InlineSpan> spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final RegExpMatch match in inlineMathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF333333)),
        ));
      }

      final String latex = (match.group(1) ?? '').trim();
      if (latex.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildMathWidget(latex, fontSize: 15),
        ));
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF333333)),
      ));
    }

    return SelectionArea(
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF333333)),
          children: spans,
        ),
      ),
    );
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
                clipBehavior: Clip.hardEdge,
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
                      if (!_isAnalyzing) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showLogViewer,
                            icon: const Icon(Icons.bug_report, size: 16),
                            label: const Text('查看调试日志',
                                style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      // 题目内容：有就显示，不等待完成
                      if (_questionMarkdown.isNotEmpty)
                        _buildMarkdownBlock(
                          title: '题目内容',
                          content: _questionMarkdown,
                          emptyText: '题目识别为空',
                          accentColor: const Color(0xFF5C6BC0),
                        )
                      else if (_isAnalyzing)
                        const Center(child: CircularProgressIndicator()),

                      // 解答过程：有就显示，不等待完成
                      if (_solutionMarkdown.isNotEmpty || _questionMarkdown.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildMarkdownBlock(
                          title: '解答过程',
                          content: _solutionMarkdown,
                          emptyText: _isAnalyzing ? 'AI 正在生成解答...' : '解题阶段未返回内容',
                          accentColor: const Color(0xFF26A69A),
                        ),
                      ],

                      // 流式状态指示器
                      if (_isAnalyzing && _questionMarkdown.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                              const SizedBox(width: 8),
                              Text(_statusMessage, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                        ),

                      if (!_isAnalyzing) ...[
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
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: GeometryPainter(
                                  scene: SafeJsonParser.parseSceneFromMap(_geometryScene!),
                                ),
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
