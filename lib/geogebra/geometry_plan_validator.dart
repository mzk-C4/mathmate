import 'package:mathmate/geogebra/geometry_plan.dart';

class GeometryPlanValidationIssue {
  const GeometryPlanValidationIssue({
    required this.stepIndex,
    required this.command,
    required this.reason,
  });

  final int stepIndex;
  final String command;
  final String reason;
}

class GeometryPlanValidationResult {
  const GeometryPlanValidationResult(this.issues);

  final List<GeometryPlanValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

/// Initial allow-list for the locally generated plans. It is intentionally
/// strict; the online planner will later use a generated runtime capability
/// catalog instead of widening this list blindly.
class GeometryPlanValidator {
  const GeometryPlanValidator({
    this.maxSteps = 32,
    this.maxCommandLength = 512,
    this.allowedCommands,
  });

  final int maxSteps;
  final int maxCommandLength;
  final Set<String>? allowedCommands;

  static const Set<String> _localAllowedCommands = <String>{
    'circle',
    'intersect',
    'midpoint',
    'parallelline',
    'perpendicularline',
    'polygon',
    'segment',
    'tangent',
  };

  static const Set<String> _forbiddenCommands = <String>{
    'delete',
    'execute',
    'runclickscript',
    'runupdatescript',
    'setconstructionstep',
    'setseed',
    'setvalue',
    'startanimation',
  };

  static const Set<String> _allowedExpressionFunctions = <String>{
    'abs',
    'acos',
    'asin',
    'atan',
    'ceil',
    'cos',
    'exp',
    'floor',
    'ln',
    'log',
    'max',
    'min',
    'round',
    'sin',
    'sqrt',
    'tan',
  };

  static final RegExp _assignment = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\s*\([^)]*\))?\s*=\s*.+$',
  );
  static final RegExp _commandCall = RegExp(r'^([A-Za-z][A-Za-z0-9_]*)\s*\(');
  static final RegExp _forbiddenAssignmentCall = RegExp(
    r'\b(?:Execute|RunClickScript|RunUpdateScript|SetValue|StartAnimation)\s*\(',
    caseSensitive: false,
  );

  GeometryPlanValidationResult validate(GeometryPlan plan) {
    final List<GeometryPlanValidationIssue> issues =
        <GeometryPlanValidationIssue>[];

    if (plan.steps.isEmpty) {
      issues.add(
        const GeometryPlanValidationIssue(
          stepIndex: -1,
          command: '',
          reason: '计划中没有可执行步骤',
        ),
      );
      return GeometryPlanValidationResult(issues);
    }
    if (plan.steps.length > maxSteps) {
      issues.add(
        GeometryPlanValidationIssue(
          stepIndex: -1,
          command: '',
          reason: '计划步骤超过上限 $maxSteps',
        ),
      );
      return GeometryPlanValidationResult(issues);
    }

    for (int index = 0; index < plan.steps.length; index++) {
      final String command = plan.steps[index].command.trim();
      String? reason;
      if (command.isEmpty) {
        reason = '命令为空';
      } else if (command.length > maxCommandLength) {
        reason = '命令长度超过上限 $maxCommandLength';
      } else if (command.contains('\n') || command.contains('\r')) {
        reason = '命令不能包含换行';
      } else if (_assignment.hasMatch(command)) {
        if (_forbiddenAssignmentCall.hasMatch(command)) {
          reason = '赋值表达式包含禁止调用';
        } else {
          final String expression = command.substring(command.indexOf('=') + 1);
          for (final RegExpMatch match in RegExp(
            r'\b([A-Za-z][A-Za-z0-9_]*)\s*\(',
          ).allMatches(expression)) {
            final String call = match.group(1)!;
            if (!_isAllowedExpressionCall(plan, call)) {
              reason = '赋值表达式包含不受支持的调用 $call';
              break;
            }
          }
        }
      } else {
        final RegExpMatch? call = _commandCall.firstMatch(command);
        if (call == null) {
          reason = '不是受支持的 GeoGebra 表达式';
        } else if (!_isAllowedCommand(call.group(1)!)) {
          reason = '命令 ${call.group(1)} 不在本地能力白名单中';
        }
      }

      if (reason != null) {
        issues.add(
          GeometryPlanValidationIssue(
            stepIndex: index,
            command: command,
            reason: reason,
          ),
        );
      }
    }
    return GeometryPlanValidationResult(issues);
  }

  bool _isAllowedExpressionCall(GeometryPlan plan, String call) {
    final String normalized = call.toLowerCase();
    if (_forbiddenCommands.contains(normalized)) return false;
    if (_allowedExpressionFunctions.contains(normalized)) return true;
    return plan.source == GeometryPlanSource.online &&
        _isAllowedCommand(normalized);
  }

  bool _isAllowedCommand(String command) {
    final String normalized = command.toLowerCase();
    if (_forbiddenCommands.contains(normalized)) return false;
    return (allowedCommands ?? _localAllowedCommands).contains(normalized);
  }
}
