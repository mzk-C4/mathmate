import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/geogebra/geometry_plan.dart';
import 'package:mathmate/geogebra/geometry_plan_validator.dart';

void main() {
  const GeometryPlanValidator validator = GeometryPlanValidator();

  test('accepts supported local geometry commands and assignments', () {
    final GeometryPlan plan = GeometryPlan(
      commands: <String>[
        'A = (0, 0)',
        'B = (4, 0)',
        'Polygon(A, B, 6)',
        'y = sin(x) + sqrt(abs(x))',
      ],
      summary: 'test',
    );

    expect(validator.validate(plan).isValid, isTrue);
  });

  test('rejects hallucinated or unsafe commands', () {
    final GeometryPlan plan = GeometryPlan(
      commands: <String>['RegularPolygon(A, B, 6)', 'A = Execute("DeleteAll")'],
      summary: 'test',
    );

    final GeometryPlanValidationResult result = validator.validate(plan);
    expect(result.isValid, isFalse);
    expect(result.issues, hasLength(2));
    expect(result.issues.first.reason, contains('白名单'));

    for (final String command in <String>[
      'A = RegularPolygon(B, C, 6)',
      'y = Delete(A)',
    ]) {
      expect(
        validator
            .validate(
              GeometryPlan(commands: <String>[command], summary: 'test'),
            )
            .isValid,
        isFalse,
      );
    }
  });

  test('rejects empty and oversized plans', () {
    expect(
      validator
          .validate(
            const GeometryPlan.steps(steps: <GeometryStep>[], summary: 'empty'),
          )
          .isValid,
      isFalse,
    );
    final GeometryPlan tooLarge = GeometryPlan(
      commands: List<String>.filled(33, 'A = (0, 0)'),
      summary: 'large',
    );
    expect(validator.validate(tooLarge).isValid, isFalse);
  });

  test('uses the bundled capability set only for online plans', () {
    const GeometryPlanValidator onlineValidator = GeometryPlanValidator(
      allowedCommands: <String>{'rotate', 'circle', 'setvalue'},
    );
    final GeometryPlan onlinePlan = GeometryPlan(
      commands: <String>['B = Rotate(A, 45°, O)', 'Circle(B, 2)'],
      summary: 'online',
      source: GeometryPlanSource.online,
    );
    final GeometryPlan localPlan = GeometryPlan(
      commands: <String>['B = Rotate(A, 45°, O)'],
      summary: 'local',
    );

    expect(onlineValidator.validate(onlinePlan).isValid, isTrue);
    expect(onlineValidator.validate(localPlan).isValid, isFalse);
    expect(
      onlineValidator
          .validate(
            GeometryPlan(
              commands: <String>['SetValue(a, 2)'],
              summary: 'forbidden',
              source: GeometryPlanSource.online,
            ),
          )
          .isValid,
      isFalse,
    );
  });
}
