import 'dart:convert';

import 'package:mathmate/geogebra/geogebra_command_search_service.dart';
import 'package:mathmate/geogebra/geometry_engine.dart';
import 'package:mathmate/geogebra/geometry_plan.dart';
import 'package:mathmate/geogebra/geometry_plan_executor.dart';
import 'package:mathmate/geogebra/geometry_plan_validator.dart';

typedef GeometryCapabilityLoader = Future<Set<String>> Function();

/// Converts the Agent tool payload into a validated, transactional plan.
/// Returning JSON keeps the feedback machine-readable for the next Agent turn.
class GeometryPlanToolHandler {
  GeometryPlanToolHandler({
    required this.engine,
    GeometryCapabilityLoader? capabilityLoader,
  }) : capabilityLoader =
           capabilityLoader ??
           GeogebraCommandSearchService.instance.supportedCommandNames;

  final GeometryEngine engine;
  final GeometryCapabilityLoader capabilityLoader;

  static String describeResult(String encodedResult) {
    try {
      final dynamic decoded = jsonDecode(encodedResult);
      if (decoded is! Map<String, dynamic>) return encodedResult;
      if (decoded['success'] == true) {
        return '计划已完整执行（${decoded['executedSteps'] ?? 0} 步）';
      }
      if (decoded['rolledBack'] == true) {
        return '计划执行失败，画布已恢复：${decoded['error'] ?? '未知错误'}';
      }
      final dynamic issues = decoded['validationIssues'];
      if (issues is List && issues.isNotEmpty && issues.first is Map) {
        final Map<dynamic, dynamic> first = issues.first as Map;
        return '计划被本地校验拒绝：${first['reason'] ?? decoded['error'] ?? '未知原因'}';
      }
      return '计划执行失败：${decoded['error'] ?? '未知错误'}';
    } catch (_) {
      return encodedResult;
    }
  }

  Future<String> execute(Map<String, dynamic> arguments) async {
    final dynamic rawCommands = arguments['commands'];
    if (rawCommands is! List ||
        rawCommands.isEmpty ||
        rawCommands.any((dynamic command) => command is! String)) {
      return jsonEncode(<String, dynamic>{
        'success': false,
        'error': 'commands 必须是非空字符串数组',
      });
    }

    final List<String> commands = rawCommands.cast<String>();
    final dynamic rawSummary = arguments['summary'];
    if (rawSummary != null && rawSummary is! String) {
      return jsonEncode(<String, dynamic>{
        'success': false,
        'error': 'summary 必须是字符串',
      });
    }
    final String summary = (rawSummary as String?)?.trim() ?? '';
    final Set<String> capabilities = await capabilityLoader();
    final GeometryPlanExecutor executor = GeometryPlanExecutor(
      validator: GeometryPlanValidator(allowedCommands: capabilities),
    );
    final GeometryPlanExecutionResult result = await executor.execute(
      plan: GeometryPlan(
        commands: commands,
        summary: summary.isEmpty ? '在线几何计划' : summary,
        source: GeometryPlanSource.online,
      ),
      engine: engine,
    );

    return jsonEncode(<String, dynamic>{
      'success': result.success,
      'executedSteps': result.steps.length,
      'rolledBack': result.rolledBack,
      if (result.error != null) 'error': result.error,
      if (result.validation != null)
        'validationIssues': result.validation!.issues
            .map(
              (GeometryPlanValidationIssue issue) => <String, dynamic>{
                'step': issue.stepIndex,
                'command': issue.command,
                'reason': issue.reason,
              },
            )
            .toList(growable: false),
    });
  }
}
