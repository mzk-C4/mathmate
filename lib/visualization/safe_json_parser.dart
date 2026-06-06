import 'dart:convert';
import 'dart:math' as math;

import 'models.dart';

/// 防御性 JSON 解析。
///
/// 设计原则：
///   * 键名比较一律 [String.toLowerCase]；
///   * 数字字段同时接受 [num] 与字符串（走 [double.tryParse] 兜底）；
///   * 缺失或类型异常的字段使用合理缺省值；
///   * 未知 `type` 的图元被静默跳过，不影响兄弟图元；
///   * 唯一会向上抛的异常是顶层 [jsonDecode] 失败，由调用方决定如何展示。
class SafeJsonParser {
  const SafeJsonParser();

  /// 解析顶层 JSON 字符串。
  static GeometryScene parseScene(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! Map) return GeometryScene.empty;
    return parseSceneFromMap(raw);
  }

  /// 从已解码的 Map 解析（兼容旧的调用方）。
  static GeometryScene parseSceneFromMap(Map raw) {
    final viewport = _parseViewport(_get(raw, 'viewport'));
    final elementsRaw = _get(raw, 'elements');
    final elements = <GeometryElement>[];
    if (elementsRaw is List) {
      for (final e in elementsRaw) {
        if (e is Map) {
          final el = _parseElement(e);
          if (el != null) elements.add(el);
        }
      }
    }
    return GeometryScene(viewport: viewport, elements: elements);
  }

  /// 大小写不敏感地从 Map 取值，缺失返回 `null`。
  static dynamic _get(Map map, String key) {
    final lower = key.toLowerCase();
    for (final entry in map.entries) {
      if (entry.key.toString().toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static Viewport _parseViewport(dynamic v) {
    if (v is! Map) return Viewport.defaultViewport;
    return Viewport(
      xmin: tryDouble(_get(v, 'xmin')) ?? -10,
      xmax: tryDouble(_get(v, 'xmax')) ?? 10,
      ymin: tryDouble(_get(v, 'ymin')) ?? -10,
      ymax: tryDouble(_get(v, 'ymax')) ?? 10,
    );
  }

  static GeometryElement? _parseElement(Map e) {
    final id = tryString(_get(e, 'id'));
    final type = tryString(_get(e, 'type'))?.toLowerCase();
    if (id == null || type == null) return null;

    final label = tryString(_get(e, 'label'));
    final color = tryColor(_get(e, 'color'));
    final style = tryString(_get(e, 'style'))?.toLowerCase();

    switch (type) {
      case 'point':
        final pos = tryDoubleList(_get(e, 'pos'));
        if (pos == null || pos.length < 2) return null;
        final constraint = _parsePointConstraint(e);
        return PointElement(
          id: id,
          x: pos[0],
          y: pos[1],
          constraint: constraint,
          label: label,
          colorArgb: color,
          style: style,
        );
      case 'circle':
        final center = tryDoubleList(_get(e, 'center'));
        final r = tryDouble(_get(e, 'radius'));
        if (center == null || center.length < 2 || r == null) return null;
        return CircleElement(
          id: id,
          cx: center[0],
          cy: center[1],
          radius: r,
          label: label,
          colorArgb: color,
          style: style,
        );
      case 'line':
        final p1 = _parseEndpoint(_get(e, 'p1'));
        final p2 = _parseEndpoint(_get(e, 'p2'));
        if (p1 == null || p2 == null) return null;
        return LineElement(
          id: id,
          p1: p1,
          p2: p2,
          label: label,
          colorArgb: color,
          style: style,
        );
      case 'glider':
        final target = tryString(_get(e, 'targetId'));
        if (target == null) return null;
        return GliderElement(
          id: id,
          targetId: target,
          t: tryDouble(_get(e, 't')) ?? 0.0,
          isAnimated: tryBool(_get(e, 'isAnimated')) ?? false,
          isDraggable: tryBool(_get(e, 'isDraggable')) ?? false,
          label: label,
          colorArgb: color,
          style: style,
        );
      case 'ellipse':
        final center = tryDoubleList(_get(e, 'center'));
        final rx = tryDouble(_get(e, 'rx'));
        final ry = tryDouble(_get(e, 'ry'));
        final rotDeg = tryDouble(_get(e, 'rotation')) ?? 0.0;
        if (center == null || center.length < 2 || rx == null || ry == null) {
          return null;
        }
        if (rx <= 0 || ry <= 0) return null;
        return EllipseElement(
          id: id,
          cx: center[0],
          cy: center[1],
          rx: rx,
          ry: ry,
          rotation: rotDeg * math.pi / 180,
          label: label,
          colorArgb: color,
          style: style,
        );
      case 'hyperbola':
        final center = tryDoubleList(_get(e, 'center'));
        final a = tryDouble(_get(e, 'a'));
        final b = tryDouble(_get(e, 'b'));
        final rotDeg = tryDouble(_get(e, 'rotation')) ?? 0.0;
        if (center == null || center.length < 2 || a == null || b == null) {
          return null;
        }
        if (a <= 0 || b <= 0) return null;
        return HyperbolaElement(
          id: id,
          cx: center[0],
          cy: center[1],
          a: a,
          b: b,
          rotation: rotDeg * math.pi / 180,
          label: label,
          colorArgb: color,
          style: style,
        );
      case 'parabola':
        final vertex = tryDoubleList(_get(e, 'vertex'));
        final pVal = tryDouble(_get(e, 'p'));
        if (vertex == null || vertex.length < 2 || pVal == null) return null;
        if (pVal == 0) return null;
        double rotDeg;
        final rotRaw = tryDouble(_get(e, 'rotation'));
        if (rotRaw != null) {
          rotDeg = rotRaw;
        } else {
          final dir = tryString(_get(e, 'direction'))?.toLowerCase();
          rotDeg = switch (dir) {
            'right' => 0.0,
            'up' => 90.0,
            'left' => 180.0,
            'down' => -90.0,
            _ => 0.0,
          };
        }
        return ParabolaElement(
          id: id,
          vx: vertex[0],
          vy: vertex[1],
          p: pVal,
          rotation: rotDeg * math.pi / 180,
          label: label,
          colorArgb: color,
          style: style,
        );
      default:
        return null;
    }
  }

  static PointConstraint? _parsePointConstraint(Map e) {
    // midpoint: ["A", "B"]
    final midpoint = tryStringList(_get(e, 'midpoint'));
    if (midpoint != null && midpoint.length >= 2) {
      return MidpointConstraint(pid1: midpoint[0], pid2: midpoint[1]);
    }
    // onSegment: ["A", "B"] + ratio
    final onSegment = tryStringList(_get(e, 'onSegment'));
    if (onSegment != null && onSegment.length >= 2) {
      final ratio = tryDouble(_get(e, 'ratio')) ?? 0.5;
      return OnSegmentConstraint(pid1: onSegment[0], pid2: onSegment[1], ratio: ratio);
    }
    // onLine: ["A", "B"] + ratio
    final onLine = tryStringList(_get(e, 'onLine'));
    if (onLine != null && onLine.length >= 2) {
      final ratio = tryDouble(_get(e, 'ratio')) ?? 0.5;
      return OnLineConstraint(pid1: onLine[0], pid2: onLine[1], ratio: ratio);
    }
    // intersection: ["l1", "l2"]
    final intersection = tryStringList(_get(e, 'intersection'));
    if (intersection != null && intersection.length >= 2) {
      return IntersectionConstraint(lid1: intersection[0], lid2: intersection[1]);
    }
    return null;
  }

  static List<String>? tryStringList(dynamic v) {
    if (v is! List) return null;
    return v.map((e) => e.toString()).toList();
  }

  static EndpointRef? _parseEndpoint(dynamic v) {
    if (v is String) return EndpointRef.byId(v);
    final list = tryDoubleList(v);
    if (list != null && list.length >= 2) {
      return EndpointRef.byCoord(list[0], list[1]);
    }
    return null;
  }

  // -------- 公开小工具，便于直接做单元测试 --------

  static double? tryDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static bool? tryBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

  static String? tryString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static List<double>? tryDoubleList(dynamic v) {
    if (v is! List) return null;
    final out = <double>[];
    for (final e in v) {
      final d = tryDouble(e);
      if (d == null) return null;
      out.add(d);
    }
    return out;
  }

  /// `#RRGGBB` / `#AARRGGBB` / 纯整型都接受。失败返回 `null`。
  static int? tryColor(dynamic v) {
    if (v is num) return v.toInt() & 0xFFFFFFFF;
    if (v is! String) return null;
    var h = v.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    return int.tryParse(h, radix: 16);
  }

  // -------- 兼容旧 API 的实例方法 --------

  Map<String, dynamic> safeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return <String, dynamic>{};
  }

  List<dynamic> safeList(dynamic value) {
    if (value is List<dynamic>) return value;
    return <dynamic>[];
  }

  double safeToDouble(dynamic value, [double defaultValue = 0.0]) {
    return tryDouble(value) ?? defaultValue;
  }

  String safeString(dynamic value, [String defaultValue = '']) {
    return tryString(value) ?? defaultValue;
  }

  dynamic readValueCaseInsensitive(Map map, List<String> candidateKeys) {
    for (final String key in candidateKeys) {
      final v = _get(map, key);
      if (v != null) return v;
    }
    return null;
  }

  List<double> safePoint(dynamic value) {
    if (value is List) {
      final result = <double>[];
      for (final v in value) {
        result.add(tryDouble(v) ?? 0.0);
      }
      if (result.length >= 2) return result;
      while (result.length < 2) {
        result.add(0.0);
      }
      return result;
    }
    if (value is Map) {
      return <double>[
        tryDouble(_get(value, 'x')) ?? 0.0,
        tryDouble(_get(value, 'y')) ?? 0.0,
      ];
    }
    return <double>[0.0, 0.0];
  }
}
