import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';

export 'package:hermes/features/project/application/contracts/project_snapshot_models.dart'
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
export 'package:hermes/features/task/application/contracts/task_snapshot_models.dart'
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
export 'package:hermes/features/project/domain/project_scheduler.dart'
    show ProjectScheduleResult;

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

/// Immutable task projection owned by the chat presentation boundary.
///
/// The aggregate is retained only inside the runtime while commands execute;
/// callers of this projection receive the fields needed to render the task
/// panel and never receive the aggregate itself.
class TaskPanelReadModel {
  const TaskPanelReadModel._(this._source);

  factory TaskPanelReadModel.fromAggregate(Task? source) => source == null
      ? throw ArgumentError.notNull('source')
      : TaskPanelReadModel._(source);

  final Task _source;

  String get id => _source.id;
  String get title => _source.title;
  String get objective => _source.objective;
  TaskStatus get status => _source.status;
  List<TaskStep> get steps => _source.steps;
  List<TaskRun> get runs => _source.runs;
  PendingTaskApproval? get pendingApproval => _source.pendingApproval;
  PendingTaskQuestion? get pendingQuestion => _source.pendingQuestion;
  PlanningMetrics get planningMetrics => _source.planningMetrics;
  String get memorySummary => _source.memorySummary;
  List<String> get doneCriteria => _source.doneCriteria;
  List<String> get outOfScope => _source.outOfScope;
  String? get currentStepId => _source.currentStepId;
  String? get projectId => _source.projectId;
  String? get chatSessionId => _source.chatSessionId;
  TaskFailure? get failure => _source.failure;
  String? get failureKey => _source.failure?.failureKey;
  int get unresolvedErrorCount => _source.failure?.unresolvedErrorCount ?? 0;
  bool get isTerminal => _source.isTerminal;
  TaskStep? get nextRunnableStep => _source.nextRunnableStep;
  TaskStep? stepById(String id) => _source.stepById(id);
}

/// Immutable project projection owned by the chat presentation boundary.
class ProjectPanelReadModel {
  const ProjectPanelReadModel._(this._source);

  factory ProjectPanelReadModel.fromAggregate(ProjectAggregate? source) =>
      source == null
      ? throw ArgumentError.notNull('source')
      : ProjectPanelReadModel._(source);

  final ProjectAggregate _source;

  String get id => _source.id;
  String get title => _source.title;
  String get originalGoal => _source.originalGoal;
  String get refinedGoal => _source.refinedGoal;
  ProjectStatus get status => _source.status;
  String? get activeTaskId => _source.activeTaskId;
  String? get chatSessionId => _source.chatSessionId;
  int get iterationCount => _source.iterationCount;
  int get maxIterations => _source.maxIterations;
  String get completionSummary => _source.completionSummary;
  List<String> get constraints => _source.constraints;
  List<ProjectTaskNode> get tasks => _source.tasks;
  List<TaskArtifact> get artifacts => _source.artifacts;
  List<ProjectCriterion> get criteria => _source.criteria;
  List<ProjectRecoveryIncident> get recoveryIncidents =>
      _source.recoveryIncidents;
  List<ProjectEvidence> get evidence => _source.evidence;
  List<ProjectMilestone> get milestones => _source.milestones;
  List<ProjectMemoryEntry> get memory => _source.memory;
  List<ProjectDecisionRecord> get decisions => _source.decisions;
  List<ProjectPlanRevision> get planHistory => _source.planHistory;
  ProjectWorkspaceGraph get workspaceGraph => _source.workspaceGraph;
  PendingProjectPlanApproval? get pendingPlanApproval =>
      _source.pendingPlanApproval;
  ProjectBlocker? get blocker => _source.blocker;
  List<PendingProjectQuestion> get openQuestions => _source.openQuestions;
  ProjectDiagnostics get diagnostics => _source.diagnostics;
  bool get isTerminal => _source.isTerminal;
  ProjectTaskNode? taskById(String id) => _source.taskById(id);
  String criterionStatement(String id) => _source.criterionStatement(id);

  ProjectScheduleResult get schedule =>
      const ProjectScheduler().refreshReadiness(_source);

  List<ProjectTaskNode> get orderedReadyTasks =>
      const ProjectScheduler().orderedReadyTasks(_source);

  ProjectWorkspaceContextSelection get workspaceContext =>
      const ProjectWorkspaceContextService().selectContext(project: _source);
}
