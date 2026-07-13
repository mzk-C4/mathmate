import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geometry_engine.dart';
import 'package:mathmate/geogebra/geometry_plan_tool_handler.dart';

void main() {
  test('executes an online plan as one transaction', () async {
    final _FakeEngine engine = _FakeEngine();
    final GeometryPlanToolHandler handler = GeometryPlanToolHandler(
      engine: engine,
      capabilityLoader: () async => <String>{'circle', 'polygon'},
    );

    final Map<String, dynamic> result =
        jsonDecode(
              await handler.execute(<String, dynamic>{
                'commands': <String>['A = (0, 0)', 'Circle(A, 2)'],
                'summary': '创建圆',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(result['executedSteps'], 2);
    expect(engine.commands, <String>['A = (0, 0)', 'Circle(A, 2)']);
    expect(engine.undoPoints, 2);
  });

  test('rolls back the complete online plan after a failed step', () async {
    final _FakeEngine engine = _FakeEngine(failingCommand: 'Polygon(A, B, C)');
    final GeometryPlanToolHandler handler = GeometryPlanToolHandler(
      engine: engine,
      capabilityLoader: () async => <String>{'polygon'},
    );

    final Map<String, dynamic> result =
        jsonDecode(
              await handler.execute(<String, dynamic>{
                'commands': <String>[
                  'A = (0, 0)',
                  'B = (2, 0)',
                  'Polygon(A, B, C)',
                ],
                'summary': '三角形',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(result['rolledBack'], isTrue);
    expect(engine.restoredXml, '<construction/>');
  });

  test(
    'rejects unknown or forbidden commands before touching the engine',
    () async {
      final _FakeEngine engine = _FakeEngine();
      final GeometryPlanToolHandler handler = GeometryPlanToolHandler(
        engine: engine,
        capabilityLoader: () async => <String>{'circle', 'setvalue'},
      );

      final Map<String, dynamic> result =
          jsonDecode(
                await handler.execute(<String, dynamic>{
                  'commands': <String>['SetValue(a, 2)'],
                  'summary': 'unsafe',
                }),
              )
              as Map<String, dynamic>;

      expect(result['success'], isFalse);
      expect(result['validationIssues'], isNotEmpty);
      expect(engine.xmlReads, 0);
    },
  );

  test('rejects malformed tool arguments', () async {
    final _FakeEngine engine = _FakeEngine();
    final GeometryPlanToolHandler handler = GeometryPlanToolHandler(
      engine: engine,
      capabilityLoader: () async => <String>{'circle'},
    );

    final Map<String, dynamic> result =
        jsonDecode(
              await handler.execute(<String, dynamic>{
                'commands': 'Circle(A, 2)',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(engine.xmlReads, 0);
  });

  test('formats structured execution feedback for the chat UI', () {
    expect(
      GeometryPlanToolHandler.describeResult(
        jsonEncode(<String, dynamic>{
          'success': true,
          'executedSteps': 3,
          'rolledBack': false,
        }),
      ),
      '计划已完整执行（3 步）',
    );
    expect(
      GeometryPlanToolHandler.describeResult(
        jsonEncode(<String, dynamic>{
          'success': false,
          'rolledBack': true,
          'error': '第三步失败',
        }),
      ),
      contains('画布已恢复'),
    );
  });
}

class _FakeEngine implements GeometryEngine {
  _FakeEngine({this.failingCommand});

  final String? failingCommand;
  final List<String> commands = <String>[];
  int undoPoints = 0;
  int xmlReads = 0;
  String? restoredXml;

  @override
  Future<GeometryEngineCommandResult> executeCommand(String command) async {
    commands.add(command);
    if (command == failingCommand) {
      return const GeometryEngineCommandResult(
        success: false,
        error: 'simulated failure',
      );
    }
    return const GeometryEngineCommandResult(success: true);
  }

  @override
  Future<String> getXML() async {
    xmlReads++;
    return '<construction/>';
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
