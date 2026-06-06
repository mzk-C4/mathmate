import 'dart:math' as math;

import 'package:flutter/material.dart' hide Viewport;

import 'models.dart';

/// 把 [GeometryScene] 渲染到 Canvas 的 CustomPainter。
///
/// * 通过 `super(repaint: animation)` 把 [AnimationController] 直接挂到
///   painter 上——动画 tick 自动触发重绘，不需要外层 [setState]。
/// * 数学坐标 → 像素坐标在 [mathToPixel] 中处理 Y 轴翻转。
/// * `line` 当作无限直线，与视口四边求交点裁剪后绘制。
/// * `glider` 支持吸附在圆、椭圆、双曲线上。
class GeometryPainter extends CustomPainter {
  final GeometryScene scene;
  final Animation<double>? animation;
  final Map<String, double> dragOverrides;
  final String? draggingGliderId;
  final int paintVersion;

  GeometryPainter({
    required this.scene,
    this.animation,
    this.dragOverrides = const {},
    this.draggingGliderId,
    this.paintVersion = 0,
  }) : super(repaint: animation);

  double get _animT => animation?.value ?? 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final v = scene.viewport;
    final byId = {for (final e in scene.elements) e.id: e};
    final positions = _resolvePositions(byId);

    for (final e in scene.elements) {
      if (e is CircleElement) {
        _drawCircle(canvas, size, v, e);
      } else if (e is LineElement) {
        _drawLine(canvas, size, v, e, positions, byId);
      } else if (e is PointElement) {
        _drawPoint(canvas, size, v, e, Offset(e.x, e.y));
      } else if (e is GliderElement) {
        final p = positions[e.id];
        if (p != null) _drawPoint(canvas, size, v, e, p);
      } else if (e is EllipseElement) {
        _drawEllipse(canvas, size, v, e);
      } else if (e is HyperbolaElement) {
        _drawHyperbola(canvas, size, v, e);
      } else if (e is ParabolaElement) {
        _drawParabola(canvas, size, v, e);
      }
    }
  }

  /// 计算所有"具备明确数学坐标"的图元位置（point + glider）。
  Map<String, Offset> _resolvePositions(Map<String, GeometryElement> byId) {
    final map = <String, Offset>{};
    for (final e in scene.elements) {
      if (e is PointElement) map[e.id] = Offset(e.x, e.y);
    }
    // 约束求解：覆盖有 constraint 的点的坐标
    _resolveConstraints(map, byId);
    for (final e in scene.elements) {
      if (e is GliderElement) {
        final t = dragOverrides.containsKey(e.id)
            ? dragOverrides[e.id]!
            : (e.isAnimated ? _animT : e.t);
        final pos = gliderMathPosition(e, byId, t);
        if (pos != null) map[e.id] = pos;
      }
    }
    return map;
  }

  /// 对有约束的点重新计算精确坐标。
  void _resolveConstraints(Map<String, Offset> positions, Map<String, GeometryElement> byId) {
    for (final e in scene.elements) {
      if (e is! PointElement || e.constraint == null) continue;
      final c = e.constraint!;
      Offset? resolved;
      if (c is MidpointConstraint) {
        final p1 = positions[c.pid1];
        final p2 = positions[c.pid2];
        if (p1 != null && p2 != null) {
          resolved = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        }
      } else if (c is OnSegmentConstraint) {
        final p1 = positions[c.pid1];
        final p2 = positions[c.pid2];
        if (p1 != null && p2 != null) {
          resolved = Offset(p1.dx + (p2.dx - p1.dx) * c.ratio, p1.dy + (p2.dy - p1.dy) * c.ratio);
        }
      } else if (c is OnLineConstraint) {
        final p1 = positions[c.pid1];
        final p2 = positions[c.pid2];
        if (p1 != null && p2 != null) {
          resolved = Offset(p1.dx + (p2.dx - p1.dx) * c.ratio, p1.dy + (p2.dy - p1.dy) * c.ratio);
        }
      } else if (c is IntersectionConstraint) {
        resolved = _intersectLines(positions, byId, c.lid1, c.lid2);
      }
      if (resolved != null) {
        positions[e.id] = resolved;
      }
    }
  }

  /// 计算两条直线的交点（数学坐标）。
  Offset? _intersectLines(Map<String, Offset> positions, Map<String, GeometryElement> byId, String lid1, String lid2) {
    Offset? a1, a2, b1, b2;
    final l1 = byId[lid1];
    final l2 = byId[lid2];
    if (l1 is LineElement) {
      a1 = _endpointPos(l1.p1, positions, byId);
      a2 = _endpointPos(l1.p2, positions, byId);
    }
    if (l2 is LineElement) {
      b1 = _endpointPos(l2.p1, positions, byId);
      b2 = _endpointPos(l2.p2, positions, byId);
    }
    if (a1 == null || a2 == null || b1 == null || b2 == null) return null;

    final x1 = a1.dx, y1 = a1.dy, x2 = a2.dx, y2 = a2.dy;
    final x3 = b1.dx, y3 = b1.dy, x4 = b2.dx, y4 = b2.dy;
    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-10) return null; // 平行
    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    return Offset(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }

  Offset? _endpointPos(EndpointRef ep, Map<String, Offset> positions, Map<String, GeometryElement> byId) {
    if (ep.isReference) {
      return positions[ep.refId!] ?? (_findPoint(ep.refId!, byId) != null
          ? Offset((_findPoint(ep.refId!, byId) as PointElement).x, (_findPoint(ep.refId!, byId) as PointElement).y)
          : null);
    }
    if (ep.x != null && ep.y != null) return Offset(ep.x!, ep.y!);
    return null;
  }

  PointElement? _findPoint(String id, Map<String, GeometryElement> byId) {
    final e = byId[id];
    return e is PointElement ? e : null;
  }

  /// 数学坐标 → Canvas 像素坐标，使用统一缩放系数（取 x/y 方向
  /// 中较小者）保持等比例映射，避免圆被压扁。
  static Offset mathToPixel(Offset mathPos, Size size, Viewport v) {
    final scale = math.min(size.width / v.width, size.height / v.height);
    final ox = (size.width - v.width * scale) / 2;
    final oy = (size.height - v.height * scale) / 2;
    final px = (mathPos.dx - v.xmin) * scale + ox;
    final py = (v.ymax - mathPos.dy) * scale + oy;
    return Offset(px, py);
  }

  /// 像素坐标 → 数学坐标（[mathToPixel] 的精确逆变换）。
  static Offset pixelToMath(Offset pixel, Size size, Viewport v) {
    final scale = math.min(size.width / v.width, size.height / v.height);
    final ox = (size.width - v.width * scale) / 2;
    final oy = (size.height - v.height * scale) / 2;
    final mx = (pixel.dx - ox) / scale + v.xmin;
    final my = v.ymax - (pixel.dy - oy) / scale;
    return Offset(mx, my);
  }

  /// 给定 glider 和参数 t，返回其在目标曲线上的数学坐标。
  /// 当前支持 circle / ellipse / hyperbola 三种目标类型。
  static Offset? gliderMathPosition(
    GliderElement e,
    Map<String, GeometryElement> byId,
    double t,
  ) {
    final target = byId[e.targetId];
    if (target is CircleElement) {
      final angle = 2 * math.pi * t;
      return Offset(
        target.cx + target.radius * math.cos(angle),
        target.cy + target.radius * math.sin(angle),
      );
    } else if (target is EllipseElement) {
      final angle = 2 * math.pi * t;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final cosR = math.cos(target.rotation);
      final sinR = math.sin(target.rotation);
      final xl = target.rx * cosA;
      final yl = target.ry * sinA;
      return Offset(
        target.cx + xl * cosR - yl * sinR,
        target.cy + xl * sinR + yl * cosR,
      );
    } else if (target is HyperbolaElement) {
      final tParam = (t - 0.5) * 6;
      final cosR = math.cos(target.rotation);
      final sinR = math.sin(target.rotation);
      final xl = target.a * cosh(tParam);
      final yl = target.b * sinh(tParam);
      return Offset(
        target.cx + xl * cosR - yl * sinR,
        target.cy + xl * sinR + yl * cosR,
      );
    }
    return null;
  }

  /// 给定手指数学坐标和一条曲线（circle/ellipse/hyperbola），
  /// 返回曲线上距离手指最近的点的参数 t ∈ [0, 1)。
  static double projectToCurve(
    Offset mathPos,
    GeometryElement target,
    double currentT,
  ) {
    if (target is CircleElement) {
      final dx = mathPos.dx - target.cx;
      final dy = mathPos.dy - target.cy;
      var t = math.atan2(dy, dx) / (2 * math.pi);
      if (t < 0) t += 1.0;
      return t;
    } else if (target is EllipseElement) {
      // 逆旋转到椭圆局部坐标系，角度近似
      final cosR = math.cos(-target.rotation);
      final sinR = math.sin(-target.rotation);
      final dx = mathPos.dx - target.cx;
      final dy = mathPos.dy - target.cy;
      final xl = dx * cosR - dy * sinR;
      final yl = dx * sinR + dy * cosR;
      var t = math.atan2(yl / target.ry, xl / target.rx) / (2 * math.pi);
      if (t < 0) t += 1.0;
      return t;
    } else if (target is HyperbolaElement) {
      // 逆旋转到局部坐标系
      final cosR = math.cos(-target.rotation);
      final sinR = math.sin(-target.rotation);
      final dx = mathPos.dx - target.cx;
      final dy = mathPos.dy - target.cy;
      final xl = dx * cosR - dy * sinR;
      final yl = dx * sinR + dy * cosR;

      // 确定分支：右支 xl >= a，左支 xl <= -a，带 hysteresis 防抖动
      final prevTLocal = (currentT - 0.5) * 6;
      bool wasLeft = prevTLocal < 0;
      const hysteresis = 0.05;
      bool isLeft;
      if (xl <= -target.a + hysteresis && xl >= target.a - hysteresis) {
        isLeft = wasLeft;
      } else {
        isLeft = xl <= -target.a || (xl < target.a && wasLeft);
      }

      // asinh 初值
      double tau;
      if (isLeft) {
        if (xl > -target.a) {
          tau = math.log((math.sqrt(target.a * target.a + yl * yl) - target.a) / yl.abs());
        } else {
          tau = asinh(yl / target.b);
          tau = -tau.abs();
        }
      } else {
        if (xl < target.a) {
          tau = math.log((math.sqrt(target.a * target.a + yl * yl) + target.a) / yl.abs());
        } else {
          tau = asinh(yl / target.b);
          tau = tau.abs();
        }
      }

      // 局部 21 点搜索最小距离
      const searchWindow = 0.5;
      const steps = 20;
      var bestDist = double.infinity;
      var bestTau = tau;
      for (int i = 0; i <= steps; i++) {
        final s = tau - searchWindow + 2 * searchWindow * i / steps;
        final sx = isLeft ? -target.a * cosh(s) : target.a * cosh(s);
        final sy = target.b * sinh(s);
        final dist = (xl - sx) * (xl - sx) + (yl - sy) * (yl - sy);
        if (dist < bestDist) {
          bestDist = dist;
          bestTau = s;
        }
      }

      // tau → t ∈ [0, 1)
      var t = bestTau / 6 + 0.5;
      if (t < 0) t += 1.0;
      if (t >= 1) t -= 1.0;
      return t;
    }
    return currentT;
  }

  // ------------------------- 各图元的绘制 -------------------------

  void _drawPoint(
    Canvas c,
    Size size,
    Viewport v,
    GeometryElement e,
    Offset mathPos,
  ) {
    final pixel = mathToPixel(mathPos, size, v);
    final color = _color(e, fallback: Colors.red);
    final isDragged = e is GliderElement && e.id == draggingGliderId;
    final radius = isDragged ? 6.5 : 4.5;
    if (isDragged) {
      c.drawCircle(
        pixel,
        radius + 4,
        Paint()
          ..color = Colors.blue.withAlpha(80)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    c.drawCircle(pixel, radius, Paint()..color = color);
    if (e.label != null) {
      _drawLabel(c, e.label!, pixel + const Offset(6, -16), color);
    }
  }

  void _drawCircle(Canvas c, Size size, Viewport v, CircleElement e) {
    final center = mathToPixel(Offset(e.cx, e.cy), size, v);
    final scale = math.min(size.width / v.width, size.height / v.height);
    final r = e.radius * scale;
    final paint = Paint()
      ..color = _color(e, fallback: Colors.blue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (e.style == 'dashed') {
      _drawDashedPath(
        c,
        Path()..addOval(Rect.fromCircle(center: center, radius: r)),
        paint,
      );
    } else {
      c.drawCircle(center, r, paint);
    }

    if (e.label != null) {
      _drawLabel(
        c,
        e.label!,
        center + Offset(r + 4, -8),
        _color(e, fallback: Colors.black87),
      );
    }
  }

  /// 椭圆：在数学坐标系中采样旋转椭圆上的点，再经 mathToPixel
  /// 变换到像素坐标——确保与 glider 动点位置的计算路径完全一致。
  void _drawEllipse(Canvas c, Size size, Viewport v, EllipseElement e) {
    final path = _buildEllipsePath(e, size, v);
    final paint = Paint()
      ..color = _color(e, fallback: Colors.purple)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    _drawPath(c, path, paint, e.style);

    if (e.label != null) {
      final center = mathToPixel(Offset(e.cx, e.cy), size, v);
      final rxPixel = e.rx / v.width * size.width;
      _drawLabel(
        c,
        e.label!,
        center + Offset(rxPixel + 4, -8),
        _color(e, fallback: Colors.black87),
      );
    }
  }

  Path _buildEllipsePath(EllipseElement e, Size size, Viewport v) {
    final path = Path();
    bool first = true;
    final cosR = math.cos(e.rotation);
    final sinR = math.sin(e.rotation);
    const samples = 100;
    for (int i = 0; i <= samples; i++) {
      final angle = 2 * math.pi * i / samples;
      final xl = e.rx * math.cos(angle);
      final yl = e.ry * math.sin(angle);
      final xw = e.cx + xl * cosR - yl * sinR;
      final yw = e.cy + xl * sinR + yl * cosR;
      final pixel = mathToPixel(Offset(xw, yw), size, v);
      if (first) {
        path.moveTo(pixel.dx, pixel.dy);
        first = false;
      } else {
        path.lineTo(pixel.dx, pixel.dy);
      }
    }
    path.close();
    return path;
  }

  /// 双曲线：左右开口标准型，再旋转。根据视口 AABB 推算参数 t 的范围，
  /// 分别采样右支和左支。
  void _drawHyperbola(Canvas c, Size size, Viewport v, HyperbolaElement e) {
    final localAABB = _viewportToLocalAABB(v, Offset(e.cx, e.cy), e.rotation);
    final xlMin = localAABB.left;
    final xlMax = localAABB.right;
    final ylMin = localAABB.top;
    final ylMax = localAABB.bottom;

    final paint = Paint()
      ..color = _color(e, fallback: Colors.orange)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 右支
    if (xlMax >= e.a) {
      final tLow = math.max(
        asinh(ylMin / e.b),
        -acosh(xlMax / e.a),
      );
      final tHigh = math.min(
        asinh(ylMax / e.b),
        acosh(xlMax / e.a),
      );
      if (tLow <= tHigh) {
        final path = _sampleHyperbolaBranch(
          e, tLow, tHigh, isRight: true, size: size, v: v,
        );
        if (path != null) _drawPath(c, path, paint, e.style);
      }
    }

    // 左支
    if (xlMin <= -e.a) {
      final tLow = math.max(
        asinh(ylMin / e.b),
        -acosh(-xlMin / e.a),
      );
      final tHigh = math.min(
        asinh(ylMax / e.b),
        acosh(-xlMin / e.a),
      );
      if (tLow <= tHigh) {
        final path = _sampleHyperbolaBranch(
          e, tLow, tHigh, isRight: false, size: size, v: v,
        );
        if (path != null) _drawPath(c, path, paint, e.style);
      }
    }

    if (e.label != null) {
      final center = mathToPixel(Offset(e.cx, e.cy), size, v);
      _drawLabel(c, e.label!, center + const Offset(6, 4), paint.color);
    }
  }

  Path? _sampleHyperbolaBranch(
    HyperbolaElement e,
    double tLow,
    double tHigh, {
    required bool isRight,
    required Size size,
    required Viewport v,
    int samples = 100,
  }) {
    if (tHigh < tLow || samples < 2) return null;
    final path = Path();
    bool hasFirst = false;
    final cosR = math.cos(e.rotation);
    final sinR = math.sin(e.rotation);
    final sign = isRight ? 1.0 : -1.0;

    for (int i = 0; i <= samples; i++) {
      final t = tLow + (tHigh - tLow) * i / samples;
      final xl = sign * e.a * cosh(t);
      final yl = e.b * sinh(t);
      final xw = e.cx + xl * cosR - yl * sinR;
      final yw = e.cy + xl * sinR + yl * cosR;
      final pixel = mathToPixel(Offset(xw, yw), size, v);
      if (!hasFirst) {
        path.moveTo(pixel.dx, pixel.dy);
        hasFirst = true;
      } else {
        path.lineTo(pixel.dx, pixel.dy);
      }
    }
    return hasFirst ? path : null;
  }

  /// 抛物线：标准开口向右，再旋转。根据视口 AABB 推算参数 t 的范围采样。
  void _drawParabola(Canvas c, Size size, Viewport v, ParabolaElement e) {
    double p = e.p;
    double rotation = e.rotation;
    if (p < 0) {
      p = -p;
      rotation += math.pi;
    }
    if (p < 1e-9) return;

    final localAABB = _viewportToLocalAABB(v, Offset(e.vx, e.vy), rotation);
    final xlMax = localAABB.right;
    final ylMin = localAABB.top;
    final ylMax = localAABB.bottom;

    if (xlMax < 0) return;

    final tLow = math.max(
      ylMin / (2 * p),
      -math.sqrt(math.max(0, xlMax / p)),
    );
    final tHigh = math.min(
      ylMax / (2 * p),
      math.sqrt(math.max(0, xlMax / p)),
    );
    if (tLow > tHigh) return;

    final path = Path();
    bool hasFirst = false;
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    const samples = 100;

    for (int i = 0; i <= samples; i++) {
      final t = tLow + (tHigh - tLow) * i / samples;
      final xl = p * t * t;
      final yl = 2 * p * t;
      final xw = e.vx + xl * cosR - yl * sinR;
      final yw = e.vy + xl * sinR + yl * cosR;
      final pixel = mathToPixel(Offset(xw, yw), size, v);
      if (!hasFirst) {
        path.moveTo(pixel.dx, pixel.dy);
        hasFirst = true;
      } else {
        path.lineTo(pixel.dx, pixel.dy);
      }
    }
    if (!hasFirst) return;

    final paint = Paint()
      ..color = _color(e, fallback: Colors.teal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawPath(c, path, paint, e.style);

    if (e.label != null) {
      final vertex = mathToPixel(Offset(e.vx, e.vy), size, v);
      _drawLabel(c, e.label!, vertex + const Offset(6, 4), paint.color);
    }
  }

  void _drawLine(
    Canvas c,
    Size size,
    Viewport v,
    LineElement e,
    Map<String, Offset> positions,
    Map<String, GeometryElement> byId,
  ) {
    final p1 = _resolveEndpoint(e.p1, positions, byId);
    final p2 = _resolveEndpoint(e.p2, positions, byId);
    if (p1 == null || p2 == null) return;
    if ((p1 - p2).distance < 1e-9) return;

    final clipped = _clipInfiniteLineToViewport(p1, p2, v);
    if (clipped == null) return;

    final a = mathToPixel(clipped.$1, size, v);
    final b = mathToPixel(clipped.$2, size, v);
    final paint = Paint()
      ..color = _color(e, fallback: Colors.green.shade700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (e.style == 'dashed') {
      _drawDashedPath(
        c,
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy),
        paint,
      );
    } else {
      c.drawLine(a, b, paint);
    }

    if (e.label != null) {
      _drawLabel(
        c,
        e.label!,
        (a + b) / 2 + const Offset(6, 4),
        _color(e, fallback: Colors.black87),
      );
    }
  }

  /// 端点解析：可以是字面坐标，也可以是另一图元 id 的引用。
  /// 引用 point/glider 时取其位置；引用 circle 时退化为圆心。
  Offset? _resolveEndpoint(
    EndpointRef ref,
    Map<String, Offset> positions,
    Map<String, GeometryElement> byId,
  ) {
    if (ref.isReference) {
      final pos = positions[ref.refId];
      if (pos != null) return pos;
      final el = byId[ref.refId];
      if (el is CircleElement) return Offset(el.cx, el.cy);
      return null;
    }
    return Offset(ref.x!, ref.y!);
  }

  /// 把过 (p1, p2) 的无限直线裁剪到视口矩形。
  (Offset, Offset)? _clipInfiniteLineToViewport(
    Offset p1,
    Offset p2,
    Viewport v,
  ) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final pts = <Offset>[];
    const eps = 1e-9;

    if (dx.abs() < eps) {
      final x = p1.dx;
      if (x < v.xmin - eps || x > v.xmax + eps) return null;
      pts
        ..add(Offset(x, v.ymin))
        ..add(Offset(x, v.ymax));
    } else {
      final m = dy / dx;
      final b = p1.dy - m * p1.dx;

      final yL = m * v.xmin + b;
      if (yL >= v.ymin - eps && yL <= v.ymax + eps) {
        pts.add(Offset(v.xmin, yL));
      }
      final yR = m * v.xmax + b;
      if (yR >= v.ymin - eps && yR <= v.ymax + eps) {
        pts.add(Offset(v.xmax, yR));
      }

      if (m.abs() > eps) {
        final xB = (v.ymin - b) / m;
        if (xB >= v.xmin - eps && xB <= v.xmax + eps) {
          pts.add(Offset(xB, v.ymin));
        }
        final xT = (v.ymax - b) / m;
        if (xT >= v.xmin - eps && xT <= v.xmax + eps) {
          pts.add(Offset(xT, v.ymax));
        }
      }
    }

    final uniq = <Offset>[];
    for (final p in pts) {
      if (!uniq.any((q) => (q - p).distance < 1e-6)) uniq.add(p);
    }
    if (uniq.length < 2) return null;
    return (uniq.first, uniq[1]);
  }

  // ------------------------- 视口 ↔ 局部坐标系工具 -------------------------

  /// 将 viewport 的四个角点变换到以 [center] 为原点、逆旋转 [rotation] 后的
  /// 局部坐标系，返回局部坐标系下的外接 AABB。
  Rect _viewportToLocalAABB(Viewport v, Offset center, double rotation) {
    final corners = [
      Offset(v.xmin, v.ymin),
      Offset(v.xmin, v.ymax),
      Offset(v.xmax, v.ymin),
      Offset(v.xmax, v.ymax),
    ];
    final cosR = math.cos(-rotation);
    final sinR = math.sin(-rotation);
    double xlMin = double.infinity, xlMax = -double.infinity;
    double ylMin = double.infinity, ylMax = -double.infinity;
    for (final p in corners) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      final xl = dx * cosR - dy * sinR;
      final yl = dx * sinR + dy * cosR;
      xlMin = math.min(xlMin, xl);
      xlMax = math.max(xlMax, xl);
      ylMin = math.min(ylMin, yl);
      ylMax = math.max(ylMax, yl);
    }
    return Rect.fromLTRB(xlMin, ylMin, xlMax, ylMax);
  }

  static double cosh(double x) {
    final e = math.exp(x);
    return (e + 1 / e) / 2;
  }

  static double sinh(double x) {
    final e = math.exp(x);
    return (e - 1 / e) / 2;
  }

  static double acosh(double x) {
    if (x < 1) return 0;
    return math.log(x + math.sqrt(x * x - 1));
  }

  static double asinh(double x) {
    return math.log(x + math.sqrt(x * x + 1));
  }

  // ------------------------- 通用工具 -------------------------

  void _drawPath(Canvas c, Path path, Paint paint, String? style) {
    if (style == 'dashed') {
      _drawDashedPath(c, path, paint);
    } else {
      c.drawPath(path, paint);
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dashLen = 6,
    double gapLen = 4,
  }) {
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = math.min(dist + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gapLen;
      }
    }
  }

  void _drawLabel(Canvas c, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, offset);
  }

  Color _color(GeometryElement e, {required Color fallback}) {
    final argb = e.colorArgb;
    return argb != null ? Color(argb) : fallback;
  }

  @override
  bool shouldRepaint(covariant GeometryPainter old) {
    return !identical(old.scene, scene) ||
        old._animT != _animT ||
        old.paintVersion != paintVersion ||
        old.draggingGliderId != draggingGliderId;
  }
}
