import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mathmate/models/user_radar_profile.dart';
import 'package:mathmate/services/ability_score_service.dart';

/// 初始能力自评页面
///
/// 用户通过点击六边形雷达图上的 5 个档位点，或使用下方的档位按钮，
/// 为 6 个数学能力维度分别设定初始水平（1~5 档）。
class AbilityAssessmentPage extends StatefulWidget {
  /// 是否为从设置页进入（回退行为不同）
  final bool isFromSettings;

  /// 完成自评后的下一步页面
  final Widget? nextPage;

  const AbilityAssessmentPage({
    super.key,
    this.isFromSettings = false,
    this.nextPage,
  });

  @override
  State<AbilityAssessmentPage> createState() => _AbilityAssessmentPageState();
}

class _AbilityAssessmentPageState extends State<AbilityAssessmentPage> {
  /// 六个维度的当前档位（1~5），初始全部为 3（中等）
  late List<int> _levels;
  final AbilityScoreService _abilityService = AbilityScoreService();

  /// 当前有效的维度名称列表（根据年级动态确定）
  List<String> get _dimNames => _abilityService.currentDimensionNames;

  @override
  void initState() {
    super.initState();
    // 如果已有自评数据则加载，否则初始化为 3
    final UserRadarProfile? existing = _abilityService.selfAssessment;
    if (existing != null) {
      _levels = existing.scores.map((double s) => s.round()).toList();
    } else {
      _levels = List<int>.filled(_dimNames.length, 3);
    }
  }

  UserRadarProfile _buildProfile() {
    return UserRadarProfile(
      scores: _levels.map((int l) => l.toDouble()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('能力自评'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.primary,
        actions: <Widget>[
          TextButton(
            onPressed: () => _onConfirm(),
            child: const Text(
              '跳过',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: <Widget>[
              // 说明文字
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '评估你的数学能力水平',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '点击雷达图上的圆点或使用下方档位按钮，为每个维度选择 1~5 档。\n后续答题数据将动态修正这些评分。',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 交互式六边形雷达图
              _buildInteractiveHexagon(cs),
              const SizedBox(height: 18),

              // 维度档位按钮行
              ..._buildDimensionRows(cs),
              const SizedBox(height: 24),

              // 确认按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => _onConfirm(),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    '确认并继续',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建交互式六边形（可点击档位点）
  Widget _buildInteractiveHexagon(ColorScheme cs) {
    return GestureDetector(
      onTapDown: (TapDownDetails details) =>
          _handleHexagonTap(details.localPosition),
      child: Center(
        child: CustomPaint(
          size: const Size(300, 300),
          painter: _InteractiveHexagonPainter(
            levels: _levels,
            dimNames: _dimNames,
            colorScheme: cs,
          ),
        ),
      ),
    );
  }

  /// 处理六边形点击——定位最近的轴和档位
  void _handleHexagonTap(Offset tapPos) {
    const double size = 300;
    final Offset center = const Offset(size / 2, size / 2);
    final double radius = math.min(size, size) / 2 - 36;

    final double dx = tapPos.dx - center.dx;
    final double dy = tapPos.dy - center.dy;
    final double dist = math.sqrt(dx * dx + dy * dy);
    final double angle = math.atan2(dy, dx);

    // 找到最近的角度轴（6 条轴）
    int closestAxis = 0;
    double minAngleDiff = double.infinity;
    for (int i = 0; i < 6; i++) {
      final double axisAngle = -math.pi / 2 + 2 * math.pi * i / 6;
      double diff = (angle - axisAngle).abs();
      if (diff > math.pi) diff = 2 * math.pi - diff;
      if (diff < minAngleDiff) {
        minAngleDiff = diff;
        closestAxis = i;
      }
    }

    // 仅当点击在轴附近（±25°）时才响应
    if (minAngleDiff > 0.44) return; // ~25°

    // 将距离映射为档位 1~5
    final double gridUnit = radius / 5.0;
    int level = ((dist / gridUnit) + 0.5).round().clamp(1, 5);

    setState(() {
      _levels[closestAxis] = level;
    });
  }

  /// 构建 6 个维度的档位选择行
  List<Widget> _buildDimensionRows(ColorScheme cs) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < _dimNames.length; i++) {
      rows.add(_buildDimensionRow(cs, i));
      if (i < 5) rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  Widget _buildDimensionRow(ColorScheme cs, int index) {
    final String name = _dimNames[index];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          const Spacer(),
          ...List<Widget>.generate(5, (int j) {
            final int level = j + 1;
            final bool selected = _levels[index] == level;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () => setState(() => _levels[index] = level),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                    border: selected
                        ? null
                        : Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                    boxShadow: selected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _onConfirm() async {
    await _abilityService.saveSelfAssessment(_buildProfile());

    if (!mounted) return;

    if (widget.isFromSettings) {
      Navigator.of(context).pop();
    } else if (widget.nextPage != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => widget.nextPage!),
        (Route<dynamic> route) => false,
      );
    } else {
      Navigator.of(context).pop();
    }
  }
}

/// 交互式六边形自评图绘制器
///
/// 绘制网格、轴线、5 档位圆点、当前选择的高亮多边形和选中档位高亮。
class _InteractiveHexagonPainter extends CustomPainter {
  final List<int> levels;
  final List<String> dimNames;
  final ColorScheme colorScheme;

  _InteractiveHexagonPainter({
    required this.levels,
    required this.dimNames,
    required this.colorScheme,
  });

  static const int _sides = 6;
  static const int _gridLevels = 5;

  double _angle(int i) => -math.pi / 2 + 2 * math.pi * i / _sides;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 36;

    _drawGrid(canvas, center, radius);
    _drawAxes(canvas, center, radius);
    _drawLevelDots(canvas, center, radius);
    _drawCurrentPolygon(canvas, center, radius);
  }

  void _drawGrid(Canvas canvas, Offset center, double radius) {
    final Paint paint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int level = 1; level <= _gridLevels; level++) {
      final double r = radius * level / _gridLevels;
      canvas.drawPath(_buildHexPath(center, r), paint);
    }
  }

  void _drawAxes(Canvas canvas, Offset center, double radius) {
    final Paint paint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < _sides; i++) {
      final double angle = _angle(i);
      canvas.drawLine(
        center,
        Offset(center.dx + radius * math.cos(angle),
               center.dy + radius * math.sin(angle)),
        paint,
      );

      // 维度标签
      final String label = i < dimNames.length
          ? dimNames[i]
          : '?';
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final double lr = radius + 22;
      double lx = center.dx + lr * math.cos(angle) - tp.width / 2;
      double ly = center.dy + lr * math.sin(angle) - tp.height / 2;
      if (angle < -2.5 || angle > 2.5) {
        ly -= 6;
      } else if (angle > -0.7 && angle < 0.7) {
        ly += 6;
      }
      tp.paint(canvas, Offset(lx, ly));
    }
  }

  /// 在每条轴的 5 个档位处绘制圆点（供用户点击参考）
  void _drawLevelDots(Canvas canvas, Offset center, double radius) {
    for (int i = 0; i < _sides; i++) {
      final double angle = _angle(i);
      final int selectedLevel = i < levels.length ? levels[i] : 3;

      for (int lv = 1; lv <= _gridLevels; lv++) {
        final double r = radius * lv / _gridLevels;
        final Offset pos = Offset(
          center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle),
        );

        final bool isSelected = lv == selectedLevel;
        final Paint dotPaint = Paint()
          ..color = isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(pos, isSelected ? 7 : 4, dotPaint);

        if (isSelected) {
          // 选中档位的外圈光晕
          final Paint glowPaint = Paint()
            ..color = colorScheme.primary.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(pos, 12, glowPaint);
        }
      }
    }
  }

  /// 绘制当前选定档位围成的多边形
  void _drawCurrentPolygon(Canvas canvas, Offset center, double radius) {
    // 填充
    final Paint fillPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final Path path = Path();
    for (int i = 0; i < _sides; i++) {
      final double angle = _angle(i);
      final int lv = i < levels.length ? levels[i] : 3;
      final double r = radius * lv / _gridLevels;
      final Offset pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, fillPaint);

    // 描边
    final Paint strokePaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, strokePaint);
  }

  Path _buildHexPath(Offset center, double radius) {
    final Path path = Path();
    for (int i = 0; i < _sides; i++) {
      final double angle = _angle(i);
      final Offset pt = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) { path.moveTo(pt.dx, pt.dy); }
      else { path.lineTo(pt.dx, pt.dy); }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _InteractiveHexagonPainter oldDelegate) {
    return oldDelegate.levels != levels || oldDelegate.dimNames != dimNames;
  }
}
