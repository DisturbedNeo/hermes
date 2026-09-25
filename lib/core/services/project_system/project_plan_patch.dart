import 'package:hermes/core/models/project.dart';

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
  const ProjectPlanPatch({required this.plan, required this.source});

  final ProjectDesiredPlan plan;
  final ProjectPlanPatchSource source;

  int get revision => plan.revision;
  List<ProjectPlanRevisionTrigger> get triggers => plan.triggers;

  factory ProjectPlanPatch.initial(ProjectDesiredPlan plan) => ProjectPlanPatch(
    plan: plan,
    source: ProjectPlanPatchSource.initialization,
  );

  factory ProjectPlanPatch.incremental(ProjectDesiredPlan plan) =>
      ProjectPlanPatch(
        plan: plan,
        source: ProjectPlanPatchSource.incrementalRevision,
      );

  factory ProjectPlanPatch.split(ProjectDesiredPlan plan) =>
      ProjectPlanPatch(plan: plan, source: ProjectPlanPatchSource.taskSplit);
}
