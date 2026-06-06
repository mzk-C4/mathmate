import 'dart:math' as math;

import 'models.dart';

/// 将 [GeometryScene] 转换为内嵌 SVG 字符串。
///
/// 纯 Dart 实现，不依赖 Flutter Canvas。生成的 SVG 可直接嵌入 HTML。
class GeometrySvgRenderer {
  const GeometrySvgRenderer();

  /// 生成 SVG 字符串。width/height 为像素尺寸。
  String render(GeometryScene scene, {double width = 600, double height = 400}) {
    final v = scene.viewport;
    final scale = math.min(width / v.width, height / v.height);
    final ox = (width - v.width * scale) / 2;
    final oy = (height - v.height * scale) / 2;

    String pt(double mx, double my) {
      final px = (mx - v.xmin) * scale + ox;
      final py = (v.ymax - my) * scale + oy;
      return '${px.toStringAsFixed(1)},${py.toStringAsFixed(1)}';
    }

    // 约束求解
    final byId = <String, GeometryElement>{for (final e in scene.elements) e.id: e};
    final positions = <String, Offset2D>{};
    for (final e in scene.elements) {
      if (e is PointElement) positions[e.id] = Offset2D(e.x, e.y);
    }
    _resolveConstraints(positions, byId);

    String ptc(String? id, double fallbackX, double fallbackY) {
      if (id != null && positions.containsKey(id)) {
        final p = positions[id]!;
        return pt(p.x, p.y);
      }
      return pt(fallbackX, fallbackY);
    }

    final buf = StringBuffer();
    buf.write('<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" '
        'viewBox="0 0 $width $height" style="background:#fafafa;border:1px solid #ddd;border-radius:4px">');

    // 坐标轴（轻灰虚线）
    if (v.xmin <= 0 && v.xmax >= 0) {
      final x0 = pt(0, v.ymin);
      final x1 = pt(0, v.ymax);
      buf.write('<line x1="${x0.split(",")[0]}" y1="${x0.split(",")[1]}" '
          'x2="${x1.split(",")[0]}" y2="${x1.split(",")[1]}" stroke="#ddd" stroke-width="1" stroke-dasharray="4,4"/>');
    }
    if (v.ymin <= 0 && v.ymax >= 0) {
      final y0 = pt(v.xmin, 0);
      final y1 = pt(v.xmax, 0);
      buf.write('<line x1="${y0.split(",")[0]}" y1="${y0.split(",")[1]}" '
          'x2="${y1.split(",")[0]}" y2="${y1.split(",")[1]}" stroke="#ddd" stroke-width="1" stroke-dasharray="4,4"/>');
    }

    for (final e in scene.elements) {
      if (e is PointElement) {
        final p = ptc(e.id, e.x, e.y);
        final xy = p.split(',');
        buf.write('<circle cx="${xy[0]}" cy="${xy[1]}" r="4" fill="#e53935"/>');
        if (e.label != null) {
          buf.write('<text x="${xy[0]}" y="${double.parse(xy[1]) - 8}" '
              'font-size="12" fill="#333" font-family="sans-serif">${_esc(e.label!)}</text>');
        }
      } else if (e is CircleElement) {
        final c = pt(e.cx, e.cy);
        final xy = c.split(',');
        final r = (e.radius * scale).toStringAsFixed(1);
        final dash = e.style == 'dashed' ? ' stroke-dasharray="6,3"' : '';
        buf.write('<circle cx="${xy[0]}" cy="${xy[1]}" r="$r" fill="none" stroke="#1e88e5" stroke-width="1.5"$dash/>');
        if (e.label != null) {
          buf.write('<text x="${xy[0]}" y="${double.parse(xy[1]) - double.parse(r) - 4}" '
              'font-size="12" fill="#333" font-family="sans-serif">${_esc(e.label!)}</text>');
        }
      } else if (e is LineElement) {
        Offset2D p1, p2;
        if (e.p1.isReference) {
          final ref = _findPoint(e.p1.refId!, byId);
          if (ref == null) continue;
          p1 = Offset2D(ref.x, ref.y);
        } else {
          p1 = Offset2D(e.p1.x!, e.p1.y!);
        }
        if (e.p2.isReference) {
          final ref = _findPoint(e.p2.refId!, byId);
          if (ref == null) continue;
          p2 = Offset2D(ref.x, ref.y);
        } else {
          p2 = Offset2D(e.p2.x!, e.p2.y!);
        }
        final a = pt(p1.x, p1.y);
        final b = pt(p2.x, p2.y);
        final dash = e.style == 'dashed' ? ' stroke-dasharray="6,3"' : '';
        buf.write('<line x1="${a.split(",")[0]}" y1="${a.split(",")[1]}" '
            'x2="${b.split(",")[0]}" y2="${b.split(",")[1]}" stroke="#43a047" stroke-width="1.5"$dash/>');
        if (e.label != null) {
          final mx = (p1.x + p2.x) / 2;
          final my = (p1.y + p2.y) / 2;
          final mid = pt(mx, my);
          final xy2 = mid.split(',');
          buf.write('<text x="${xy2[0]}" y="${double.parse(xy2[1]) - 6}" '
              'font-size="12" fill="#333" font-family="sans-serif">${_esc(e.label!)}</text>');
        }
      } else if (e is EllipseElement) {
        final c = pt(e.cx, e.cy);
        final xy = c.split(',');
        final rx = (e.rx * scale).toStringAsFixed(1);
        final ry = (e.ry * scale).toStringAsFixed(1);
        final rot = e.rotation * 180 / math.pi; // 弧度转度
        buf.write('<ellipse cx="${xy[0]}" cy="${xy[1]}" rx="$rx" ry="$ry" '
            'transform="rotate(${rot.toStringAsFixed(1)},${xy[0]},${xy[1]})" '
            'fill="none" stroke="#8e24aa" stroke-width="1.5"/>');
        if (e.label != null) {
          buf.write('<text x="${xy[0]}" y="${double.parse(xy[1]) - double.parse(ry) - 4}" '
              'font-size="12" fill="#333" font-family="sans-serif">${_esc(e.label!)}</text>');
        }
      } else if (e is ParabolaElement) {
        _renderParabolaSvg(buf, e, v, scale, ox, oy, pt);
      } else if (e is HyperbolaElement) {
        _renderHyperbolaSvg(buf, e, v, scale, ox, oy, pt);
      }
    }

    buf.write('</svg>');
    return buf.toString();
  }

  void _renderParabolaSvg(StringBuffer buf, ParabolaElement e, Viewport v,
      double scale, double ox, double oy, String Function(double, double) pt) {
    final path = StringBuffer();
    bool first = true;
    // 抛物线参数方程
    double rotRad = e.rotation;
    for (int i = 0; i <= 80; i++) {
      final t = (i / 40 - 1) * 4; // t ∈ [-4, 4]
      final xl = 2 * e.p * t;
      final yl = e.p * t * t;
      final cosR = math.cos(rotRad);
      final sinR = math.sin(rotRad);
      final xw = e.vx + xl * cosR - yl * sinR;
      final yw = e.vy + xl * sinR + yl * cosR;
      if (!v.containsX(xw) || !v.containsY(yw)) {
        first = true;
        continue;
      }
      final p = pt(xw, yw);
      final xy = p.split(',');
      if (first) {
        path.write('M${xy[0]},${xy[1]}');
        first = false;
      } else {
        path.write('L${xy[0]},${xy[1]}');
      }
    }
    if (path.isNotEmpty) {
      buf.write('<path d="$path" fill="none" stroke="#fb8c00" stroke-width="1.5"/>');
    }
  }

  void _renderHyperbolaSvg(StringBuffer buf, HyperbolaElement e, Viewport v,
      double scale, double ox, double oy, String Function(double, double) pt) {
    // 右支
    _renderHyperbolaBranch(buf, e, v, true, pt);
    // 左支
    _renderHyperbolaBranch(buf, e, v, false, pt);
  }

  void _renderHyperbolaBranch(StringBuffer buf, HyperbolaElement e, Viewport v,
      bool rightBranch, String Function(double, double) pt) {
    final path = StringBuffer();
    bool first = true;
    final cosR = math.cos(e.rotation);
    final sinR = math.sin(e.rotation);
    for (int i = 0; i <= 100; i++) {
      // 局部坐标：t ∈ [-4, 4]，覆盖视口可见区域
      final tLocal = (i / 50 - 1) * 4;
      final sign = rightBranch ? 1.0 : -1.0;
      final coshT = cosh(tLocal);
      final sinhT = sinh(tLocal);
      final xl = sign * e.a * coshT;
      final yl = e.b * sinhT;
      final xw = e.cx + xl * cosR - yl * sinR;
      final yw = e.cy + xl * sinR + yl * cosR;
      if (!v.containsX(xw) || !v.containsY(yw)) {
        first = true;
        continue;
      }
      final p = pt(xw, yw);
      final xy = p.split(',');
      if (first) {
        path.write('M${xy[0]},${xy[1]}');
        first = false;
      } else {
        path.write('L${xy[0]},${xy[1]}');
      }
    }
    if (path.isNotEmpty) {
      buf.write('<path d="$path" fill="none" stroke="#ef6c00" stroke-width="1.5"/>');
    }
  }

  void _resolveConstraints(Map<String, Offset2D> positions, Map<String, GeometryElement> byId) {
    for (final e in byId.values) {
      if (e is! PointElement || e.constraint == null) continue;
      final c = e.constraint!;
      Offset2D? resolved;
      if (c is MidpointConstraint) {
        final p1 = positions[c.pid1];
        final p2 = positions[c.pid2];
        if (p1 != null && p2 != null) {
          resolved = Offset2D((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
        }
      } else if (c is OnSegmentConstraint) {
        final p1 = positions[c.pid1];
        final p2 = positions[c.pid2];
        if (p1 != null && p2 != null) {
          resolved = Offset2D(p1.x + (p2.x - p1.x) * c.ratio, p1.y + (p2.y - p1.y) * c.ratio);
        }
      } else if (c is OnLineConstraint) {
        final p1 = positions[c.pid1];
        final p2 = positions[c.pid2];
        if (p1 != null && p2 != null) {
          resolved = Offset2D(p1.x + (p2.x - p1.x) * c.ratio, p1.y + (p2.y - p1.y) * c.ratio);
        }
      } else if (c is IntersectionConstraint) {
        resolved = _intersectLinesSvg(positions, byId, c.lid1, c.lid2);
      }
      if (resolved != null) positions[e.id] = resolved;
    }
  }

  Offset2D? _intersectLinesSvg(Map<String, Offset2D> positions, Map<String, GeometryElement> byId, String lid1, String lid2) {
    Offset2D? a1, a2, b1, b2;
    final l1 = byId[lid1];
    final l2 = byId[lid2];
    if (l1 is LineElement) {
      a1 = _epPos(l1.p1, positions, byId);
      a2 = _epPos(l1.p2, positions, byId);
    }
    if (l2 is LineElement) {
      b1 = _epPos(l2.p1, positions, byId);
      b2 = _epPos(l2.p2, positions, byId);
    }
    if (a1 == null || a2 == null || b1 == null || b2 == null) return null;
    final denom = (a1.x - a2.x) * (b1.y - b2.y) - (a1.y - a2.y) * (b1.x - b2.x);
    if (denom.abs() < 1e-10) return null;
    final t = ((a1.x - b1.x) * (b1.y - b2.y) - (a1.y - b1.y) * (b1.x - b2.x)) / denom;
    return Offset2D(a1.x + t * (a2.x - a1.x), a1.y + t * (a2.y - a1.y));
  }

  Offset2D? _epPos(EndpointRef ep, Map<String, Offset2D> positions, Map<String, GeometryElement> byId) {
    if (ep.isReference) {
      return positions[ep.refId!] ?? (_findPoint(ep.refId!, byId) != null
          ? Offset2D((_findPoint(ep.refId!, byId) as PointElement).x, (_findPoint(ep.refId!, byId) as PointElement).y)
          : null);
    }
    if (ep.x != null && ep.y != null) return Offset2D(ep.x!, ep.y!);
    return null;
  }

  PointElement? _findPoint(String id, Map<String, GeometryElement> elements) {
    final e = elements[id];
    return e is PointElement ? e : null;
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// 简单的 2D 坐标类（避免依赖 dart:ui.Offset）
class Offset2D {
  final double x;
  final double y;
  const Offset2D(this.x, this.y);
}

/// 数学函数（Dart 标准库的 dart:math 没有 cosh/sinh）
double cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
double sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double asinh(double x) => math.log(x + math.sqrt(x * x + 1));
double acosh(double x) => math.log(x + math.sqrt(x * x - 1));
