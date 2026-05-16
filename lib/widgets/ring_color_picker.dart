import 'dart:math';
import 'package:flutter/material.dart';

class RingColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onConfirm;
  final ColorScheme colorScheme;

  const RingColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    required this.onConfirm,
    required this.colorScheme,
  });

  @override
  State<RingColorPicker> createState() => _RingColorPickerState();
}

class _RingColorPickerState extends State<RingColorPicker> {
  late double _hue;
  late double _saturation;
  double _brightness = 1.0;
  Color _currentColor = Colors.black;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue / 360;
    _saturation = hsv.saturation;
    _brightness = hsv.value;
    _currentColor = widget.initialColor;
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
      _hue = angle;
      _saturation = dist.clamp(0.0, 1.0);
      _currentColor = _hsvToColor(_hue, _saturation, _brightness);
      widget.onColorChanged(_currentColor);
    });
  }

  @override
  Widget build(BuildContext context) {
    const double wheelSize = 260;
    final cs = widget.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('取色器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: wheelSize, height: wheelSize,
              child: GestureDetector(
                onTapDown: (d) => _onPickerTap(d.localPosition, const Size(wheelSize, wheelSize)),
                onPanUpdate: (d) => _onPickerTap(d.localPosition, const Size(wheelSize, wheelSize)),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RingWheelPainter(),
                    child: Center(
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: _currentColor,
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
              Text('明度', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Expanded(
                child: Slider(
                  value: _brightness, min: 0, max: 1,
                  activeColor: _currentColor,
                  onChanged: (v) {
                    setState(() {
                      _brightness = v;
                      _currentColor = _hsvToColor(_hue, _saturation, _brightness);
                      widget.onColorChanged(_currentColor);
                    });
                  },
                ),
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant),
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
                  color: _currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant, width: 2),
                  boxShadow: [BoxShadow(color: _currentColor.withValues(alpha: 0.4), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '#${(_currentColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: cs.onSurface),
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

class _RingWheelPainter extends CustomPainter {
  static const List<Color> _hueStops = [
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
        ..shader = const SweepGradient(colors: _hueStops).createShader(rect),
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
  bool shouldRepaint(covariant _RingWheelPainter oldDelegate) => false;
}
