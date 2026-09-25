import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_task_models.dart';

/// Planning-owned view of a project.
///
/// This is intentionally a read model over the compatibility snapshot while
/// the persisted schema is migrated. New planning code should depend on this
/// boundary rather than reaching into execution fields on ProjectState.
class ProjectPlan {
  const ProjectPlan({
    required this.id,
    required this.title,
    required this.originalGoal,
    required this.refinedGoal,
    required this.criteria,
    required this.constraints,
    required this.tasks,
    required this.milestones,
    required this.planHistory,
  });

  final String id;
  final String title;
  final String originalGoal;
  final String refinedGoal;
  final List<ProjectCriterion> criteria;
  final List<String> constraints;
  final List<ProjectTaskNode> tasks;
  final List<ProjectMilestone> milestones;
  final List<ProjectPlanRevision> planHistory;

  factory ProjectPlan.fromProject(ProjectDocument project) => ProjectPlan(
    id: project.id,
    title: project.title,
    originalGoal: project.originalGoal,
    refinedGoal: project.refinedGoal,
    criteria: List.unmodifiable(project.criteria),
    constraints: List.unmodifiable(project.constraints),
    tasks: List.unmodifiable(project.tasks.map(ProjectTaskNode.fromTask)),
    milestones: List.unmodifiable(project.milestones),
    planHistory: List.unmodifiable(project.planHistory),
  );
}

/// Execution-owned project state. Task steps and run history remain in the
/// task system; this type carries only the project-level execution cursor.
class ProjectExecutionState {
  const ProjectExecutionState({
    required this.activeTaskId,
    required this.currentBatchTaskIds,
    required this.currentBatchIndex,
    required this.currentBatchPlanRevision,
    required this.currentBatchProgressObserved,
    required this.pendingReplanReason,
    required this.pendingReplanTriggers,
    required this.iterationCount,
    required this.maxIterations,
    required this.maxFailedTasks,
    required this.recoveryIncidents,
  });

  final String? activeTaskId;
  final List<String> currentBatchTaskIds;
  final int currentBatchIndex;
  final int currentBatchPlanRevision;
  final bool currentBatchProgressObserved;
  final String? pendingReplanReason;
  final List<ProjectPlanRevisionTrigger> pendingReplanTriggers;
  final int iterationCount;
  final int maxIterations;
  final int maxFailedTasks;
  final List<ProjectRecoveryIncident> recoveryIncidents;

  factory ProjectExecutionState.fromProject(ProjectDocument project) =>
      ProjectExecutionState(
        activeTaskId: project.activeTaskId,
        currentBatchTaskIds: List.unmodifiable(project.currentBatchTaskIds),
        currentBatchIndex: project.currentBatchIndex,
        currentBatchPlanRevision: project.currentBatchPlanRevision,
        currentBatchProgressObserved: project.currentBatchProgressObserved,
        pendingReplanReason: project.pendingReplanReason,
        pendingReplanTriggers: List.unmodifiable(project.pendingReplanTriggers),
        iterationCount: project.iterationCount,
        maxIterations: project.maxIterations,
        maxFailedTasks: project.maxFailedTasks,
        recoveryIncidents: List.unmodifiable(project.recoveryIncidents),
      );
}

/// Evidence and review state owned by project evaluation.
class ProjectEvidenceState {
  const ProjectEvidenceState({
    required this.artifacts,
    required this.evidence,
    required this.completionReviewCheckpoint,
  });

  final List<TaskArtifact> artifacts;
  final List<ProjectEvidence> evidence;
  final ProjectCompletionReviewCheckpoint? completionReviewCheckpoint;

  factory ProjectEvidenceState.fromProject(ProjectDocument project) =>
      ProjectEvidenceState(
        artifacts: List.unmodifiable(project.artifacts),
        evidence: List.unmodifiable(project.evidence),
        completionReviewCheckpoint: project.completionReviewCheckpoint,
      );
}

/// Control state presented to the application. The legacy fields remain in
/// ProjectState for snapshot compatibility, but callers can consume one
/// explicit object instead of inferring a stop condition.
class ProjectControlState {
  const ProjectControlState({
    required this.boundary,
    required this.status,
    required this.blocker,
    required this.openQuestions,
    required this.pendingPlanApproval,
  });

  final ProjectBoundary? boundary;
  final ProjectStatus status;
  final ProjectBlocker? blocker;
  final List<PendingProjectQuestion> openQuestions;
  final PendingProjectPlanApproval? pendingPlanApproval;

  factory ProjectControlState.fromProject(ProjectDocument project) =>
      ProjectControlState(
        boundary: project.boundary,
        status: project.status,
        blocker: project.blocker,
        openQuestions: List.unmodifiable(project.openQuestions),
        pendingPlanApproval: project.pendingPlanApproval,
      );
}

extension ProjectStateBoundaries on ProjectDocument {
  ProjectPlan get plan => ProjectPlan.fromProject(this);

  ProjectExecutionState get execution =>
      ProjectExecutionState.fromProject(this);

  ProjectEvidenceState get evidenceState =>
      ProjectEvidenceState.fromProject(this);

  ProjectControlState get control => ProjectControlState.fromProject(this);
}
