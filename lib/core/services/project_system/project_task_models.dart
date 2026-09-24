import 'package:hermes/core/models/task.dart';

/// Planner-owned description of a task.
///
/// This deliberately contains no execution IDs, step state, run history, or
/// persistence metadata. The project planner can exchange this shape without
/// accidentally treating an executable task document as authoritative plan
/// input.
class ProjectTaskSpec {
  final String ref;
  final String title;
  final String objective;
  final List<String> criterionRefs;
  final List<String> dependencyRefs;
  final String? milestoneRef;
  final TaskPriority priority;
  final TaskRisk risk;
  final ProjectRiskReduction riskReduction;
  final TaskEffort effort;
  final String selectionRationale;
  final List<String> constraints;
  final List<String> readPaths;
  final List<String> writePaths;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> context;
  final List<TaskArtifact> expectedArtifacts;

  const ProjectTaskSpec({
    this.ref = '',
    this.title = '',
    this.objective = '',
    this.criterionRefs = const [],
    this.dependencyRefs = const [],
    this.milestoneRef,
    this.priority = TaskPriority.normal,
    this.risk = TaskRisk.unknown,
    this.riskReduction = ProjectRiskReduction.none,
    this.effort = TaskEffort.small,
    this.selectionRationale = '',
    this.constraints = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.context = const [],
    this.expectedArtifacts = const [],
  });
}

/// The project-owned identity of a task document.
///
/// Task content and execution history remain in the task system. Projects
/// persist IDs and use refs when planning or scheduling work.
class ProjectTaskRef {
  final String id;
  final int planRevision;

  const ProjectTaskRef({required this.id, required this.planRevision});
}

/// Execution-owned observation of a canonical task document.
///
/// It is intentionally an adapter rather than a second persisted task model;
/// it lets project orchestration consume execution state without making the
/// planning representation own task steps or run history.
class TaskExecution {
  final String taskId;
  final TaskStatus status;
  final String? currentStepId;
  final int persistenceRevision;
  final TaskRun? latestRun;
  final DateTime observedAt;

  const TaskExecution({
    required this.taskId,
    required this.status,
    required this.persistenceRevision,
    required this.observedAt,
    this.currentStepId,
    this.latestRun,
  });

  factory TaskExecution.fromTask(Task task, {DateTime? observedAt}) =>
      TaskExecution(
        taskId: task.id,
        status: task.status,
        currentStepId: task.currentStepId,
        persistenceRevision: task.persistenceRevision,
        latestRun: task.runs.isEmpty ? null : task.runs.last,
        observedAt: observedAt ?? DateTime.now(),
      );
}
