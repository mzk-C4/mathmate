// 几何模型层。
//
// 纯 Dart——不导入 dart:ui / Flutter，确保模型可以在任何环境（含纯单元
// 测试）下被解析和使用。颜色字段用 int 形式的 ARGB 表示，由渲染层
// 转换成 Color。

/// 数学坐标系视口。所有几何字面坐标都基于这套视口。
class Viewport {
  final double xmin;
  final double xmax;
  final double ymin;
  final double ymax;

  const Viewport({
    required this.xmin,
    required this.xmax,
    required this.ymin,
    required this.ymax,
  });

  double get width => xmax - xmin;
  double get height => ymax - ymin;

  bool containsX(double x) => x >= xmin && x <= xmax;
  bool containsY(double y) => y >= ymin && y <= ymax;

  static const Viewport defaultViewport = Viewport(
    xmin: -10,
    xmax: 10,
    ymin: -10,
    ymax: 10,
  );
}

/// 所有几何图元的抽象基类。
abstract class GeometryElement {
  final String id;
  final String? label;
  final int? colorArgb;
  final String? style; // 'solid' / 'dashed'
  const GeometryElement({
    required this.id,
    this.label,
    this.colorArgb,
    this.style,
  });
}

/// 点的约束类型——告诉渲染器用几何关系计算精确坐标，而不是相信模型估算的值。
sealed class PointConstraint {
  const PointConstraint();
}

/// 中点约束：point = midpoint of segment(pid1, pid2)
class MidpointConstraint extends PointConstraint {
  final String pid1;
  final String pid2;
  const MidpointConstraint({required this.pid1, required this.pid2}) : super();
}

/// 线段比例约束：point on segment(pid1, pid2) at ratio ∈ [0,1] from pid1
class OnSegmentConstraint extends PointConstraint {
  final String pid1;
  final String pid2;
  final double ratio;
  const OnSegmentConstraint({required this.pid1, required this.pid2, required this.ratio}) : super();
}

/// 直线比例约束：point on line(pid1, pid2) at ratio from pid1
class OnLineConstraint extends PointConstraint {
  final String pid1;
  final String pid2;
  final double ratio;
  const OnLineConstraint({required this.pid1, required this.pid2, required this.ratio}) : super();
}

/// 两线交点约束：point = intersection of line(lid1) and line(lid2)
class IntersectionConstraint extends PointConstraint {
  final String lid1;
  final String lid2;
  const IntersectionConstraint({required this.lid1, required this.lid2}) : super();
}

class PointElement extends GeometryElement {
  final double x;
  final double y;
  final PointConstraint? constraint;
  const PointElement({
    required super.id,
    required this.x,
    required this.y,
    this.constraint,
    super.label,
    super.colorArgb,
    super.style,
  });
}

class CircleElement extends GeometryElement {
  final double cx;
  final double cy;
  final double radius;
  const CircleElement({
    required super.id,
    required this.cx,
    required this.cy,
    required this.radius,
    super.label,
    super.colorArgb,
    super.style,
  });
}

/// 直线端点描述：要么是字面坐标，要么是另一个图元的 id 引用。
class EndpointRef {
  final String? refId;
  final double? x;
  final double? y;

  const EndpointRef.byId(String this.refId)
      : x = null,
        y = null;

  const EndpointRef.byCoord(double this.x, double this.y) : refId = null;

  bool get isReference => refId != null;
}

/// `line` 在协议中语义为**直线**而非线段——渲染层会按视口边界裁剪。
class LineElement extends GeometryElement {
  final EndpointRef p1;
  final EndpointRef p2;
  const LineElement({
    required super.id,
    required this.p1,
    required this.p2,
    super.label,
    super.colorArgb,
    super.style,
  });
}

/// 滑动点：吸附在 [targetId] 指向的图元（当前实现支持圆、椭圆、双曲线）上。
///
/// 当 [isAnimated] 为 true 时，渲染层会用 AnimationController 的当前值
/// 替换 [t]；否则使用静态的 [t]。
class GliderElement extends GeometryElement {
  final String targetId;
  final double t;
  final bool isAnimated;
  final bool isDraggable;
  const GliderElement({
    required super.id,
    required this.targetId,
    required this.t,
    required this.isAnimated,
    this.isDraggable = false,
    super.label,
    super.colorArgb,
    super.style,
  });
}

class EllipseElement extends GeometryElement {
  final double cx;
  final double cy;
  final double rx;
  final double ry;

  /// 弧度（渲染层直接使用，解析器负责把 JSON 中的角度转成弧度）。
  final double rotation;
  const EllipseElement({
    required super.id,
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required this.rotation,
    super.label,
    super.colorArgb,
    super.style,
  });
}

/// 标准左右开口双曲线 `(x/a)^2 - (y/b)^2 = 1`，再整体旋转 [rotation] 弧度。
/// 上下开口可通过 `rotation = π/2` 实现。
class HyperbolaElement extends GeometryElement {
  final double cx;
  final double cy;
  final double a;
  final double b;

  /// 弧度。
  final double rotation;
  const HyperbolaElement({
    required super.id,
    required this.cx,
    required this.cy,
    required this.a,
    required this.b,
    required this.rotation,
    super.label,
    super.colorArgb,
    super.style,
  });
}

/// 标准开口向右抛物线 `y^2 = 4px`（参数化 `x = p*t^2, y = 2p*t`），
/// 再整体旋转 [rotation] 弧度。其他方向通过 rotation 实现。
class ParabolaElement extends GeometryElement {
  final double vx;
  final double vy;
  final double p;

  /// 弧度。
  final double rotation;
  const ParabolaElement({
    required super.id,
    required this.vx,
    required this.vy,
    required this.p,
    required this.rotation,
    super.label,
    super.colorArgb,
    super.style,
  });
}

/// 一份完整的几何场景：视口 + 图元列表（渲染顺序按列表顺序）。
class GeometryScene {
  final Viewport viewport;
  final List<GeometryElement> elements;
  const GeometryScene({required this.viewport, required this.elements});

  static const GeometryScene empty = GeometryScene(
    viewport: Viewport.defaultViewport,
    elements: [],
  );
}
