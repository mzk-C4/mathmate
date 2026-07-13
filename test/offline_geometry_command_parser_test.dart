import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/offline_geometry_command_parser.dart';

void main() {
  const parser = OfflineGeometryCommandParser();

  test('parses a point with Chinese punctuation', () {
    final plan = parser.parse('画一个点 A，坐标是（1，2）');
    expect(plan?.commands, <String>['A = (1, 2)']);
    expect(parser.parse('在（-2，3）处创建点 B')?.commands, <String>['B = (-2, 3)']);
  });

  test('parses a fixed-radius circle', () {
    final plan = parser.parse('以 A 为圆心，半径为 3 画圆');
    expect(plan?.commands, <String>['Circle(A, 3)']);
    expect(parser.parse('画一个圆，圆心是 B，半径是 2.5')?.commands, <String>[
      'Circle(B, 2.5)',
    ]);
  });

  test('parses a segment and a function', () {
    expect(parser.parse('画线段 A 和 B')?.commands, <String>['Segment(A, B)']);
    expect(parser.parse('画出 y = x²')?.commands, <String>['y = x^2']);
    expect(parser.parse('y=x²')?.commands, <String>['y=x^2']);
    expect(parser.parse('连接 A 和 B')?.commands, <String>['Segment(A, B)']);
    expect(parser.parse('作线段 CD')?.commands, <String>['Segment(C, D)']);
  });

  test('parses perpendicular and parallel constructions', () {
    expect(parser.parse('过点 A 作直线 g 的垂线')?.commands, <String>[
      'PerpendicularLine(A, g)',
    ]);
    expect(parser.parse('过 A 画 g 的平行线')?.commands, <String>[
      'ParallelLine(A, g)',
    ]);
    expect(parser.parse('作过 B 且与 h 垂直的直线')?.commands, <String>[
      'PerpendicularLine(B, h)',
    ]);
    expect(parser.parse('画过 C 与 k 平行的直线')?.commands, <String>[
      'ParallelLine(C, k)',
    ]);
  });

  test('parses intersection and tangent constructions', () {
    expect(parser.parse('求直线 g 与直线 h 的交点')?.commands, <String>[
      'Intersect(g, h)',
    ]);
    expect(parser.parse('从点 A 作圆 c 的切线')?.commands, <String>['Tangent(A, c)']);
  });

  test('parses compact and separated polygon labels', () {
    expect(parser.parse('画一个三角形 ABC')?.commands, <String>['Polygon(A, B, C)']);
    expect(parser.parse('绘制多边形 A、B、C、D')?.commands, <String>[
      'Polygon(A, B, C, D)',
    ]);
    expect(parser.parse('连接 A、B、C 构成三角形')?.commands, <String>[
      'Polygon(A, B, C)',
    ]);
    expect(parser.parse('画一个正六边形')?.commands, <String>[
      'P_1 = (-2, 0)',
      'P_2 = (2, 0)',
      'Polygon(P_1, P_2, 6)',
    ]);
    expect(parser.parse('创建正12边形')?.commands.last, 'Polygon(P_1, P_2, 12)');
  });

  test('parses compact midpoint notation', () {
    expect(parser.parse('求线段 AB 的中点')?.commands, <String>['Midpoint(A, B)']);
  });

  test('rejects invalid polygon labels', () {
    expect(parser.parse('画多边形 A、B'), isNull);
    expect(parser.parse('画三角形 A、B、A'), isNull);
  });

  test('does not guess a complex construction', () {
    expect(parser.parse('请证明这个三角形的九点圆定理'), isNull);
    expect(parser.parse('画出 y = x² 和它的切线'), isNull);
  });
}
