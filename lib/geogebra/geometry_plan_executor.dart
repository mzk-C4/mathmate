import 'package:mathmate/geogebra/geometry_engine.dart';
import 'package:mathmate/geogebra/geometry_plan.dart';
import 'package:mathmate/geogebra/geometry_plan_validator.dart';

class GeometryStepExecution {
  const GeometryStepExecution({
    required this.step,
    required this.success,
    this.label,
    this.error,
  });

  final GeometryStep step;
  final bool success;
  final String? label;
  final String? error;
}

class GeometryPlanExecutionResult {
  const GeometryPlanExecutionResult({
    required this.success,
    required this.steps,
    this.validation,
    this.rolledBack = false,
    this.error,
  });

  final bool success;
  final List<GeometryStepExecution> steps;
  final GeometryPlanValidationResult? validation;
  final bool rolledBack;
  final String? error;
}

/// Executes one user request as a transaction. A failed step restores the XML
/// snapshot so the canvas never remains in a partially constructed state.
class GeometryPlanExecutor {
  const GeometryPlanExecutor({this.validator = const GeometryPlanValidator()});

  final GeometryPlanValidator validator;

  Future<GeometryPlanExecutionResult> execute({
    required GeometryPlan plan,
    required GeometryEngine engine,
  }) async {
    final GeometryPlanValidationResult validation = validator.validate(plan);
    if (!validation.isValid) {
      return GeometryPlanExecutionResult(
        success: false,
        steps: const <GeometryStepExecution>[],
        validation: validation,
        error: validation.issues.first.reason,
      );
    }

    final List<GeometryStepExecution> executed = <GeometryStepExecution>[];
    String? snapshot;
    try {
      snapshot = await engine.getXML();
      await engine.setUndoPoint();
      for (final GeometryStep step in plan.steps) {
        final GeometryEngineCommandResult result = await engine.executeCommand(
          step.command,
        );
        executed.add(
          GeometryStepExecution(
            step: step,
            success: result.success,
            label: result.label,
            error: result.error,
          ),
        );
        if (!result.success) {
          final bool rolledBack = await _rollback(engine, snapshot);
          return GeometryPlanExecutionResult(
            success: false,
            steps: List<GeometryStepExecution>.unmodifiable(executed),
            rolledBack: rolledBack,
            error: result.error ?? '命令执行失败',
          );
        }
      }
      await engine.setUndoPoint();
      return GeometryPlanExecutionResult(
        success: true,
        steps: List<GeometryStepExecution>.unmodifiable(executed),
      );
    } catch (error) {
      final bool rolledBack = snapshot == null
          ? false
          : await _rollback(engine, snapshot);
      return GeometryPlanExecutionResult(
        success: false,
        steps: List<GeometryStepExecution>.unmodifiable(executed),
        rolledBack: rolledBack,
        error: error.toString(),
      );
    }
  }

  Future<bool> _rollback(GeometryEngine engine, String snapshot) async {
    try {
      final bool restored = await engine.setXML(snapshot);
      if (restored) await engine.setUndoPoint();
      return restored;
    } catch (_) {
      return false;
    }
  }
}
