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
  const TaskPanelReadModel._(this._snapshot);

  factory TaskPanelReadModel.fromAggregate(Task? source) => source == null
      ? throw ArgumentError.notNull('source')
      : TaskPanelReadModel._(_snapshotTask(source));

  /// A detached aggregate snapshot. Runtime updates replace the aggregate;
  /// they cannot mutate an already-published panel value.
  final Task _snapshot;

  String get id => _snapshot.id;
  String get title => _snapshot.title;
  String get objective => _snapshot.objective;
  TaskStatus get status => _snapshot.status;
  List<TaskStep> get steps => _snapshot.steps;
  List<TaskRun> get runs => _snapshot.runs;
  PendingTaskApproval? get pendingApproval => _snapshot.pendingApproval;
  PendingTaskQuestion? get pendingQuestion => _snapshot.pendingQuestion;
  PlanningMetrics get planningMetrics => _snapshot.planningMetrics;
  String get memorySummary => _snapshot.memorySummary;
  List<String> get doneCriteria => _snapshot.doneCriteria;
  List<String> get outOfScope => _snapshot.outOfScope;
  String? get currentStepId => _snapshot.currentStepId;
  String? get projectId => _snapshot.projectId;
  String? get chatSessionId => _snapshot.chatSessionId;
  TaskFailure? get failure => _snapshot.failure;
  String? get failureKey => _snapshot.failure?.failureKey;
  int get unresolvedErrorCount => _snapshot.failure?.unresolvedErrorCount ?? 0;
  bool get isTerminal => _snapshot.isTerminal;
  TaskStep? get nextRunnableStep => _snapshot.nextRunnableStep;
  TaskStep? stepById(String id) => _snapshot.stepById(id);
}

/// Immutable project projection owned by the chat presentation boundary.
class ProjectPanelReadModel {
  const ProjectPanelReadModel._(this._snapshot);

  factory ProjectPanelReadModel.fromAggregate(ProjectAggregate? source) =>
      source == null
      ? throw ArgumentError.notNull('source')
      : ProjectPanelReadModel._(_snapshotProject(source));

  /// A detached aggregate snapshot retained only to calculate derived panel
  /// values such as readiness and workspace context.
  final ProjectAggregate _snapshot;

  String get id => _snapshot.id;
  String get title => _snapshot.title;
  String get originalGoal => _snapshot.originalGoal;
  String get refinedGoal => _snapshot.refinedGoal;
  ProjectStatus get status => _snapshot.status;
  String? get activeTaskId => _snapshot.activeTaskId;
  String? get chatSessionId => _snapshot.chatSessionId;
  int get iterationCount => _snapshot.iterationCount;
  int get maxIterations => _snapshot.maxIterations;
  String get completionSummary => _snapshot.completionSummary;
  List<String> get constraints => _snapshot.constraints;
  List<ProjectTaskNode> get tasks => _snapshot.tasks;
  List<TaskArtifact> get artifacts => _snapshot.artifacts;
  List<ProjectCriterion> get criteria => _snapshot.criteria;
  List<ProjectRecoveryIncident> get recoveryIncidents =>
      _snapshot.recoveryIncidents;
  List<ProjectEvidence> get evidence => _snapshot.evidence;
  List<ProjectMilestone> get milestones => _snapshot.milestones;
  List<ProjectMemoryEntry> get memory => _snapshot.memory;
  List<ProjectDecisionRecord> get decisions => _snapshot.decisions;
  List<ProjectPlanRevision> get planHistory => _snapshot.planHistory;
  ProjectWorkspaceGraph get workspaceGraph => _snapshot.workspaceGraph;
  PendingProjectPlanApproval? get pendingPlanApproval =>
      _snapshot.pendingPlanApproval;
  ProjectBlocker? get blocker => _snapshot.blocker;
  List<PendingProjectQuestion> get openQuestions => _snapshot.openQuestions;
  ProjectDiagnostics get diagnostics => _snapshot.diagnostics;
  bool get isTerminal => _snapshot.isTerminal;
  ProjectTaskNode? taskById(String id) => _snapshot.taskById(id);
  String criterionStatement(String id) => _snapshot.criterionStatement(id);

  ProjectScheduleResult get schedule =>
      const ProjectScheduler().refreshReadiness(_snapshot);

  List<ProjectTaskNode> get orderedReadyTasks =>
      const ProjectScheduler().orderedReadyTasks(_snapshot);

  ProjectWorkspaceContextSelection get workspaceContext =>
      const ProjectWorkspaceContextService().selectContext(project: _snapshot);
}

Task _snapshotTask(Task source) => source.copyWith(
  constraints: List.unmodifiable(source.constraints),
  successCriteria: List.unmodifiable(source.successCriteria),
  gates: List.unmodifiable(source.gates.map(_snapshotGate)),
  steps: List.unmodifiable(source.steps.map(_snapshotStep)),
  criterionIds: List.unmodifiable(source.criterionIds),
  dependsOnTaskIds: List.unmodifiable(source.dependsOnTaskIds),
  expectedEvidence: List.unmodifiable(
    source.expectedEvidence.map(_snapshotEvidenceExpectation),
  ),
  readPaths: List.unmodifiable(source.readPaths),
  writePaths: List.unmodifiable(source.writePaths),
  doneCriteria: List.unmodifiable(source.doneCriteria),
  outOfScope: List.unmodifiable(source.outOfScope),
  context: List.unmodifiable(source.context),
  expectedArtifacts: List.unmodifiable(
    source.expectedArtifacts.map(_snapshotArtifact),
  ),
  runs: List.unmodifiable(source.runs.map(_snapshotRun)),
);

TaskGate _snapshotGate(TaskGate source) => TaskGate(
  id: source.id,
  required: source.required,
  scope: source.scope,
  params: _snapshotMap(source.params),
  description: source.description,
);

TaskEvidenceExpectation _snapshotEvidenceExpectation(
  TaskEvidenceExpectation source,
) => TaskEvidenceExpectation(
  id: source.id,
  type: source.type,
  criterionIds: List.unmodifiable(source.criterionIds),
  description: source.description,
  required: source.required,
  sourceRef: source.sourceRef,
  details: _snapshotMap(source.details),
);

TaskArtifact _snapshotArtifact(TaskArtifact source) => source.copyWith();

TaskStep _snapshotStep(TaskStep source) => source.copyWith(
  instructions: List.unmodifiable(source.instructions),
  artifacts: List.unmodifiable(source.artifacts.map(_snapshotArtifact)),
  gates: List.unmodifiable(source.gates.map(_snapshotGate)),
);

TaskRun _snapshotRun(TaskRun source) => source.copyWith(
  toolCalls: List.unmodifiable(source.toolCalls),
  artifacts: List.unmodifiable(source.artifacts.map(_snapshotArtifact)),
  gateResults: List.unmodifiable(source.gateResults),
  evidenceClaims: List.unmodifiable(source.evidenceClaims),
);

ProjectAggregate _snapshotProject(ProjectAggregate source) => source.copyWith(
  criteria: List.unmodifiable(source.criteria.map(_snapshotCriterion)),
  constraints: List.unmodifiable(source.constraints),
  taskIds: List.unmodifiable(source.taskIds),
  currentBatchTaskIds: List.unmodifiable(source.currentBatchTaskIds),
  tasks: List.unmodifiable(source.tasks.map(_snapshotProjectTask)),
  artifacts: List.unmodifiable(source.artifacts.map(_snapshotArtifact)),
  recoveryIncidents: List.unmodifiable(
    source.recoveryIncidents.map(_snapshotRecoveryIncident),
  ),
  evidence: List.unmodifiable(source.evidence.map(_snapshotEvidence)),
  milestones: List.unmodifiable(source.milestones.map(_snapshotMilestone)),
  memory: List.unmodifiable(source.memory.map(_snapshotMemory)),
  workspaceGraph: source.workspaceGraph.copyWith(
    nodes: List.unmodifiable(
      source.workspaceGraph.nodes.map(_snapshotWorkspaceNode),
    ),
    edges: List.unmodifiable(
      source.workspaceGraph.edges.map(_snapshotWorkspaceEdge),
    ),
  ),
  planHistory: List.unmodifiable(source.planHistory.map(_snapshotPlanRevision)),
  pendingReplanTriggers: List.unmodifiable(source.pendingReplanTriggers),
  openQuestions: List.unmodifiable(source.openQuestions),
  decisions: List.unmodifiable(source.decisions),
);

ProjectCriterion _snapshotCriterion(ProjectCriterion source) =>
    source.copyWith();

ProjectEvidence _snapshotEvidence(ProjectEvidence source) => source.copyWith(
  criterionIds: List.unmodifiable(source.criterionIds),
  expectationIds: List.unmodifiable(source.expectationIds),
  details: _snapshotMap(source.details),
);

ProjectMilestone _snapshotMilestone(ProjectMilestone source) =>
    ProjectMilestone(
      id: source.id,
      title: source.title,
      objective: source.objective,
      criterionIds: List.unmodifiable(source.criterionIds),
      status: source.status,
      exitConditions: List.unmodifiable(source.exitConditions),
      order: source.order,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      completedAt: source.completedAt,
    );

ProjectMemoryEntry _snapshotMemory(ProjectMemoryEntry source) =>
    source.copyWith(coveredEntryIds: List.unmodifiable(source.coveredEntryIds));

ProjectRecoveryIncident _snapshotRecoveryIncident(
  ProjectRecoveryIncident source,
) => source.copyWith(
  sourceTaskIds: List.unmodifiable(source.sourceTaskIds),
  sourceTaskTitles: List.unmodifiable(source.sourceTaskTitles),
  recoveryTaskIds: List.unmodifiable(source.recoveryTaskIds),
);

ProjectPlanRevision _snapshotPlanRevision(ProjectPlanRevision source) =>
    ProjectPlanRevision(
      revision: source.revision,
      trigger: source.trigger,
      summary: source.summary,
      rationale: source.rationale,
      addedTaskIds: List.unmodifiable(source.addedTaskIds),
      updatedTaskIds: List.unmodifiable(source.updatedTaskIds),
      removedTaskIds: List.unmodifiable(source.removedTaskIds),
      criterionChanges: List.unmodifiable(source.criterionChanges),
      milestoneChanges: List.unmodifiable(source.milestoneChanges),
      validationWarnings: List.unmodifiable(source.validationWarnings),
      createdAt: source.createdAt,
      approvedAt: source.approvedAt,
      approvedBy: source.approvedBy,
    );

ProjectWorkspaceNode _snapshotWorkspaceNode(ProjectWorkspaceNode source) =>
    source.copyWith(
      aliases: List.unmodifiable(source.aliases),
      tags: List.unmodifiable(source.tags),
      references: List.unmodifiable(source.references),
    );

ProjectWorkspaceEdge _snapshotWorkspaceEdge(ProjectWorkspaceEdge source) =>
    source.copyWith();

ProjectTaskNode _snapshotProjectTask(ProjectTaskNode source) => source.copyWith(
  gates: List.unmodifiable(source.gates.map(_snapshotGate)),
  constraints: List.unmodifiable(source.constraints),
  successCriteria: List.unmodifiable(source.successCriteria),
  criterionIds: List.unmodifiable(source.criterionIds),
  dependsOnTaskIds: List.unmodifiable(source.dependsOnTaskIds),
  expectedEvidence: List.unmodifiable(
    source.expectedEvidence.map(_snapshotEvidenceExpectation),
  ),
  readPaths: List.unmodifiable(source.readPaths),
  writePaths: List.unmodifiable(source.writePaths),
  doneCriteria: List.unmodifiable(source.doneCriteria),
  outOfScope: List.unmodifiable(source.outOfScope),
  context: List.unmodifiable(source.context),
  expectedArtifacts: List.unmodifiable(
    source.expectedArtifacts.map(_snapshotArtifact),
  ),
  failureErrorCodes: List.unmodifiable(source.failureErrorCodes),
);

Map<String, dynamic> _snapshotMap(Map<String, dynamic> source) =>
    Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: _snapshotValue(entry.value),
    });

Object? _snapshotValue(Object? value) {
  if (value is Map<String, dynamic>) return _snapshotMap(value);
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _snapshotValue(entry.value),
    });
  }
  if (value is Iterable) {
    return List.unmodifiable(value.map(_snapshotValue));
  }
  return value;
}
