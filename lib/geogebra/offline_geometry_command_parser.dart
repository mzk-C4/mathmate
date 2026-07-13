import 'package:mathmate/geogebra/geometry_plan.dart';

/// Recognizes only high-confidence, deterministic drawing requests.
/// Everything else is left to the online agent instead of guessing.
class OfflineGeometryCommandParser {
  const OfflineGeometryCommandParser();

  GeometryPlan? parse(
    String input, {
    Iterable<String> knownPointLabels = const <String>[],
  }) {
    final String text = _normalize(input);

    final GeometryPlan? referencePlan = _parsePointReferencePlan(
      text,
      knownPointLabels,
    );
    if (referencePlan != null) return referencePlan;

    final GeometryPlan? compositePointPlan = _parseCompositePointPlan(text);
    if (compositePointPlan != null) return compositePointPlan;

    final RegExpMatch? point = RegExp(
      r'(?:画|创建|新建)(?:一个)?点\s*([A-Za-z][A-Za-z0-9_]*)[^\d-]*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)',
      caseSensitive: false,
    ).firstMatch(text);
    if (point != null) {
      final String label = point.group(1)!;
      final String x = point.group(2)!;
      final String y = point.group(3)!;
      return GeometryPlan(
        commands: <String>['$label = ($x, $y)'],
        summary: '已在本地创建点 $label($x, $y)。',
      );
    }

    final RegExpMatch? pointAtCoordinates = RegExp(
      r'(?:在)?\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)(?:处|位置)?\s*(?:画|创建|新建)(?:一个)?(?:点\s*)?([A-Za-z][A-Za-z0-9_]*)(?:点)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (pointAtCoordinates != null) {
      final String x = pointAtCoordinates.group(1)!;
      final String y = pointAtCoordinates.group(2)!;
      final String label = pointAtCoordinates.group(3)!;
      return GeometryPlan(
        commands: <String>['$label = ($x, $y)'],
        summary: '已在本地创建点 $label($x, $y)。',
      );
    }

    final RegExpMatch? circle = RegExp(
      r'以\s*([A-Za-z][A-Za-z0-9_]*)\s*为圆心.*?半径(?:为|是)?\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (circle != null) {
      final String center = circle.group(1)!;
      final String radius = circle.group(2)!;
      return GeometryPlan(
        commands: <String>['Circle($center, $radius)'],
        summary: '已在本地创建以 $center 为圆心、半径为 $radius 的圆。',
      );
    }

    final RegExpMatch? circleWithCenter = RegExp(
      r'(?:画|作|创建)(?:一个)?圆.*?圆心(?:为|是)?\s*([A-Za-z][A-Za-z0-9_]*).*?半径(?:为|是)?\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (circleWithCenter != null) {
      final String center = circleWithCenter.group(1)!;
      final String radius = circleWithCenter.group(2)!;
      return GeometryPlan(
        commands: <String>['Circle($center, $radius)'],
        summary: '已在本地创建以 $center 为圆心、半径为 $radius 的圆。',
      );
    }

    final RegExpMatch? regularPolygon = RegExp(
      r'(?:画|作|绘制|创建)(?:一个)?正(3|4|5|6|7|8|9|10|11|12|三|四|五|六|七|八|九|十|十一|十二)边形',
    ).firstMatch(text);
    if (regularPolygon != null) {
      final int sides = _parseSideCount(regularPolygon.group(1)!);
      return GeometryPlan(
        commands: <String>[
          'P_1 = (-2, 0)',
          'P_2 = (2, 0)',
          'Polygon(P_1, P_2, $sides)',
        ],
        summary: '已在本地创建正 $sides 边形。',
      );
    }

    final List<String>? polygonLabels = _parsePolygonLabels(text);
    if (polygonLabels != null) {
      final String labels = polygonLabels.join(', ');
      return GeometryPlan(
        commands: <String>['Polygon($labels)'],
        summary: '已在本地依次连接 ${polygonLabels.join('、')} 构成多边形。',
      );
    }

    final RegExpMatch? connectedPoints = RegExp(
      r'连接\s*(?:点)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:和|与|到|、|,)\s*(?:点)?\s*([A-Za-z][A-Za-z0-9_]*)(?!\s*(?:和|与|、|,)\s*(?:点)?[A-Za-z])(?!\s*(?:组成|构成|形成|成)(?:一个)?(?:三角形|多边形))',
      caseSensitive: false,
    ).firstMatch(text);
    if (connectedPoints != null) {
      final String a = connectedPoints.group(1)!;
      final String b = connectedPoints.group(2)!;
      return GeometryPlan(
        commands: <String>['Segment($a, $b)'],
        summary: '已在本地连接点 $a 和 $b。',
      );
    }

    final RegExpMatch? segment = RegExp(
      r'(?:画|作|连接)(?:出)?(?:一条)?线段\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:和|与|到|、|,)?\s*([A-Za-z][A-Za-z0-9_]*)',
      caseSensitive: false,
    ).firstMatch(text);
    if (segment != null) {
      final String a = segment.group(1)!;
      final String b = segment.group(2)!;
      return GeometryPlan(
        commands: <String>['Segment($a, $b)'],
        summary: '已在本地连接点 $a 和 $b。',
      );
    }

    final RegExpMatch? compactSegment = RegExp(
      r'(?:画|作)(?:出)?(?:一条)?线段\s*([A-Za-z])([A-Za-z])$',
      caseSensitive: false,
    ).firstMatch(text);
    if (compactSegment != null) {
      final String a = compactSegment.group(1)!;
      final String b = compactSegment.group(2)!;
      return GeometryPlan(
        commands: <String>['Segment($a, $b)'],
        summary: '已在本地连接点 $a 和 $b。',
      );
    }

    final RegExpMatch? midpoint = RegExp(
      r'(?:求|作|画)(?:出)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:和|与|、|,)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:的)?中点',
      caseSensitive: false,
    ).firstMatch(text);
    if (midpoint != null) {
      final String a = midpoint.group(1)!;
      final String b = midpoint.group(2)!;
      return GeometryPlan(
        commands: <String>['Midpoint($a, $b)'],
        summary: '已在本地创建 $a、$b 的中点。',
      );
    }

    final RegExpMatch? compactMidpoint = RegExp(
      r'(?:求|作|画)(?:出)?(?:线段)?\s*([A-Za-z])([A-Za-z])\s*(?:的)?中点',
      caseSensitive: false,
    ).firstMatch(text);
    if (compactMidpoint != null) {
      final String a = compactMidpoint.group(1)!;
      final String b = compactMidpoint.group(2)!;
      return GeometryPlan(
        commands: <String>['Midpoint($a, $b)'],
        summary: '已在本地创建 $a、$b 的中点。',
      );
    }

    final RegExpMatch? perpendicular = RegExp(
      r'过(?:点)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:作|画|绘制)?\s*(?:直线)?\s*([A-Za-z][A-Za-z0-9_]*)\s*的?垂线',
      caseSensitive: false,
    ).firstMatch(text);
    if (perpendicular != null) {
      final String point = perpendicular.group(1)!;
      final String line = perpendicular.group(2)!;
      return GeometryPlan(
        commands: <String>['PerpendicularLine($point, $line)'],
        summary: '已在本地创建过点 $point 且垂直于 $line 的直线。',
      );
    }

    final RegExpMatch? perpendicularToLine = RegExp(
      r'(?:作|画|绘制)\s*过(?:点)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:且|并)?\s*(?:与)?(?:直线)?\s*([A-Za-z][A-Za-z0-9_]*)\s*垂直(?:的直线)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (perpendicularToLine != null) {
      final String point = perpendicularToLine.group(1)!;
      final String line = perpendicularToLine.group(2)!;
      return GeometryPlan(
        commands: <String>['PerpendicularLine($point, $line)'],
        summary: '已在本地创建过点 $point 且垂直于 $line 的直线。',
      );
    }

    final RegExpMatch? parallel = RegExp(
      r'过(?:点)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:作|画|绘制)?\s*(?:直线)?\s*([A-Za-z][A-Za-z0-9_]*)\s*的?平行线',
      caseSensitive: false,
    ).firstMatch(text);
    if (parallel != null) {
      final String point = parallel.group(1)!;
      final String line = parallel.group(2)!;
      return GeometryPlan(
        commands: <String>['ParallelLine($point, $line)'],
        summary: '已在本地创建过点 $point 且平行于 $line 的直线。',
      );
    }

    final RegExpMatch? parallelToLine = RegExp(
      r'(?:作|画|绘制)\s*过(?:点)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:且|并)?\s*(?:与)?(?:直线)?\s*([A-Za-z][A-Za-z0-9_]*)\s*平行(?:的直线)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (parallelToLine != null) {
      final String point = parallelToLine.group(1)!;
      final String line = parallelToLine.group(2)!;
      return GeometryPlan(
        commands: <String>['ParallelLine($point, $line)'],
        summary: '已在本地创建过点 $point 且平行于 $line 的直线。',
      );
    }

    final RegExpMatch? intersection = RegExp(
      r'(?:求|作|画)?(?:出)?\s*(?:直线|曲线|圆)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:和|与|、|,)\s*(?:直线|曲线|圆)?\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:的)?交点',
      caseSensitive: false,
    ).firstMatch(text);
    if (intersection != null) {
      final String first = intersection.group(1)!;
      final String second = intersection.group(2)!;
      return GeometryPlan(
        commands: <String>['Intersect($first, $second)'],
        summary: '已在本地创建 $first 与 $second 的交点。',
      );
    }

    final RegExpMatch? tangent = RegExp(
      r'(?:过(?:点)?|从(?:点)?)\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:作|画|绘制)?\s*(?:到)?\s*(?:圆)?\s*([A-Za-z][A-Za-z0-9_]*)\s*的?切线',
      caseSensitive: false,
    ).firstMatch(text);
    if (tangent != null) {
      final String point = tangent.group(1)!;
      final String circle = tangent.group(2)!;
      return GeometryPlan(
        commands: <String>['Tangent($point, $circle)'],
        summary: '已在本地创建点 $point 到圆 $circle 的切线。',
      );
    }

    final RegExpMatch? function = RegExp(
      r'^(?:(?:画|绘制)(?:出)?(?:函数|图像)?\s*)?((?:y|[A-Za-z]\s*\([^)]*\))\s*=\s*[^，。；;]+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (function != null) {
      final String expression = function.group(1)!.trim();
      if (!RegExp(r'[\u3400-\u9fff]').hasMatch(expression)) {
        return GeometryPlan(
          commands: <String>[expression],
          summary: '已在本地绘制 $expression。',
        );
      }
    }

    return null;
  }

  /// Whether [input] needs local canvas context to resolve point references.
  /// The mobile page uses this to avoid a bridge round-trip for ordinary text.
  bool needsPointReference(String input) {
    final String text = _normalize(input);
    return RegExp(r'(?:这|这些|所有).{0,4}点').hasMatch(text) &&
        RegExp(r'连接|连结').hasMatch(text);
  }

  GeometryPlan? _parsePointReferencePlan(
    String text,
    Iterable<String> knownPointLabels,
  ) {
    if (!needsPointReference(text)) return null;
    final List<String> labels = knownPointLabels
        .where(
          (String label) => RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(label),
        )
        .toSet()
        .toList(growable: false);

    if (RegExp(r'(?:这)?(?:两|2)(?:个)?点').hasMatch(text) && labels.length == 2) {
      return GeometryPlan(
        commands: <String>['Segment(${labels[0]}, ${labels[1]})'],
        summary: '已在本地连接当前的两个点 ${labels[0]} 和 ${labels[1]}。',
      );
    }

    final bool isTriangle = RegExp(r'三角形').hasMatch(text);
    if (isTriangle &&
        RegExp(r'(?:这)?(?:三|3)(?:个)?点').hasMatch(text) &&
        labels.length == 3) {
      return GeometryPlan(
        commands: <String>['Polygon(${labels.join(', ')})'],
        summary: '已在本地连接当前三个点构成三角形。',
      );
    }

    if (RegExp(r'(?:这些|所有)点').hasMatch(text) &&
        labels.length >= 3 &&
        labels.length <= 12) {
      return GeometryPlan(
        commands: <String>['Polygon(${labels.join(', ')})'],
        summary: '已在本地连接当前 ${labels.length} 个点构成多边形。',
      );
    }
    return null;
  }

  GeometryPlan? _parseCompositePointPlan(String text) {
    if (!RegExp(r'画|作|绘制|创建|新建|连接|点|三角形|多边形').hasMatch(text)) {
      return null;
    }

    final List<_ParsedPoint> points =
        RegExp(
              r'(?:点\s*)?([A-Za-z][A-Za-z0-9_]*)\s*(?:点)?\s*(?:的)?\s*(?:坐标)?\s*(?:=|为|是|:)?\s*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)',
              caseSensitive: false,
            )
            .allMatches(text)
            .map((RegExpMatch match) {
              return _ParsedPoint(
                label: match.group(1)!,
                x: match.group(2)!,
                y: match.group(3)!,
              );
            })
            .toList(growable: false);

    // A single point is handled by the more specific rules below. This branch
    // exists for genuinely multi-step requests so that no trailing geometry
    // instruction is silently discarded.
    if (points.length < 2) return null;
    final Set<String> labels = points
        .map((_ParsedPoint point) => point.label.toLowerCase())
        .toSet();
    if (labels.length != points.length) return null;

    final List<String> commands = points
        .map(
          (_ParsedPoint point) => '${point.label} = (${point.x}, ${point.y})',
        )
        .toList(growable: true);
    String constructionSummary = '';

    final List<String>? explicitPolygon = _parsePolygonLabels(text);
    if (explicitPolygon != null) {
      commands.add('Polygon(${explicitPolygon.join(', ')})');
      constructionSummary = '，并连接成多边形';
    } else if (RegExp(r'三角形|多边形').hasMatch(text) && points.length >= 3) {
      commands.add('Polygon(${points.map((point) => point.label).join(', ')})');
      constructionSummary = '，并连接成多边形';
    } else if (RegExp(r'连接|线段').hasMatch(text) && points.length == 2) {
      commands.add('Segment(${points[0].label}, ${points[1].label})');
      constructionSummary = '，并连接成线段';
    }

    final String pointSummary = points
        .map((_ParsedPoint point) => '${point.label}(${point.x}, ${point.y})')
        .join('、');
    return GeometryPlan(
      commands: commands,
      summary: '已在本地创建 $pointSummary$constructionSummary。',
    );
  }

  int _parseSideCount(String value) {
    final int? arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    return const <String, int>{
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
      '十一': 11,
      '十二': 12,
    }[value]!;
  }

  List<String>? _parsePolygonLabels(String text) {
    RegExpMatch? match = RegExp(
      r'(?:画|作|绘制|连接)(?:出)?(?:一个)?(?:三角形|多边形)\s*([A-Za-z][A-Za-z0-9_]*(?:\s*(?:、|,|和|与)\s*[A-Za-z][A-Za-z0-9_]*)*|[A-Za-z]{3,12})',
      caseSensitive: false,
    ).firstMatch(text);
    match ??= RegExp(
      r'连接\s*([A-Za-z][A-Za-z0-9_]*(?:\s*(?:、|,|和|与)\s*[A-Za-z][A-Za-z0-9_]*){2,})\s*(?:组成|构成|形成|成)(?:一个)?(?:三角形|多边形)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final String rawLabels = match.group(1)!.trim();
    final List<String> labels;
    if (RegExp(r'^[A-Za-z]{3,12}$').hasMatch(rawLabels)) {
      labels = rawLabels.split('');
    } else {
      labels = rawLabels
          .split(RegExp(r'\s*(?:、|,|和|与)\s*'))
          .where((String label) => label.isNotEmpty)
          .toList(growable: false);
    }

    if (labels.length < 3 || labels.toSet().length != labels.length) {
      return null;
    }
    return labels;
  }

  String _normalize(String input) {
    return input
        .trim()
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('，', ',')
        .replaceAll('²', '^2')
        .replaceAll('³', '^3');
  }
}

class _ParsedPoint {
  const _ParsedPoint({required this.label, required this.x, required this.y});

  final String label;
  final String x;
  final String y;
}
