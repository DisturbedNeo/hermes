/// Domain-owned project aggregate.
///
/// The aggregate contains business state and behavior only. Snapshot mapping is
/// provided by the persistence infrastructure; the application contract remains a
/// compatibility export for callers that have not migrated their imports yet.
library;

import 'package:hermes/core/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/features/project/application/contracts/project_state_models.dart'
    hide ProjectSnapshotAggregate;

export 'package:hermes/features/project/application/contracts/project_state_models.dart'
    hide ProjectSnapshotAggregate;

class ProjectAggregate {
  static const int defaultMaxIterations = 25;
  static const int defaultMaxFailedTasks = 3;

  /// Revision of the canonical project snapshot.
  final int persistenceRevision;
  final String id;
  final String title;
  final String originalGoal;
  final String refinedGoal;
  final List<ProjectCriterion> criteria;
  final List<String> constraints;

  /// Project-owned task references. The canonical executable task document is
  /// persisted by the task system and hydrated by ProjectAggregateHydrator.
  final List<String> taskIds;
  final List<String> currentBatchTaskIds;
  final int currentBatchIndex;
  final int currentBatchPlanRevision;
  final bool currentBatchProgressObserved;
  final String? pendingReplanReason;

  /// Planner-owned task projections. Full executable task documents are
  /// resolved from the task system and are never part of project state.
  final List<ProjectTaskNode> tasks;
  final List<TaskArtifact> artifacts;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final List<ProjectEvidence> evidence;
  final List<ProjectMilestone> milestones;
  final List<ProjectMemoryEntry> memory;
  final ProjectWorkspaceGraph workspaceGraph;
  final List<ProjectPlanRevision> planHistory;
  final PendingProjectPlanApproval? pendingPlanApproval;
  final List<ProjectPlanRevisionTrigger> pendingReplanTriggers;
  final ProjectCompletionReviewCheckpoint? completionReviewCheckpoint;

  /// Durable, application-facing explanation of the current command boundary.
  /// Older snapshots may omit this field; the control-state service derives it
  /// from the compatibility fields when they are loaded.
  final ProjectBoundary? boundary;
  final List<PendingProjectQuestion> openQuestions;
  final ProjectStatus status;
  final int iterationCount;
  final int maxIterations;
  final int maxFailedTasks;
  final String? activeTaskId;
  final String? chatSessionId;
  final String completionSummary;
  final ProjectBlocker? blocker;
  final List<ProjectDecisionRecord> decisions;
  final ProjectDiagnostics diagnostics;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  ProjectAggregate({
    this.persistenceRevision = 0,
    required this.id,
    required this.title,
    required this.originalGoal,
    required this.refinedGoal,
    required this.criteria,
    required this.constraints,
    List<ProjectTaskNode>? tasks,
    List<String>? taskIds,
    this.currentBatchTaskIds = const [],
    this.currentBatchIndex = 0,
    this.currentBatchPlanRevision = 0,
    this.currentBatchProgressObserved = false,
    this.pendingReplanReason,
    List<TaskArtifact>? artifacts,
    List<ProjectRecoveryIncident>? recoveryIncidents,
    List<ProjectEvidence>? evidence,
    List<ProjectMilestone>? milestones,
    List<ProjectMemoryEntry>? memory,
    ProjectWorkspaceGraph? workspaceGraph,
    List<ProjectPlanRevision>? planHistory,
    this.pendingPlanApproval,
    this.pendingReplanTriggers = const [],
    this.completionReviewCheckpoint,
    this.boundary,
    this.openQuestions = const [],
    required this.status,
    int? iterationCount,
    this.maxIterations = defaultMaxIterations,
    this.maxFailedTasks = defaultMaxFailedTasks,
    required this.activeTaskId,
    this.chatSessionId,
    this.completionSummary = '',
    this.blocker,
    this.decisions = const [],
    this.diagnostics = const ProjectDiagnostics(),
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  }) : tasks = List.unmodifiable(tasks ?? const <ProjectTaskNode>[]),
       taskIds =
           taskIds ??
           [for (final task in tasks ?? const <ProjectTaskNode>[]) task.id],
       artifacts = artifacts ?? const [],
       recoveryIncidents = recoveryIncidents ?? const [],
       evidence = evidence ?? const [],
       milestones = milestones ?? const [],
       memory = memory ?? const [],
       workspaceGraph = workspaceGraph ?? ProjectWorkspaceGraph.empty(),
       planHistory =
           planHistory ??
           [
             ProjectPlanRevision(
               revision: 1,
               trigger: ProjectPlanRevisionTrigger.initialization,
               summary: 'Initial project plan.',
               rationale: 'Created from the initial project definition.',
               createdAt: createdAt,
               approvedAt: createdAt,
               approvedBy: ProjectPlanRevisionApprover.automatic,
             ),
           ],
       iterationCount =
           iterationCount ??
           (tasks
                   ?.where((task) => task.status == TaskStatus.completed)
                   .length ??
               0);

  ProjectPlanState get planState => ProjectPlanState(
    revision: currentBatchPlanRevision,
    criteria: criteria,
    milestones: milestones,
    tasks: tasks,
  );

  ProjectExecutionState get executionState => ProjectExecutionState(
    status: status,
    activeTaskId: activeTaskId,
    iterationCount: iterationCount,
  );

  ProjectEvidenceState get evidenceState => ProjectEvidenceState(
    evidence: evidence,
    artifacts: artifacts,
    completionReview: completionReviewCheckpoint,
  );

  ProjectControlState get controlState => ProjectControlState(
    boundary: boundary,
    blocker: blocker,
    openQuestions: openQuestions,
  );

  bool get isTerminal =>
      status == ProjectStatus.completed ||
      status == ProjectStatus.cancelled ||
      status == ProjectStatus.failed;

  int get nextRevision {
    var highest = 0;
    for (final revision in planHistory) {
      if (revision.revision > highest) highest = revision.revision;
    }
    return highest + 1;
  }

  String criterionStatement(String criterionId) {
    for (final criterion in criteria) {
      if (criterion.id == criterionId) return criterion.statement;
    }
    return criterionId;
  }

  List<String> criterionStatementsFor(ProjectTaskNode task) => [
    for (final criterionId in task.criterionIds)
      criterionStatement(criterionId),
  ];

  ProjectTaskNode? taskById(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  bool get hasCurrentBatch =>
      currentBatchTaskIds.isNotEmpty &&
      currentBatchIndex < currentBatchTaskIds.length;

  String? get currentBatchTaskId =>
      hasCurrentBatch ? currentBatchTaskIds[currentBatchIndex] : null;

  ProjectAggregate copyWith({
    int? persistenceRevision,
    String? id,
    String? title,
    String? originalGoal,
    String? refinedGoal,
    List<ProjectCriterion>? criteria,
    List<String>? constraints,
    List<ProjectTaskNode>? tasks,
    List<String>? taskIds,
    List<String>? currentBatchTaskIds,
    int? currentBatchIndex,
    int? currentBatchPlanRevision,
    bool? currentBatchProgressObserved,
    Object? pendingReplanReason = kSentinel,
    List<TaskArtifact>? artifacts,
    List<ProjectRecoveryIncident>? recoveryIncidents,
    List<ProjectEvidence>? evidence,
    List<ProjectMilestone>? milestones,
    List<ProjectMemoryEntry>? memory,
    ProjectWorkspaceGraph? workspaceGraph,
    List<ProjectPlanRevision>? planHistory,
    Object? pendingPlanApproval = kSentinel,
    List<ProjectPlanRevisionTrigger>? pendingReplanTriggers,
    Object? completionReviewCheckpoint = kSentinel,
    Object? boundary = kSentinel,
    List<PendingProjectQuestion>? openQuestions,
    ProjectStatus? status,
    int? iterationCount,
    int? maxIterations,
    int? maxFailedTasks,
    Object? activeTaskId = kSentinel,
    Object? chatSessionId = kSentinel,
    String? completionSummary,
    Object? blocker = kSentinel,
    List<ProjectDecisionRecord>? decisions,
    ProjectDiagnostics? diagnostics,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return ProjectAggregate(
      persistenceRevision: persistenceRevision ?? this.persistenceRevision,
      id: id ?? this.id,
      title: title ?? this.title,
      originalGoal: originalGoal ?? this.originalGoal,
      refinedGoal: refinedGoal ?? this.refinedGoal,
      criteria: criteria ?? this.criteria,
      constraints: constraints ?? this.constraints,
      tasks: tasks ?? this.tasks,
      taskIds:
          taskIds ??
          (tasks == null ? this.taskIds : [for (final task in tasks) task.id]),
      currentBatchTaskIds: currentBatchTaskIds ?? this.currentBatchTaskIds,
      currentBatchIndex: currentBatchIndex ?? this.currentBatchIndex,
      currentBatchPlanRevision:
          currentBatchPlanRevision ?? this.currentBatchPlanRevision,
      currentBatchProgressObserved:
          currentBatchProgressObserved ?? this.currentBatchProgressObserved,
      pendingReplanReason: resolve(
        pendingReplanReason,
        this.pendingReplanReason,
      ),
      artifacts: artifacts ?? this.artifacts,
      recoveryIncidents: recoveryIncidents ?? this.recoveryIncidents,
      evidence: evidence ?? this.evidence,
      milestones: milestones ?? this.milestones,
      memory: memory ?? this.memory,
      workspaceGraph: workspaceGraph ?? this.workspaceGraph,
      planHistory: planHistory ?? this.planHistory,
      pendingPlanApproval: resolve(
        pendingPlanApproval,
        this.pendingPlanApproval,
      ),
      pendingReplanTriggers:
          pendingReplanTriggers ?? this.pendingReplanTriggers,
      completionReviewCheckpoint: resolve(
        completionReviewCheckpoint,
        this.completionReviewCheckpoint,
      ),
      boundary: resolve(boundary, this.boundary),
      openQuestions: openQuestions ?? this.openQuestions,
      status: status ?? this.status,
      iterationCount: iterationCount ?? this.iterationCount,
      maxIterations: maxIterations ?? this.maxIterations,
      maxFailedTasks: maxFailedTasks ?? this.maxFailedTasks,
      activeTaskId: resolve(activeTaskId, this.activeTaskId),
      chatSessionId: resolve(chatSessionId, this.chatSessionId),
      completionSummary: completionSummary ?? this.completionSummary,
      blocker: resolve(blocker, this.blocker),
      decisions: decisions ?? this.decisions,
      diagnostics: diagnostics ?? this.diagnostics,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
    );
  }
}
