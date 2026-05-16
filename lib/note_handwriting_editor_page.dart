import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'note_model.dart';
import 'services/formula_analysis_service.dart';
import 'services/handwriting_ocr_service.dart';
import 'widgets/ring_color_picker.dart';

enum CanvasMode { write, eraser, pan }
enum PaperBackground { blank, lined, grid }

class HandwritingStroke {
  final Color color;
  final double width;
  final List<Offset> points;

  HandwritingStroke({required this.color, required this.width, required this.points});

  Map<String, dynamic> toJson() => {
        'color': color.toARGB32(),
        'width': width,
        'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      };

  static HandwritingStroke fromJson(Map<String, dynamic> json) {
    return HandwritingStroke(
      color: Color(json['color'] as int),
      width: (json['width'] as num).toDouble(),
      points: (json['points'] as List)
          .map((p) => Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()))
          .toList(),
    );
  }
}

class RecognizedBlock {
  String text;
  Offset position;
  double scale;

  RecognizedBlock({required this.text, this.position = Offset.zero, this.scale = 1.0});

  Map<String, dynamic> toJson() => {
        'text': text,
        'dx': position.dx,
        'dy': position.dy,
        'scale': scale,
      };

  static RecognizedBlock fromJson(Map<String, dynamic> json) {
    return RecognizedBlock(
      text: json['text'] as String? ?? '',
      position: Offset(
        (json['dx'] as num?)?.toDouble() ?? 0,
        (json['dy'] as num?)?.toDouble() ?? 0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class PaperPage {
  List<HandwritingStroke> strokes = [];
  List<Offset> currentPoints = [];
  String recognizedText = '';
  List<RecognizedBlock> recognizedBlocks = [];
  PaperBackground background = PaperBackground.blank;
  double bgSpacing = 30.0;

  Map<String, dynamic> toJson() => {
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'recognizedText': recognizedText,
        'recognizedBlocks': recognizedBlocks.map((b) => b.toJson()).toList(),
        'background': background.index,
        'bgSpacing': bgSpacing,
      };

  static PaperPage fromJson(Map<String, dynamic> json) {
    PaperPage page = PaperPage();
    page.strokes = (json['strokes'] as List?)
            ?.map((s) => HandwritingStroke.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];
    page.recognizedText = json['recognizedText'] as String? ?? '';
    page.recognizedBlocks = (json['recognizedBlocks'] as List?)
            ?.map((b) => RecognizedBlock.fromJson(b as Map<String, dynamic>))
            .toList() ??
        [];
    page.background = PaperBackground.values[json['background'] as int? ?? 0];
    page.bgSpacing = (json['bgSpacing'] as num?)?.toDouble() ?? 30.0;
    return page;
  }
}

class NoteHandwritingEditorPage extends StatefulWidget {
  final Note? note;

  const NoteHandwritingEditorPage({super.key, this.note});

  @override
  State<NoteHandwritingEditorPage> createState() => _NoteHandwritingEditorPageState();
}

class _NoteHandwritingEditorPageState extends State<NoteHandwritingEditorPage>
    with TickerProviderStateMixin {
  final GlobalKey _canvasKey = GlobalKey();
  final HandwritingOcrService _ocrService = HandwritingOcrService();
  final FormulaAnalysisService _formulaService = FormulaAnalysisService();

  List<PaperPage> _pages = [PaperPage()];
  int _currentPageIndex = 0;

  PaperPage get _currentPage => _pages[_currentPageIndex];

  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;
  bool _isRecognizing = false;
  CanvasMode _canvasMode = CanvasMode.write;

  static const double _eraserWidth = 24.0;

  Color get _activeColor =>
      _canvasMode == CanvasMode.eraser ? Colors.grey.withValues(alpha: 0.3) : _selectedColor;
  double get _activeWidth =>
      _canvasMode == CanvasMode.eraser ? _eraserWidth : _strokeWidth;

  double _scale = 1.0;
  double _baseScale = 1.0;
  static const double _minScale = 0.5;
  static const double _maxScale = 3.0;

  static const Size _paperSize = Size(700.0, 900.0);
  Offset _paperOffset = Offset.zero;
  AnimationController? _springController;
  Animation<Offset>? _springAnimation;

  static const double _pageFlipThreshold = 0.3;
  double _dragAccumulatedX = 0;
  bool _isPageFlipping = false;
  bool _isDrawing = false;
  bool _isScaling = false;

  // 识别面板控制
  bool _showRecognitionPanel = false;
  bool _isPanelCollapsed = false;
  final DraggableScrollableController _panelController = DraggableScrollableController();

  // 公式分析状态
  String? _analyzingFormula;
  final Map<String, _FormulaAnalysis> _analysisCache = {};

  bool _enableVisualization = false;

  @override
  void initState() {
    super.initState();
    _loadNoteContent();
    _ensureEnv();
  }

  @override
  void dispose() {
    _springController?.dispose();
    _panelController.dispose();
    super.dispose();
  }

  Future<void> _ensureEnv() async {
    await dotenv.load(fileName: '.env');
  }

  void _loadNoteContent() {
    if (widget.note != null && widget.note!.content.isNotEmpty) {
      try {
        final data = jsonDecode(widget.note!.content);
        if (data is Map && data['pages'] != null) {
          setState(() {
            _pages = (data['pages'] as List)
                .map((p) => PaperPage.fromJson(p as Map<String, dynamic>))
                .toList();
            if (_pages.isEmpty) _pages = [PaperPage()];
          });
        }
      } catch (e) {
        debugPrint('加载笔记内容失败: $e');
      }
    }
  }

  void _addPage() {
    setState(() {
      _pages.add(PaperPage());
      _currentPageIndex = _pages.length - 1;
      _paperOffset = Offset.zero;
    });
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() {
      _currentPageIndex = index;
      _paperOffset = Offset.zero;
    });
  }

  void _undo() {
    setState(() {
      if (_currentPage.strokes.isNotEmpty) _currentPage.strokes.removeLast();
    });
  }

  void _clear() {
    setState(() {
      _currentPage.strokes.clear();
      _currentPage.currentPoints.clear();
      _currentPage.recognizedText = '';
      _paperOffset = Offset.zero;
    });
  }

  void _toggleMode(CanvasMode mode) {
    setState(() => _canvasMode = mode);
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_canvasMode == CanvasMode.pan) {
      _isScaling = details.pointerCount > 1;
      if (_isScaling) _baseScale = _scale;
      _dragAccumulatedX = 0;
      _isPageFlipping = false;
    } else {
      _isDrawing = true;
      RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
      setState(() {
        _currentPage.currentPoints = [box.globalToLocal(details.focalPoint)];
      });
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_canvasMode == CanvasMode.pan) {
      if (_isScaling || details.pointerCount > 1) {
        if (!_isScaling) { _isScaling = true; _baseScale = _scale; }
        setState(() {
          _scale = (_baseScale * details.scale).clamp(_minScale, _maxScale);
        });
        return;
      }
      final delta = details.focalPointDelta.dx;
      _dragAccumulatedX += delta;
      setState(() => _paperOffset += details.focalPointDelta);
      final screenWidth = MediaQuery.of(context).size.width;
      final threshold = screenWidth * _pageFlipThreshold;
      if (!_isPageFlipping) {
        if (_dragAccumulatedX > threshold && _currentPageIndex < _pages.length - 1) {
          _isPageFlipping = true;
          _goToPage(_currentPageIndex + 1);
        } else if (_dragAccumulatedX < -threshold && _currentPageIndex > 0) {
          _isPageFlipping = true;
          _goToPage(_currentPageIndex - 1);
        }
      }
      return;
    }
    if (!_isDrawing) return;
    RenderBox box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    setState(() {
      _currentPage.currentPoints.add(box.globalToLocal(details.focalPoint));
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_canvasMode == CanvasMode.pan) {
      if (_isScaling) { _isScaling = false; return; }
      if (_isPageFlipping) { _isPageFlipping = false; _dragAccumulatedX = 0; return; }
      _dragAccumulatedX = 0;
      _animateBack();
      return;
    }
    if (!_isDrawing) return;
    _isDrawing = false;
    if (_canvasMode == CanvasMode.eraser) {
      _eraseStrokes();
      setState(() => _currentPage.currentPoints.clear());
      return;
    }
    setState(() {
      if (_currentPage.currentPoints.isNotEmpty) {
        _currentPage.strokes.add(HandwritingStroke(
          color: _activeColor, width: _activeWidth,
          points: List.from(_currentPage.currentPoints),
        ));
        _currentPage.currentPoints.clear();
      }
    });
  }

  void _animateBack() {
    final screenSize = MediaQuery.of(context).size;
    final canvasWidth = screenSize.width - 16;
    final canvasHeight = screenSize.height * 0.45;
    final maxOffsetX = canvasWidth - _paperSize.width;
    final maxOffsetY = canvasHeight - _paperSize.height;
    if (_paperOffset.dx >= maxOffsetX && _paperOffset.dy >= maxOffsetY &&
        _paperOffset.dx <= 0 && _paperOffset.dy <= 0) {
      return;
    }
    double targetX = _paperOffset.dx.clamp(maxOffsetX, 0.0);
    double targetY = _paperOffset.dy.clamp(maxOffsetY, 0.0);
    final targetOffset = Offset(targetX, targetY);
    if (_paperOffset == targetOffset) return;
    _springController?.dispose();
    _springController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    );
    _springAnimation = Tween<Offset>(
      begin: _paperOffset, end: targetOffset,
    ).animate(CurvedAnimation(parent: _springController!, curve: Curves.elasticOut));
    _springController!.addListener(() {
      setState(() => _paperOffset = _springAnimation!.value);
    });
    _springController!.forward();
  }

  void _eraseStrokes() {
    final eraserPath = List<Offset>.from(_currentPage.currentPoints);
    final threshold = _eraserWidth / 2;
    setState(() {
      _currentPage.strokes.removeWhere((stroke) {
        for (final point in stroke.points) {
          for (int i = 0; i < eraserPath.length - 1; i++) {
            if (_pointToSegmentDistance(point, eraserPath[i], eraserPath[i + 1]) < threshold) {
              return true;
            }
          }
        }
        return false;
      });
    });
  }

  double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final dot = ap.dx * ab.dx + ap.dy * ab.dy;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final t = (dot / lenSq).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }

  Rect _calculateStrokeBounds() {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    double maxStrokeWidth = 0;

    for (final stroke in _currentPage.strokes) {
      if (stroke.width > maxStrokeWidth) maxStrokeWidth = stroke.width;
      for (final point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
    }
    for (final point in _currentPage.currentPoints) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }

    const padding = 32.0;
    final halfWidth = maxStrokeWidth / 2;
    final totalPadding = padding + halfWidth;
    return Rect.fromLTRB(
      (minX - totalPadding).clamp(0, _paperSize.width),
      (minY - totalPadding).clamp(0, _paperSize.height),
      (maxX + totalPadding).clamp(0, _paperSize.width),
      (maxY + totalPadding).clamp(0, _paperSize.height),
    );
  }

  List<Offset> _catmullRomSmoothPoints(List<Offset> points) {
    final result = <Offset>[points.first];
    final pts = [points.first, ...points, points.last];
    for (int i = 0; i < pts.length - 3; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final p2 = pts[i + 2];
      final p3 = pts[i + 3];
      for (int j = 1; j <= 8; j++) {
        final t = j / 8.0;
        final t2 = t * t;
        final t3 = t2 * t;
        result.add(Offset(
          0.5 * (2 * p1.dx + (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
          0.5 * (2 * p1.dy + (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
        ));
      }
    }
    result.add(points.last);
    return result;
  }

  void _drawSmoothPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawPoints(ui.PointMode.points, points, paint);
      return;
    }
    if (points.length == 2) {
      canvas.drawLine(points[0], points[1], paint);
      return;
    }
    final smoothed = _catmullRomSmoothPoints(points);
    final path = Path();
    path.moveTo(smoothed.first.dx, smoothed.first.dy);
    for (int i = 1; i < smoothed.length; i++) {
      path.lineTo(smoothed[i].dx, smoothed[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  Future<ui.Image> _renderStrokesBlack(Rect bounds) async {
    const pixelRatio = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-bounds.left, -bounds.top);

    // 白色背景
    canvas.drawRect(bounds, Paint()..color = Colors.white);

    // 所有笔迹以黑色绘制，忽略用户选择的颜色
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _currentPage.strokes) {
      paint.strokeWidth = stroke.width;
      _drawSmoothPath(canvas, stroke.points, paint);
    }
    if (_currentPage.currentPoints.isNotEmpty) {
      paint.strokeWidth = _activeWidth;
      _drawSmoothPath(canvas, _currentPage.currentPoints, paint);
    }

    final picture = recorder.endRecording();
    return picture.toImage(
      (bounds.width * pixelRatio).ceil(),
      (bounds.height * pixelRatio).ceil(),
    );
  }

  Future<void> _recognizeHandwriting() async {
    if (_currentPage.strokes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前页没有笔迹')));
      return;
    }
    setState(() => _isRecognizing = true);
    try {
      final strokeBounds = _calculateStrokeBounds();

      // 生成黑白识别用图：无论用户选什么颜色，笔迹统一黑色，白色背景
      final image = await _renderStrokesBlack(strokeBounds);

      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null && mounted) {
        Uint8List pngBytes = byteData.buffer.asUint8List();
        final result = await _ocrService.recognize(pngBytes);
        if (mounted) {
          // 将识别结果解析为 RecognizedBlock 列表，位置跟随笔迹区域
          final blocks = <RecognizedBlock>[];
          double yOffset = 0;
          final startX = strokeBounds.left + 20;
          final startY = strokeBounds.top;
          for (final line in result.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            blocks.add(RecognizedBlock(
              text: trimmed,
              position: Offset(startX, startY + yOffset),
              scale: 1.0,
            ));
            yOffset += 48;
          }
          setState(() {
            _currentPage.recognizedText = result;
            _currentPage.recognizedBlocks = blocks;
            _showRecognitionPanel = true;
          });
        }
      }
    } catch (e) {
      debugPrint("识别失败: $e");
      if (mounted) {
        setState(() => _currentPage.recognizedText = '识别出错: $e');
      }
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  Future<void> _analyzeFormula(String formula) async {
    setState(() => _analyzingFormula = formula);
    try {
      final result = await _formulaService.analyze(formula);
      if (mounted) {
        _showAnalysisResult(formula, result.explanation, result.visualization);
      }
    } catch (e) {
      if (mounted) {
        _showAnalysisResult(formula, '分析出错: $e', '');
      }
    } finally {
      if (mounted) setState(() => _analyzingFormula = null);
    }
  }

  void _showAnalysisResult(String formula, String explanation, String visualization) {
    _analysisCache[formula] = _FormulaAnalysis(
      formula: formula,
      explanation: explanation,
      visualization: visualization,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FormulaAnalysisSheet(
        formula: formula,
        explanation: explanation,
        visualization: visualization,
        cs: Theme.of(context).colorScheme,
      ),
    );
  }

  // 参考 principia InteractiveBadge: 每行公式旁边的分析按钮
  Widget _buildFormulaRow(String line) {
    final isLatex = line.contains(r'\') || line.contains('^') ||
        line.contains('_') || line.contains('{') || line.contains('}');
    final isAnalyzing = _analyzingFormula == line;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: isLatex
                ? Math.tex(
                    line,
                    textStyle: const TextStyle(fontSize: 16),
                    onErrorFallback: (err) => Text(line,
                        style: const TextStyle(fontSize: 14, color: Colors.blue)),
                  )
                : Text(line, style: const TextStyle(fontSize: 16)),
          ),
          if (isLatex && _enableVisualization)
            GestureDetector(
              onTap: isAnalyzing ? null : () => _analyzeFormula(line),
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (!isAnalyzing)
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                  ],
                ),
                child: isAnalyzing
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : Icon(Icons.auto_awesome, size: 12, color: cs.primary),
              ),
            ),
        ],
      ),
    );
  }

  void _showTitleEditDialog() {
    final titleController = TextEditingController(
      text: widget.note?.title ?? '手写笔记',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('笔记标题'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入笔记标题', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doSave(titleController.text.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _doSave(String title) {
    if (title.isEmpty) {
      title = '手写笔记 ${DateTime.now().toString().substring(0, 16)}';
    }
    final saveData = {'pages': _pages.map((p) => p.toJson()).toList()};
    final note = Note(
      title: title,
      content: jsonEncode(saveData),
      createTime: widget.note?.createTime ?? DateTime.now(),
      updateTime: DateTime.now(),
      noteType: 'handwriting',
      imagePaths: widget.note?.imagePaths ?? [],
    );
    Navigator.pop(context, note);
  }

  Future<void> _exportText() async {
    if (_currentPage.strokes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前页没有笔迹可导出')));
      return;
    }
    try {
      // 捕获画布为 PNG
      final RenderRepaintBoundary boundary =
          _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('图片转换失败');

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName = 'handwriting_${DateTime.now().millisecondsSinceEpoch}.png';
      final File file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        await Share.shareXFiles(
          <XFile>[XFile(file.path, mimeType: 'image/png')],
          subject: '手写笔记',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  ColorScheme get cs => Theme.of(context).colorScheme;

  void _autoSaveAndPop() {
    bool hasContent = _pages.any((page) => page.strokes.isNotEmpty);
    if (!hasContent) {
      Navigator.pop(context);
      return;
    }
    final title = (widget.note?.title.isNotEmpty == true)
        ? widget.note!.title
        : '手写笔记 ${DateTime.now().toString().substring(0, 16)}';
    final saveData = {'pages': _pages.map((p) => p.toJson()).toList()};
    final note = Note(
      title: title,
      content: jsonEncode(saveData),
      createTime: widget.note?.createTime ?? DateTime.now(),
      updateTime: DateTime.now(),
      noteType: 'handwriting',
      imagePaths: widget.note?.imagePaths ?? [],
    );
    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _autoSaveAndPop();
      },
      child: Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text("手写笔记 (${_currentPageIndex + 1}/${_pages.length})",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        actions: [
          // 右上角识别面板开关
          if (_currentPage.recognizedText.isNotEmpty)
            IconButton(
              icon: Icon(
                _showRecognitionPanel ? Icons.visibility_off : Icons.visibility,
                color: cs.primary,
              ),
              tooltip: _showRecognitionPanel ? "关闭识别面板" : "打开识别面板",
              onPressed: () {
                setState(() => _showRecognitionPanel = !_showRecognitionPanel);
              },
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: "AI识别",
            onPressed: _currentPage.strokes.isEmpty ? null : _recognizeHandwriting,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: "导出图片",
            onPressed: _exportText,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: "保存",
            onPressed: _showTitleEditDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 主画布区域
          Column(
            children: [
              Expanded(child: _buildCanvas()),
              _buildToolbar(),
            ],
          ),
          // 可拖动识别面板（从底部弹出）
          if (_showRecognitionPanel && _currentPage.recognizedText.isNotEmpty)
            _buildDraggablePanel(),
        ],
      ),
      ),
    );
  }

  // 可拖动的识别面板
  Widget _buildDraggablePanel() {
    return DraggableScrollableSheet(
      controller: _panelController,
      initialChildSize: _isPanelCollapsed ? 0.08 : 0.35,
      minChildSize: 0.08,
      maxChildSize: 0.75,
      snap: true,
      snapSizes: const [0.08, 0.35, 0.75],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // 拖动手柄 + 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // 拖动指示条
                    Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Text('识别结果',
                                style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface,
                                )),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 收起/展开按钮
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isPanelCollapsed = !_isPanelCollapsed;
                                  if (_isPanelCollapsed) {
                                    _panelController.animateTo(
                                      0.08,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  } else {
                                    _panelController.animateTo(
                                      0.35,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isPanelCollapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 20, color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // 可视化开关（仅展开时显示）
                            if (!_isPanelCollapsed)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('动图', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                  SizedBox(
                                    height: 24,
                                    child: Switch(
                                      value: _enableVisualization,
                                      onChanged: (v) => setState(() => _enableVisualization = v),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(width: 4),
                            // 关闭面板
                            GestureDetector(
                              onTap: () => setState(() {
                                _showRecognitionPanel = false;
                                _isPanelCollapsed = false;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 内容区域（收起时隐藏）
              if (!_isPanelCollapsed)
                Expanded(
                  child: _isRecognizing
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: _buildRecognizedContent(_currentPage.recognizedText),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvas() {
    return Container(
      color: cs.surfaceContainerLowest,
      margin: const EdgeInsets.all(8),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: cs.surfaceContainerLowest)),
            // 左侧翻页按钮
            if (_pages.length > 1)
              Positioned(
                left: 0,
                top: 0,
                bottom: 40,
                child: Center(
                  child: GestureDetector(
                    onTap: _currentPageIndex > 0 ? () => _goToPage(_currentPageIndex - 1) : null,
                    child: Container(
                      width: 32, height: 48,
                      decoration: BoxDecoration(
                        color: _currentPageIndex > 0
                            ? cs.primary.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                      ),
                      child: Icon(
                        Icons.chevron_left,
                        color: _currentPageIndex > 0 ? cs.primary : Colors.grey.withValues(alpha: 0.3),
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            // 右侧翻页按钮
            if (_pages.length > 1)
              Positioned(
                right: 0,
                top: 0,
                bottom: 40,
                child: Center(
                  child: GestureDetector(
                    onTap: _currentPageIndex < _pages.length - 1
                        ? () => _goToPage(_currentPageIndex + 1) : null,
                    child: Container(
                      width: 32, height: 48,
                      decoration: BoxDecoration(
                        color: _currentPageIndex < _pages.length - 1
                            ? cs.primary.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: _currentPageIndex < _pages.length - 1
                            ? cs.primary : Colors.grey.withValues(alpha: 0.3),
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54, borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentPageIndex + 1} / ${_pages.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8 + _paperOffset.dx, top: 8 + _paperOffset.dy,
              child: Transform.scale(
                scale: _scale, alignment: Alignment.topLeft,
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: Container(
                    width: _paperSize.width, height: _paperSize.height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10, offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: CustomPaint(
                        painter: _BackgroundPainter(
                          backgroundType: _currentPage.background,
                          spacing: _currentPage.bgSpacing,
                        ),
                        foregroundPainter: _StrokePainter(
                          strokes: _currentPage.strokes,
                          currentPoints: _currentPage.currentPoints,
                          currentColor: _activeColor,
                          currentWidth: _activeWidth,
                        ),
                        size: _paperSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 浮动 KaTeX 识别卡片（在画布上层，独立拖动）
            if (_currentPage.recognizedBlocks.isNotEmpty)
              ..._buildFloatingBlocks(),
            // 右上角面板开关浮钮
            if (!_showRecognitionPanel && _currentPage.recognizedText.isNotEmpty)
              Positioned(
                top: 8, right: 8,
                child: FloatingActionButton.small(
                  heroTag: 'panel_toggle',
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  onPressed: () => setState(() => _showRecognitionPanel = true),
                  child: const Icon(Icons.auto_awesome, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecognizedContent(String text) {
    List<Widget> widgets = [];
    for (String line in text.split('\n')) {
      line = line.trim();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      widgets.add(_buildFormulaRow(line));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  List<Widget> _buildFloatingBlocks() {
    return _currentPage.recognizedBlocks.asMap().entries.map((entry) {
      final block = entry.value;
      final isLatex = block.text.contains(r'\') || block.text.contains('^') ||
          block.text.contains('_') || block.text.contains('{');
      final screenX = 8 + _paperOffset.dx + block.position.dx * _scale;
      final screenY = 8 + _paperOffset.dy + block.position.dy * _scale;

      return Positioned(
        left: screenX,
        top: screenY,
        child: Transform.scale(
          scale: _scale * block.scale,
          alignment: Alignment.topLeft,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                block.position = Offset(
                  block.position.dx + details.delta.dx / _scale,
                  block.position.dy + details.delta.dy / _scale,
                );
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8, offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isLatex
                  ? Math.tex(
                      block.text,
                      textStyle: const TextStyle(fontSize: 16),
                      onErrorFallback: (err) => Text(block.text,
                          style: const TextStyle(fontSize: 14, color: Colors.blue)),
                    )
                  : Text(block.text, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            _buildModeBtn(Icons.edit, '写字', CanvasMode.write),
            const SizedBox(width: 4),
            _buildModeBtn(Icons.auto_fix_high, '橡皮', CanvasMode.eraser),
            const SizedBox(width: 4),
            _buildModeBtn(Icons.pan_tool, '拖动', CanvasMode.pan),
            _divider(),
            IconButton(
              icon: Icon(
                _currentPage.background == PaperBackground.blank ? Icons.check_box_outline_blank :
                _currentPage.background == PaperBackground.lined ? Icons.view_agenda :
                Icons.grid_on,
                size: 22,
              ),
              tooltip: "背景类型",
              onPressed: _cycleBackground,
            ),
            if (_currentPage.background != PaperBackground.blank)
              InkWell(
                onTap: () {
                  double next = _currentPage.bgSpacing >= 60 ? 20 : _currentPage.bgSpacing + 20;
                  setState(() => _currentPage.bgSpacing = next);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer, borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('间距${_currentPage.bgSpacing.toInt()}',
                      style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
                ),
              ),
            _divider(),
            IconButton(icon: const Icon(Icons.add_box_outlined, size: 22), tooltip: "添加纸张", onPressed: _addPage),
            _divider(),
            if (_canvasMode != CanvasMode.eraser) ...[
              _buildPenBtn(2.0, "细"),
              _buildPenBtn(4.0, "中"),
              _buildPenBtn(8.0, "粗"),
              _divider(),
            ],
            IconButton(icon: const Icon(Icons.undo, size: 22), tooltip: "撤销", onPressed: _undo),
            IconButton(icon: const Icon(Icons.delete_outline, size: 22), tooltip: "清空", onPressed: _clear),
            _divider(),
            if (_canvasMode != CanvasMode.eraser) ...[
              _buildColorPaletteBtn(),
              const SizedBox(width: 4),
            ],
          ]),
        ),
      ),
    );
  }

  void _cycleBackground() {
    setState(() {
      final types = PaperBackground.values;
      int idx = types.indexOf(_currentPage.background);
      _currentPage.background = types[(idx + 1) % types.length];
    });
  }

  Widget _divider() => Container(
        width: 1, height: 32, color: cs.outlineVariant,
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );

  Widget _buildModeBtn(IconData icon, String label, CanvasMode mode) {
    final isSelected = _canvasMode == mode;
    return InkWell(
      onTap: () => _toggleMode(mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: isSelected ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            fontSize: 11, color: isSelected ? cs.primary : cs.onSurfaceVariant,
          )),
        ]),
      ),
    );
  }

  Widget _buildPenBtn(double width, String label) {
    final isSelected = _strokeWidth == width;
    return InkWell(
      onTap: () => setState(() => _strokeWidth = width),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
        )),
      ),
    );
  }

  Widget _buildColorPaletteBtn() {
    return InkWell(
      onTap: () => _showRingColorPicker(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _selectedColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.palette, size: 16, color: _selectedColor.computeLuminance() > 0.5 ? Colors.black : Colors.white),
          const SizedBox(width: 4),
          Text('调色盘', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: _selectedColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          )),
        ]),
      ),
    );
  }

  void _showRingColorPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          child: RingColorPicker(
            initialColor: _selectedColor,
            onColorChanged: (color) {
              setState(() => _selectedColor = color);
            },
            onConfirm: () {
              Navigator.pop(ctx);
            },
            colorScheme: cs,
          ),
        );
      },
    );
  }
}

// 公式分析结果
class _FormulaAnalysis {
  final String formula;
  final String explanation;
  final String visualization;
  _FormulaAnalysis({required this.formula, required this.explanation, required this.visualization});
}

// 公式分析弹窗（参考 principia InteractiveBadge）
class _FormulaAnalysisSheet extends StatefulWidget {
  final String formula;
  final String explanation;
  final String visualization;
  final ColorScheme cs;

  const _FormulaAnalysisSheet({
    required this.formula,
    required this.explanation,
    required this.visualization,
    required this.cs,
  });

  @override
  State<_FormulaAnalysisSheet> createState() => _FormulaAnalysisSheetState();
}

class _FormulaAnalysisSheetState extends State<_FormulaAnalysisSheet> {
  late WebViewController _webController;

  @override
  void initState() {
    super.initState();
    if (widget.visualization.isNotEmpty) {
      _initWebView();
    }
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1A2E))
      ..loadHtmlString(_buildVizHtml());
  }

  void _openFullScreenViz() {
    final fullScreenController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1A2E))
      ..loadHtmlString(_buildVizHtml());

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          appBar: AppBar(
            title: Text(widget.formula, style: const TextStyle(fontSize: 14)),
            backgroundColor: const Color(0xFF1A1A2E),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: WebViewWidget(controller: fullScreenController),
        ),
      ),
    );
  }

  String _buildVizHtml() {
    return '''
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script src="https://cdn.plot.ly/plotly-2.27.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
  body { margin: 0; overflow: hidden; background: #1A1A2E; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; font-family: sans-serif; }
</style>
</head><body>
${widget.visualization}
</body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('公式可视化分析',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 内容
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 原公式
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('原始公式', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Math.tex(
                            widget.formula,
                            textStyle: TextStyle(fontSize: 18, color: cs.onSurface),
                            onErrorFallback: (err) => SelectableText(widget.formula,
                                style: TextStyle(fontSize: 14, color: cs.onSurface)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // AI 解释（Markdown 渲染为简单文本）
                    if (widget.explanation.isNotEmpty) ...[
                      Text('AI 解析', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                        ),
                        child: _buildMarkdownContent(widget.explanation, cs),
                      ),
                    ],
                    // 可视化
                    if (widget.visualization.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text('交互可视化', style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: cs.tertiary)),
                          ),
                          GestureDetector(
                            onTap: () => _openFullScreenViz(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.fullscreen, size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text('全屏', style: TextStyle(fontSize: 11, color: cs.primary)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 350,
                          child: WebViewWidget(controller: _webController),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Markdown + KaTeX 渲染（支持粗体、$...$ 内联公式、$$...$$ 块级公式）
  Widget _buildMarkdownContent(String text, ColorScheme cs) {
    final lines = text.split('\n');
    final List<Widget> widgets = [];
    bool inDisplayMath = false;
    String displayMathBuffer = '';

    for (int li = 0; li < lines.length; li++) {
      String line = lines[li].trim();

      // 处理 $$...$$ 块级公式（可能跨行）
      if (line.startsWith(r'$$') && line.endsWith(r'$$') && line.length > 4) {
        // 单行 $$...$$
        final formula = line.substring(2, line.length - 2).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Math.tex(
            formula,
            textStyle: TextStyle(fontSize: 14, color: cs.onSurface),
            onErrorFallback: (err) => Text(formula,
                style: TextStyle(fontSize: 14, color: cs.onSurface)),
          ),
        ));
        continue;
      }
      if (line.startsWith(r'$$')) {
        inDisplayMath = true;
        displayMathBuffer = line.substring(2);
        continue;
      }
      if (inDisplayMath && line.endsWith(r'$$')) {
        displayMathBuffer += '\n${line.substring(0, line.length - 2)}';
        final formula = displayMathBuffer.trim();
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Math.tex(
            formula,
            textStyle: TextStyle(fontSize: 14, color: cs.onSurface),
            onErrorFallback: (err) => Text(formula,
                style: TextStyle(fontSize: 14, color: cs.onSurface)),
          ),
        ));
        inDisplayMath = false;
        displayMathBuffer = '';
        continue;
      }
      if (inDisplayMath) {
        displayMathBuffer += '\n$line';
        continue;
      }
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // 解析行内混合内容：$...$ 公式 + 普通文本 + **粗体**
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _buildInlineMixed(line, cs),
      ));
    }

    // 未闭合的公式块，按普通文本处理
    if (inDisplayMath && displayMathBuffer.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(displayMathBuffer.trim(),
            style: TextStyle(fontSize: 14, color: cs.onSurface)),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  // 解析单行中的内联 $...$ 和 **粗体**
  Widget _buildInlineMixed(String line, ColorScheme cs) {
    final List<InlineSpan> spans = [];
    int i = 0;
    while (i < line.length) {
      // 匹配 $...$ 内联公式
      if (line[i] == r'$') {
        final end = line.indexOf(r'$', i + 1);
        if (end != -1) {
          final formula = line.substring(i + 1, end);
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              formula,
              textStyle: TextStyle(fontSize: 14, color: cs.onSurface),
              onErrorFallback: (err) => Text(formula,
                  style: TextStyle(fontSize: 14, color: cs.onSurface)),
            ),
          ));
          i = end + 1;
          continue;
        }
      }
      // 匹配 **粗体**
      if (line.substring(i).startsWith('**')) {
        final end = line.indexOf('**', i + 2);
        if (end != -1) {
          final boldText = line.substring(i + 2, end);
          spans.add(TextSpan(
            text: boldText,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
          ));
          i = end + 2;
          continue;
        }
      }
      // 普通文本：收集到下一个特殊标记
      int next = line.length;
      final nextDollar = line.indexOf(r'$', i);
      if (nextDollar != -1) next = nextDollar;
      final nextBold = line.indexOf('**', i);
      if (nextBold != -1 && nextBold < next) next = nextBold;
      spans.add(TextSpan(
        text: line.substring(i, next),
        style: TextStyle(fontSize: 14, color: cs.onSurface),
      ));
      i = next;
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class _BackgroundPainter extends CustomPainter {
  final PaperBackground backgroundType;
  final double spacing;

  _BackgroundPainter({required this.backgroundType, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundType == PaperBackground.blank) return;
    final paint = Paint()
      ..color = const Color(0xFFD0E0F0)
      ..strokeWidth = 0.5;
    if (backgroundType == PaperBackground.lined) {
      double y = spacing;
      while (y < size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        y += spacing;
      }
    } else if (backgroundType == PaperBackground.grid) {
      double y = spacing;
      while (y < size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        y += spacing;
      }
      double x = spacing;
      while (x < size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        x += spacing;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      backgroundType != oldDelegate.backgroundType || spacing != oldDelegate.spacing;
}

class _StrokePainter extends CustomPainter {
  final List<HandwritingStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  _StrokePainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawPath(canvas, stroke.points, paint);
    }
    if (currentPoints.isNotEmpty) {
      final paint = Paint()
        ..color = currentColor
        ..strokeWidth = currentWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawPath(canvas, currentPoints, paint);
    }
  }

  void _drawPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      canvas.drawPoints(ui.PointMode.points, points, paint);
      return;
    }
    if (points.length == 2) {
      canvas.drawLine(points[0], points[1], paint);
      return;
    }
    final smoothed = _catmullRomSmooth(points);
    final path = Path();
    path.moveTo(smoothed.first.dx, smoothed.first.dy);
    for (int i = 1; i < smoothed.length; i++) {
      path.lineTo(smoothed[i].dx, smoothed[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  List<Offset> _catmullRomSmooth(List<Offset> points) {
    final result = <Offset>[points.first];
    final pts = [points.first, ...points, points.last];
    for (int i = 0; i < pts.length - 3; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final p2 = pts[i + 2];
      final p3 = pts[i + 3];
      for (int j = 1; j <= 8; j++) {
        final t = j / 8.0;
        final t2 = t * t;
        final t3 = t2 * t;
        result.add(Offset(
          0.5 * (2 * p1.dx + (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
          0.5 * (2 * p1.dy + (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
        ));
      }
    }
    result.add(points.last);
    return result;
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
