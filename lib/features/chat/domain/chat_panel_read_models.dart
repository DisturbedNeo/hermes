import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/task/domain/task.dart';

export 'package:hermes/features/project/domain/project.dart'
    show
        ProjectBlocker,
        ProjectBlockerType,
        ProjectCriterion,
        ProjectCriterionStatus,
        ProjectDecisionRecord,
        ProjectDiagnostics,
        ProjectEvidence,
        ProjectEvidenceStatus,
        ProjectMilestone,
        ProjectMilestoneStatus,
        ProjectMemoryEntry,
        ProjectPlanRevision,
        ProjectRecoveryIncident,
        ProjectRecoveryIncidentStatus,
        ProjectStatus,
        ProjectSummary,
        ProjectDecisionType,
        ProjectEvidenceType,
        TaskReadiness,
        PendingProjectPlanApproval,
        PendingProjectQuestion;
export 'package:hermes/features/project/application/contracts/project_task_models.dart';
export 'package:hermes/features/project/application/contracts/project_workspace_graph.dart';
export 'package:hermes/features/task/application/contracts/task_planning_types.dart';
export 'package:hermes/features/task/application/contracts/task_execution_contracts.dart';
export 'package:hermes/features/task/domain/task.dart'
    show
        PendingTaskApproval,
        PendingTaskQuestion,
        ExecutionMode,
        TaskFailure,
        TaskRun,
        TaskRunStatus,
        TaskStatus,
        TaskStep,
        TaskStepStatus;

extension ChatProjectStatusWire on ProjectStatus {
  String get wire => switch (this) {
    ProjectStatus.runningTask => 'running_task',
    ProjectStatus.reviewingTask => 'reviewing_task',
    ProjectStatus.waitingForUser => 'waiting_for_user',
    _ => name,
  };
}

extension ChatProjectBlockerTypeWire on ProjectBlockerType {
  String get wire => switch (this) {
    ProjectBlockerType.taskEditApproval => 'task_edit_approval',
    ProjectBlockerType.taskBlocked => 'task_blocked',
    ProjectBlockerType.taskFailed => 'task_failed',
    ProjectBlockerType.recoveryFailed => 'recovery_failed',
    ProjectBlockerType.duplicateTask => 'duplicate_task',
    ProjectBlockerType.oversizedTask => 'oversized_task',
    ProjectBlockerType.maxFailures => 'max_failures',
    ProjectBlockerType.planApproval => 'plan_approval',
    _ => name,
  };
}

extension ChatProjectDecisionTypeWire on ProjectDecisionType {
  String get wire => switch (this) {
    ProjectDecisionType.createTask => 'create_task',
    ProjectDecisionType.createRecoveryTask => 'create_recovery_task',
    ProjectDecisionType.rejectTask => 'reject_task',
    ProjectDecisionType.splitTask => 'split_task',
    ProjectDecisionType.evaluateTask => 'evaluate_task',
    ProjectDecisionType.retryRecovery => 'retry_recovery',
    ProjectDecisionType.applyPlanRevision => 'apply_plan_revision',
    ProjectDecisionType.approvePlanRevision => 'approve_plan_revision',
    ProjectDecisionType.rejectPlanRevision => 'reject_plan_revision',
    _ => name,
  };
}

extension ChatTaskStepStatusWire on TaskStepStatus {
  String get wire => name;
}

extension ChatTaskRunStatusWire on TaskRunStatus {
  String get wire => this == TaskRunStatus.needsReplan ? 'needs_replan' : name;
}

/// Scheduler output needed by the project panel without exposing an aggregate.
class ProjectScheduleReadModel {
  const ProjectScheduleReadModel({
    required this.readiness,
    required this.readinessReasons,
  });

  final Map<String, TaskReadiness> readiness;
  final Map<String, List<String>> readinessReasons;

  TaskReadiness readinessFor(String taskId) =>
      readiness[taskId] ?? TaskReadiness.notEligible;

  List<String> reasonsFor(String taskId) =>
      readinessReasons[taskId] ?? const [];
}

/// Bounded workspace context prepared for display.
class ProjectWorkspaceContextReadModel {
  const ProjectWorkspaceContextReadModel({
    required this.orientation,
    required this.nodes,
    required this.edges,
    required this.maxCharacters,
    required this.usedCharacters,
    required this.truncated,
  });

  final String orientation;
  final List<ProjectWorkspaceNode> nodes;
  final List<ProjectWorkspaceEdge> edges;
  final int maxCharacters;
  final int usedCharacters;
  final bool truncated;
}

/// Immutable task projection owned by the chat presentation boundary.
class TaskPanelReadModel {
  const TaskPanelReadModel({
    required this.id,
    required this.title,
    required this.objective,
    required this.status,
    required this.steps,
    required this.runs,
    required this.pendingApproval,
    required this.pendingQuestion,
    required this.planningMetrics,
    required this.memorySummary,
    required this.doneCriteria,
    required this.outOfScope,
    required this.currentStepId,
    required this.projectId,
    required this.chatSessionId,
    required this.failure,
  });

  final String id;
  final String title;
  final String objective;
  final TaskStatus status;
  final List<TaskStep> steps;
  final List<TaskRun> runs;
  final PendingTaskApproval? pendingApproval;
  final PendingTaskQuestion? pendingQuestion;
  final PlanningMetrics planningMetrics;
  final String memorySummary;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final String? currentStepId;
  final String? projectId;
  final String? chatSessionId;
  final TaskFailure? failure;

  String? get failureKey => failure?.failureKey;
  int get unresolvedErrorCount => failure?.unresolvedErrorCount ?? 0;

  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.rejected ||
      status == TaskStatus.split ||
      status == TaskStatus.cancelled ||
      status == TaskStatus.failed;

  TaskStep? get nextRunnableStep => steps
      .where(
        (step) =>
            step.status == TaskStepStatus.pending ||
            step.status == TaskStepStatus.approved ||
            step.status == TaskStepStatus.blocked ||
            step.status == TaskStepStatus.failed,
      )
      .firstOrNull;

  TaskStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }
}

/// Immutable project projection owned by the chat presentation boundary.
class ProjectPanelReadModel {
  const ProjectPanelReadModel({
    required this.id,
    required this.title,
    required this.originalGoal,
    required this.refinedGoal,
    required this.status,
    required this.activeTaskId,
    required this.chatSessionId,
    required this.iterationCount,
    required this.maxIterations,
    required this.completionSummary,
    required this.constraints,
    required this.tasks,
    required this.artifacts,
    required this.criteria,
    required this.recoveryIncidents,
    required this.evidence,
    required this.milestones,
    required this.memory,
    required this.decisions,
    required this.planHistory,
    required this.workspaceGraph,
    required this.pendingPlanApproval,
    required this.blocker,
    required this.openQuestions,
    required this.diagnostics,
    required this.schedule,
    required this.orderedReadyTasks,
    required this.workspaceContext,
  });

  final String id;
  final String title;
  final String originalGoal;
  final String refinedGoal;
  final ProjectStatus status;
  final String? activeTaskId;
  final String? chatSessionId;
  final int iterationCount;
  final int maxIterations;
  final String completionSummary;
  final List<String> constraints;
  final List<ProjectTaskNode> tasks;
  final List<TaskArtifact> artifacts;
  final List<ProjectCriterion> criteria;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final List<ProjectEvidence> evidence;
  final List<ProjectMilestone> milestones;
  final List<ProjectMemoryEntry> memory;
  final List<ProjectDecisionRecord> decisions;
  final List<ProjectPlanRevision> planHistory;
  final ProjectWorkspaceGraph workspaceGraph;
  final PendingProjectPlanApproval? pendingPlanApproval;
  final ProjectBlocker? blocker;
  final List<PendingProjectQuestion> openQuestions;
  final ProjectDiagnostics diagnostics;
  final ProjectScheduleReadModel schedule;
  final List<ProjectTaskNode> orderedReadyTasks;
  final ProjectWorkspaceContextReadModel workspaceContext;

  bool get isTerminal =>
      status == ProjectStatus.completed ||
      status == ProjectStatus.cancelled ||
      status == ProjectStatus.failed;

  ProjectTaskNode? taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  String criterionStatement(String id) {
    for (final criterion in criteria) {
      if (criterion.id == id) return criterion.statement;
    }
    return id;
  }
}
