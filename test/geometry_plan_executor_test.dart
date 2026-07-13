import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geometry_engine.dart';
import 'package:mathmate/geogebra/geometry_plan.dart';
import 'package:mathmate/geogebra/geometry_plan_executor.dart';

void main() {
  test('executes a valid plan and creates one undo transaction', () async {
    final _FakeGeometryEngine engine = _FakeGeometryEngine();
    final GeometryPlan plan = GeometryPlan(
      commands: <String>['A = (0, 0)', 'Circle(A, 3)'],
      summary: 'circle',
    );

    final GeometryPlanExecutionResult result =
        await const GeometryPlanExecutor().execute(plan: plan, engine: engine);

    expect(result.success, isTrue);
    expect(engine.commands, plan.commands);
    expect(engine.undoPoints, 2);
    expect(engine.restoredXml, isNull);
  });

  test('restores the XML snapshot after a failed step', () async {
    final _FakeGeometryEngine engine = _FakeGeometryEngine(failAt: 1);
    final GeometryPlan plan = GeometryPlan(
      commands: <String>['A = (0, 0)', 'Circle(A, 3)', 'Segment(A, B)'],
      summary: 'partial failure',
    );

    final GeometryPlanExecutionResult result =
        await const GeometryPlanExecutor().execute(plan: plan, engine: engine);

    expect(result.success, isFalse);
    expect(result.rolledBack, isTrue);
    expect(engine.commands, <String>['A = (0, 0)', 'Circle(A, 3)']);
    expect(engine.restoredXml, '<construction />');
  });

  test('does not touch the engine when validation fails', () async {
    final _FakeGeometryEngine engine = _FakeGeometryEngine();
    final GeometryPlan plan = GeometryPlan(
      commands: <String>['RegularPolygon(A, B, 6)'],
      summary: 'invalid',
    );

    final GeometryPlanExecutionResult result =
        await const GeometryPlanExecutor().execute(plan: plan, engine: engine);

    expect(result.success, isFalse);
    expect(result.validation?.isValid, isFalse);
    expect(engine.snapshotReads, 0);
    expect(engine.commands, isEmpty);
  });
}

class _FakeGeometryEngine implements GeometryEngine {
  _FakeGeometryEngine({this.failAt});

  final int? failAt;
  final List<String> commands = <String>[];
  int snapshotReads = 0;
  int undoPoints = 0;
  String? restoredXml;

  @override
  Future<GeometryEngineCommandResult> executeCommand(String command) async {
    commands.add(command);
    final bool succeeds = commands.length - 1 != failAt;
    return GeometryEngineCommandResult(
      success: succeeds,
      error: succeeds ? null : 'simulated failure',
    );
  }

  @override
  Future<String> getXML() async {
    snapshotReads++;
    return '<construction />';
  }

  @override
  Future<bool> setUndoPoint() async {
    undoPoints++;
    return true;
  }

  @override
  Future<bool> setXML(String xml) async {
    restoredXml = xml;
    return true;
  }
}
