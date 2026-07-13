enum GeometryPlanSource { local, online }

class GeometryStep {
  const GeometryStep({required this.command, this.purpose});

  final String command;
  final String? purpose;
}

/// A platform-independent description of one atomic canvas change requested
/// by the user. Plans are validated before they can reach GeoGebra.
class GeometryPlan {
  factory GeometryPlan({
    required List<String> commands,
    required String summary,
    GeometryPlanSource source = GeometryPlanSource.local,
  }) {
    return GeometryPlan.steps(
      steps: commands
          .map((String command) => GeometryStep(command: command))
          .toList(growable: false),
      summary: summary,
      source: source,
    );
  }

  const GeometryPlan.steps({
    required this.steps,
    required this.summary,
    this.source = GeometryPlanSource.local,
  });

  final List<GeometryStep> steps;
  final String summary;
  final GeometryPlanSource source;

  List<String> get commands =>
      steps.map((GeometryStep step) => step.command).toList(growable: false);
}
