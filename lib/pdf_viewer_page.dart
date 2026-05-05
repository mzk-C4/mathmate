import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'note_handwriting_editor_page.dart';

enum _PdfMode { view, write, eraser }

class PdfViewerPage extends StatefulWidget {
  final String pdfPath;
  final String title;

  const PdfViewerPage({super.key, required this.pdfPath, required this.title});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final WebViewController _controller;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;

  final Map<int, List<HandwritingStroke>> _pageStrokes = {};
  List<Offset> _currentPoints = [];
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.0;
  _PdfMode _mode = _PdfMode.view;

  List<HandwritingStroke> get _currentStrokes =>
      _pageStrokes.putIfAbsent(_currentPage, () => []);

  @override
  void initState() {
    super.initState();
    _initPdfViewer();
  }

  void _initPdfViewer() {
    final file = File(widget.pdfPath);
    final bytes = file.readAsBytesSync();
    final base64Pdf = base64Encode(bytes);

    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #525659; display: flex; flex-direction: column; align-items: center; overflow-y: auto; }
    canvas { margin: 10px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.3); }
    .page-container { display: flex; flex-direction: column; align-items: center; padding: 20px 0; }
  </style>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"></script>
</head>
<body>
  <div class="page-container" id="container"></div>
  <script>
    pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
    var pdfDoc = null;
    var currentPage = 1;
    var totalPages = 0;
    var scale = 1.0;

    function renderPage(num) {
      pdfDoc.getPage(num).then(function(page) {
        var container = document.getElementById('container');
        var canvas = document.createElement('canvas');
        canvas.id = 'page-' + num;
        canvas.style.width = '95%';
        canvas.style.maxWidth = '800px';
        var ctx = canvas.getContext('2d');
        var viewport = page.getViewport({scale: scale});
        canvas.height = viewport.height;
        canvas.width = viewport.width;
        container.appendChild(canvas);

        var maxWidth = Math.min(window.innerWidth * 0.95, 800);
        if (viewport.width > maxWidth) {
          var ratio = maxWidth / viewport.width;
          canvas.style.width = maxWidth + 'px';
          canvas.style.height = (viewport.height * ratio) + 'px';
        }

        page.render({canvasContext: ctx, viewport: viewport}).promise.then(function() {
          window.flutterMessage.postMessage(JSON.stringify({
            type: 'pageRendered',
            page: num,
            total: totalPages
          }));
        });
      });
    }

    function loadPdf(base64Data) {
      var raw = atob(base64Data);
      var uint8Array = new Uint8Array(raw.length);
      for (var i = 0; i < raw.length; i++) { uint8Array[i] = raw.charCodeAt(i); }
      pdfjsLib.getDocument({data: uint8Array}).promise.then(function(pdf) {
        pdfDoc = pdf;
        totalPages = pdf.numPages;
        window.flutterMessage.postMessage(JSON.stringify({
          type: 'loaded',
          total: totalPages
        }));
        renderPage(currentPage);
      });
    }

    function goToPage(num) {
      if (num < 1 || num > totalPages) return;
      currentPage = num;
      document.getElementById('container').innerHTML = '';
      renderPage(currentPage);
    }

    document.addEventListener('DOMContentLoaded', function() {
      loadPdf('$base64Pdf');
    });
  </script>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF525659))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..addJavaScriptChannel(
        'flutterMessage',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            final match = RegExp(r'\{.*\}').firstMatch(msg.message);
            final data = match?.group(0) ?? msg.message;
            final map = jsonDecode(data) as Map<String, dynamic>;
            if (map['type'] == 'loaded' || map['type'] == 'pageRendered') {
              if (mounted) {
                setState(() {
                  _totalPages = (map['total'] as num?)?.toInt() ?? 1;
                  if (map['page'] != null) {
                    _currentPage = (map['page'] as num).toInt();
                  }
                  _isLoading = false;
                });
              }
            }
          } catch (_) {}
        },
      )
      ..loadHtmlString(html);
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages) return;
    setState(() => _currentPage = page);
    _controller.runJavaScript('goToPage($page);');
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentPoints = [details.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentPoints.isEmpty) return;
    if (_mode == _PdfMode.eraser) {
      _eraseStrokes();
      setState(() => _currentPoints.clear());
      return;
    }
    setState(() {
      _currentStrokes.add(HandwritingStroke(
        color: _selectedColor,
        width: _strokeWidth,
        points: List.from(_currentPoints),
      ));
      _currentPoints.clear();
    });
  }

  void _undo() {
    setState(() {
      if (_currentStrokes.isNotEmpty) _currentStrokes.removeLast();
    });
  }

  void _clearPage() {
    setState(() => _currentStrokes.clear());
  }

  void _eraseStrokes() {
    final eraserPath = List<Offset>.from(_currentPoints);
    const threshold = 12.0;
    setState(() {
      _currentStrokes.removeWhere((stroke) {
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

  void _showRingColorPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          child: _PdfRingColorPicker(
            initialColor: _selectedColor,
            onColorChanged: (c) => setState(() => _selectedColor = c),
            onConfirm: () => Navigator.pop(ctx),
            cs: Theme.of(context).colorScheme,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF525659),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _PdfStrokePainter(
                          strokes: _currentStrokes,
                          currentPoints: _currentPoints,
                          currentColor: _mode == _PdfMode.eraser
                              ? Colors.grey.withValues(alpha: 0.3)
                              : _selectedColor,
                          currentWidth: _mode == _PdfMode.eraser ? 24.0 : _strokeWidth,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    if (_mode != _PdfMode.view)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                        ),
                      ),
                  ],
                ),
              ),
              _buildToolbar(cs),
              _buildPageBar(cs),
            ],
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            _buildModeBtn(Icons.visibility, '查看', _PdfMode.view, cs),
            const SizedBox(width: 4),
            _buildModeBtn(Icons.edit, '写字', _PdfMode.write, cs),
            const SizedBox(width: 4),
            _buildModeBtn(Icons.auto_fix_high, '橡皮', _PdfMode.eraser, cs),
            _divider(cs),
            if (_mode != _PdfMode.eraser) ...[
              _buildPenBtn(2.0, '细', cs),
              _buildPenBtn(4.0, '中', cs),
              _buildPenBtn(8.0, '粗', cs),
              _divider(cs),
              _buildColorBtn(cs),
              const SizedBox(width: 4),
            ],
            _divider(cs),
            IconButton(
              icon: const Icon(Icons.undo, size: 22),
              tooltip: '撤销笔画',
              onPressed: _currentStrokes.isNotEmpty ? _undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 22),
              tooltip: '清空本页标注',
              onPressed: _currentStrokes.isNotEmpty ? _clearPage : null,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Container(
        width: 1, height: 32, color: cs.outlineVariant,
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );

  Widget _buildModeBtn(IconData icon, String label, _PdfMode mode, ColorScheme cs) {
    final isSelected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
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

  Widget _buildPenBtn(double width, String label, ColorScheme cs) {
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

  Widget _buildColorBtn(ColorScheme cs) {
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
          Icon(Icons.palette, size: 16,
              color: _selectedColor.computeLuminance() > 0.5 ? Colors.black : Colors.white),
          const SizedBox(width: 4),
          Text('调色盘', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: _selectedColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
          )),
        ]),
      ),
    );
  }

  Widget _buildPageBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_currentPage / $_totalPages',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
              onPressed: _currentPage < _totalPages ? () => _goToPage(_currentPage + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfStrokePainter extends CustomPainter {
  final List<HandwritingStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  _PdfStrokePainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var stroke in strokes) {
      _drawSmoothPath(canvas, stroke.points, stroke.color, stroke.width);
    }
    if (currentPoints.isNotEmpty) {
      _drawSmoothPath(canvas, currentPoints, currentColor, currentWidth);
    }
  }

  void _drawSmoothPath(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
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
  bool shouldRepaint(covariant _PdfStrokePainter oldDelegate) => true;
}

class _PdfRingColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onConfirm;
  final ColorScheme cs;

  const _PdfRingColorPicker({
    required this.initialColor,
    required this.onColorChanged,
    required this.onConfirm,
    required this.cs,
  });

  @override
  State<_PdfRingColorPicker> createState() => _PdfRingColorPickerState();
}

class _PdfRingColorPickerState extends State<_PdfRingColorPicker> {
  late double hue;
  late double saturation;
  double brightness = 1.0;
  Color currentColor = Colors.black;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    hue = hsv.hue / 360;
    saturation = hsv.saturation;
    brightness = hsv.value;
    currentColor = widget.initialColor;
  }

  Color _hsvToColor(double h, double s, double v) {
    return HSVColor.fromAHSV(1, h * 360, s.clamp(0.0, 1.0), v.clamp(0.0, 1.0)).toColor();
  }

  void _onPickerTap(Offset localPos, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final distSq = dx * dx + dy * dy;
    final radius = size.width / 2;

    if (distSq > radius * radius) return;

    final raw = atan2(dy, dx);
    final angle = (raw < 0 ? raw + 2 * pi : raw) / (2 * pi);
    final dist = sqrt(distSq) / radius;

    setState(() {
      hue = angle;
      saturation = dist.clamp(0.0, 1.0);
      currentColor = _hsvToColor(hue, saturation, brightness);
      widget.onColorChanged(currentColor);
    });
  }

  @override
  Widget build(BuildContext context) {
    const double wheelSize = 260;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: widget.cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('取色器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: widget.cs.onSurface)),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: wheelSize, height: wheelSize,
              child: GestureDetector(
                onTapDown: (d) => _onPickerTap(d.localPosition, const Size(wheelSize, wheelSize)),
                onPanUpdate: (d) => _onPickerTap(d.localPosition, const Size(wheelSize, wheelSize)),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RingPainter2(),
                    child: Center(
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: currentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('明度', style: TextStyle(fontSize: 12, color: widget.cs.onSurfaceVariant)),
              Expanded(
                child: Slider(
                  value: brightness, min: 0, max: 1,
                  activeColor: currentColor,
                  onChanged: (v) {
                    setState(() {
                      brightness = v;
                      currentColor = _hsvToColor(hue, saturation, brightness);
                      widget.onColorChanged(currentColor);
                    });
                  },
                ),
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.cs.outlineVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.cs.outlineVariant, width: 2),
                  boxShadow: [BoxShadow(color: currentColor.withValues(alpha: 0.4), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '#${(currentColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: widget.cs.onSurface),
                ),
              ),
              ElevatedButton(
                onPressed: widget.onConfirm,
                child: const Text('确定'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RingPainter2 extends CustomPainter {
  static const List<Color> hueStops = [
    Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
    Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(center, radius,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = const SweepGradient(colors: hueStops).createShader(rect),
    );

    canvas.drawCircle(center, radius,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
          stops: [0.0, 0.99],
        ).createShader(rect),
    );

    canvas.drawCircle(center, radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter2 oldDelegate) => false;
}
