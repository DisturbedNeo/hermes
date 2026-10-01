import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';

enum ProjectPlanPatchSource {
  initialization,
  incrementalRevision,
  taskSplit,
  recovery,
  user,
}

/// Common typed envelope for every model- or user-produced plan change.
///
/// The desired plan remains complete so validation can reject omissions and
/// reconciliation can preserve runtime history. The envelope gives all
/// producers one application protocol without making model output authoritative
/// over execution state.
class ProjectPlanPatch {
  const ProjectPlanPatch({
    required this.plan,
    required this.source,
    this.title,
    this.refinedGoal,
    this.constraints,
  });

  final ProjectDesiredPlan plan;
  final ProjectPlanPatchSource source;

  /// Initial planning edits the project header in the same transaction as the
  /// plan. Incremental patches leave these null.
  final String? title;
  final String? refinedGoal;
  final List<String>? constraints;

  int get revision => plan.revision;
  List<ProjectPlanRevisionTrigger> get triggers => plan.triggers;

  factory ProjectPlanPatch.initial(
    ProjectDesiredPlan plan, {
    String? title,
    String? refinedGoal,
    List<String>? constraints,
  }) => ProjectPlanPatch(
    plan: plan,
    source: ProjectPlanPatchSource.initialization,
    title: title,
    refinedGoal: refinedGoal,
    constraints: constraints,
  );

  factory ProjectPlanPatch.incremental(ProjectDesiredPlan plan) =>
      ProjectPlanPatch(
        plan: plan,
        source: ProjectPlanPatchSource.incrementalRevision,
      );

  factory ProjectPlanPatch.split(ProjectDesiredPlan plan) =>
      ProjectPlanPatch(plan: plan, source: ProjectPlanPatchSource.taskSplit);
}
