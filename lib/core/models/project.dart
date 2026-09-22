import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

export 'task.dart'
    show
        ProjectEvidenceType,
        ProjectRiskReduction,
        TaskEffort,
        TaskPriority,
        TaskRisk,
        Task,
        TaskArtifact,
        TaskFailure,
        TaskStatus,
        TaskEvidenceExpectation,
        TaskStatusWire;

part 'project.mapper.dart';
part 'project_json_hooks.dart';

@MappableEnum(defaultValue: ProjectStatus.active)
enum ProjectStatus {
  initializing,
  active,
  paused,
  @MappableValue('running_task')
  runningTask,
  @MappableValue('reviewing_task')
  reviewingTask,
  @MappableValue('waiting_for_user')
  waitingForUser,
  blocked,
  completed,
  failed,
  cancelled,
}

@MappableEnum(defaultValue: ProjectCriterionStatus.unsatisfied)
enum ProjectCriterionStatus { unsatisfied, partial, satisfied, invalidated }

@MappableEnum(defaultValue: ProjectVerificationMode.mixed)
enum ProjectVerificationMode {
  deterministic,
  @MappableValue('model_review')
  modelReview,
  @MappableValue('human_approval')
  humanApproval,
  mixed,
}

@MappableEnum(defaultValue: ProjectEvidenceStatus.proposed)
enum ProjectEvidenceStatus { proposed, accepted, rejected, stale }

@MappableEnum(defaultValue: ProjectEvidenceStrength.advisory)
enum ProjectEvidenceStrength { advisory, supporting, conclusive }

@MappableEnum(defaultValue: ProjectMilestoneStatus.planned)
enum ProjectMilestoneStatus { planned, active, completed, blocked, cancelled }

@MappableEnum(defaultValue: TaskReadiness.ready)
enum TaskReadiness {
  ready,
  @MappableValue('waiting_dependency')
  waitingDependency,
  @MappableValue('waiting_input')
  waitingInput,
  @MappableValue('not_eligible')
  notEligible,
}

@MappableEnum(defaultValue: ProjectMemoryKind.fact)
enum ProjectMemoryKind {
  requirement,
  fact,
  assumption,
  decision,
  risk,
  summary,
}

@MappableEnum(defaultValue: ProjectMemorySourceType.system)
enum ProjectMemorySourceType { user, planner, task, gate, system }

@MappableEnum(defaultValue: ProjectMemoryConfidence.inferred)
enum ProjectMemoryConfidence { confirmed, inferred, uncertain }

@MappableEnum(defaultValue: ProjectPlanRevisionTrigger.initialization)
enum ProjectPlanRevisionTrigger {
  initialization,
  @MappableValue('task_completed')
  taskCompleted,
  @MappableValue('task_failed')
  taskFailed,
  @MappableValue('new_context')
  newContext,
  @MappableValue('no_ready_task')
  noReadyTask,
  @MappableValue('milestone_completed')
  milestoneCompleted,
  manual,
  @MappableValue('workspace_changed')
  workspaceChanged,
  @MappableValue('evidence_rejected')
  evidenceRejected,
  @MappableValue('task_replan_requested')
  taskReplanRequested,
  @MappableValue('batch_complete')
  batchComplete,
  @MappableValue('scope_changed')
  scopeChanged,
  @MappableValue('milestone_roadmap_changed')
  milestoneRoadmapChanged,
}

@MappableEnum(defaultValue: ProjectCompletionReviewReason.noRemainingTasks)
enum ProjectCompletionReviewReason {
  @MappableValue('no_remaining_tasks')
  noRemainingTasks,
  @MappableValue('milestone_ended')
  milestoneEnded,
  @MappableValue('batch_ended')
  batchEnded,
  @MappableValue('final_criterion_evidence')
  finalCriterionEvidence,
}

@MappableEnum(defaultValue: ProjectPlanApprovalPolicy.highRiskOnly)
enum ProjectPlanApprovalPolicy {
  never,
  highRiskOnly,
  everyRevision;

  String get wire => name;

  String get label => switch (this) {
    ProjectPlanApprovalPolicy.never => 'Never (autonomous)',
    ProjectPlanApprovalPolicy.highRiskOnly => 'High risk only',
    ProjectPlanApprovalPolicy.everyRevision => 'Every revision',
  };

  static ProjectPlanApprovalPolicy parse(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    return switch (raw) {
      'never' => ProjectPlanApprovalPolicy.never,
      'everyrevision' ||
      'every_revision' => ProjectPlanApprovalPolicy.everyRevision,
      _ => ProjectPlanApprovalPolicy.highRiskOnly,
    };
  }
}

@MappableEnum(defaultValue: ProjectPlanRevisionApprover.automatic)
enum ProjectPlanRevisionApprover { automatic, user }

@MappableEnum(defaultValue: ProjectBlockerType.error)
enum ProjectBlockerType {
  question,
  @MappableValue('task_edit_approval')
  taskEditApproval,
  @MappableValue('task_blocked')
  taskBlocked,
  @MappableValue('task_failed')
  taskFailed,
  @MappableValue('recovery_failed')
  recoveryFailed,
  budget,
  validation,
  @MappableValue('duplicate_task')
  duplicateTask,
  @MappableValue('oversized_task')
  oversizedTask,
  @MappableValue('max_failures')
  maxFailures,
  @MappableValue('plan_approval')
  planApproval,
  stagnation,
  error,
}

@MappableEnum(defaultValue: ProjectDecisionType.blocked)
enum ProjectDecisionType {
  @MappableValue('create_task')
  createTask,
  @MappableValue('create_recovery_task')
  createRecoveryTask,
  complete,
  blocked,
  @MappableValue('reject_task')
  rejectTask,
  @MappableValue('split_task')
  splitTask,
  @MappableValue('evaluate_task')
  evaluateTask,
  @MappableValue('retry_recovery')
  retryRecovery,
  @MappableValue('apply_plan_revision')
  applyPlanRevision,
  @MappableValue('approve_plan_revision')
  approvePlanRevision,
  @MappableValue('reject_plan_revision')
  rejectPlanRevision,
}

extension ProjectStatusWire on ProjectStatus {
  String get wire => switch (this) {
    ProjectStatus.runningTask => 'running_task',
    ProjectStatus.reviewingTask => 'reviewing_task',
    ProjectStatus.waitingForUser => 'waiting_for_user',
    _ => name,
  };
}

extension ProjectBlockerTypeWire on ProjectBlockerType {
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

@MappableClass(ignoreNull: true)
class ProjectDiagnostics with ProjectDiagnosticsMappable {
  final int projectModelCalls;
  final int planRevisionAttempts;
  final int invalidPlanProposals;
  final int taskExecutions;
  final int completedTaskExecutions;
  final int completedBatchesWithoutCriterionProgress;
  final int criterionReversals;
  final int noReadyTaskBlocks;
  final int userApprovals;
  final int userQuestions;
  final int consecutiveNoProgressBatches;
  @MappableField(hook: OmitEmptyPlanningMetricsHook())
  final PlanningMetrics planningMetrics;
  @MappableField(hook: JsonStringListHook())
  final List<String> recentNoProgressBatchIds;

  const ProjectDiagnostics({
    this.projectModelCalls = 0,
    this.planRevisionAttempts = 0,
    this.invalidPlanProposals = 0,
    this.taskExecutions = 0,
    this.completedTaskExecutions = 0,
    this.completedBatchesWithoutCriterionProgress = 0,
    this.criterionReversals = 0,
    this.noReadyTaskBlocks = 0,
    this.userApprovals = 0,
    this.userQuestions = 0,
    this.consecutiveNoProgressBatches = 0,
    this.planningMetrics = const PlanningMetrics(),
    this.recentNoProgressBatchIds = const [],
  });

  double get projectModelCallsPerCompletedTask => completedTaskExecutions == 0
      ? 0
      : projectModelCalls / completedTaskExecutions;

  ProjectDiagnostics copyWith({
    int? projectModelCalls,
    int? planRevisionAttempts,
    int? invalidPlanProposals,
    int? taskExecutions,
    int? completedTaskExecutions,
    int? completedBatchesWithoutCriterionProgress,
    int? criterionReversals,
    int? noReadyTaskBlocks,
    int? userApprovals,
    int? userQuestions,
    int? consecutiveNoProgressBatches,
    List<String>? recentNoProgressBatchIds,
    PlanningMetrics? planningMetrics,
  }) {
    return ProjectDiagnostics(
      projectModelCalls: projectModelCalls ?? this.projectModelCalls,
      planRevisionAttempts: planRevisionAttempts ?? this.planRevisionAttempts,
      invalidPlanProposals: invalidPlanProposals ?? this.invalidPlanProposals,
      taskExecutions: taskExecutions ?? this.taskExecutions,
      completedTaskExecutions:
          completedTaskExecutions ?? this.completedTaskExecutions,
      completedBatchesWithoutCriterionProgress:
          completedBatchesWithoutCriterionProgress ??
          this.completedBatchesWithoutCriterionProgress,
      criterionReversals: criterionReversals ?? this.criterionReversals,
      noReadyTaskBlocks: noReadyTaskBlocks ?? this.noReadyTaskBlocks,
      userApprovals: userApprovals ?? this.userApprovals,
      userQuestions: userQuestions ?? this.userQuestions,
      consecutiveNoProgressBatches:
          consecutiveNoProgressBatches ?? this.consecutiveNoProgressBatches,
      recentNoProgressBatchIds:
          recentNoProgressBatchIds ?? this.recentNoProgressBatchIds,
      planningMetrics: planningMetrics ?? this.planningMetrics,
    );
  }
}

extension ProjectDecisionTypeWire on ProjectDecisionType {
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

@MappableClass(ignoreNull: true)
class ProjectCriterion with ProjectCriterionMappable {
  final String id;
  final String statement;
  final bool required;
  final ProjectCriterionStatus status;
  final ProjectVerificationMode verificationMode;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? verifiedAt;

  const ProjectCriterion({
    required this.id,
    required this.statement,
    this.required = true,
    this.status = ProjectCriterionStatus.unsatisfied,
    this.verificationMode = ProjectVerificationMode.mixed,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.verifiedAt,
  });

  ProjectCriterion copyWith({
    String? id,
    String? statement,
    bool? required,
    ProjectCriterionStatus? status,
    ProjectVerificationMode? verificationMode,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? verifiedAt = kSentinel,
  }) {
    return ProjectCriterion(
      id: id ?? this.id,
      statement: statement ?? this.statement,
      required: required ?? this.required,
      status: status ?? this.status,
      verificationMode: verificationMode ?? this.verificationMode,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      verifiedAt: resolve(verifiedAt, this.verifiedAt),
    );
  }
}

@MappableClass(ignoreNull: true)
class ProjectEvidence with ProjectEvidenceMappable {
  final String id;
  final ProjectEvidenceType type;
  final List<String> criterionIds;
  final List<String> expectationIds;
  final String? taskId;
  final String? runId;
  final String sourceRef;
  final String? sourceFingerprint;
  final String summary;
  final ProjectEvidenceStatus status;
  final ProjectEvidenceStrength strength;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  final DateTime? evaluatedAt;

  const ProjectEvidence({
    required this.id,
    required this.type,
    this.criterionIds = const [],
    this.expectationIds = const [],
    this.taskId,
    this.runId,
    required this.sourceRef,
    this.sourceFingerprint,
    required this.summary,
    this.status = ProjectEvidenceStatus.proposed,
    this.strength = ProjectEvidenceStrength.advisory,
    this.details = const {},
    required this.createdAt,
    this.evaluatedAt,
  });

  ProjectEvidence copyWith({
    String? id,
    ProjectEvidenceType? type,
    List<String>? criterionIds,
    List<String>? expectationIds,
    Object? taskId = kSentinel,
    Object? runId = kSentinel,
    String? sourceRef,
    Object? sourceFingerprint = kSentinel,
    String? summary,
    ProjectEvidenceStatus? status,
    ProjectEvidenceStrength? strength,
    Map<String, dynamic>? details,
    DateTime? createdAt,
    Object? evaluatedAt = kSentinel,
  }) {
    return ProjectEvidence(
      id: id ?? this.id,
      type: type ?? this.type,
      criterionIds: criterionIds ?? this.criterionIds,
      expectationIds: expectationIds ?? this.expectationIds,
      taskId: resolve(taskId, this.taskId),
      runId: resolve(runId, this.runId),
      sourceRef: sourceRef ?? this.sourceRef,
      sourceFingerprint: resolve(sourceFingerprint, this.sourceFingerprint),
      summary: summary ?? this.summary,
      status: status ?? this.status,
      strength: strength ?? this.strength,
      details: details ?? this.details,
      createdAt: createdAt ?? this.createdAt,
      evaluatedAt: resolve(evaluatedAt, this.evaluatedAt),
    );
  }
}

@MappableClass(ignoreNull: true)
class ProjectMilestone with ProjectMilestoneMappable {
  final String id;
  final String title;
  final String objective;
  final List<String> criterionIds;
  final ProjectMilestoneStatus status;
  final List<String> exitConditions;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const ProjectMilestone({
    required this.id,
    required this.title,
    required this.objective,
    this.criterionIds = const [],
    this.status = ProjectMilestoneStatus.planned,
    this.exitConditions = const [],
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });
}

@MappableClass(ignoreNull: true)
class ProjectMemoryEntry with ProjectMemoryEntryMappable {
  final String id;
  final ProjectMemoryKind kind;
  final String content;
  final ProjectMemorySourceType sourceType;
  final String? sourceId;
  final ProjectMemoryConfidence confidence;
  final bool protected;
  final bool active;
  final String? supersedesId;
  @MappableField(hook: JsonStringListHook())
  final List<String> coveredEntryIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProjectMemoryEntry({
    required this.id,
    required this.kind,
    required this.content,
    required this.sourceType,
    this.sourceId,
    required this.confidence,
    this.protected = false,
    this.active = true,
    this.supersedesId,
    this.coveredEntryIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  ProjectMemoryEntry copyWith({
    String? id,
    ProjectMemoryKind? kind,
    String? content,
    ProjectMemorySourceType? sourceType,
    Object? sourceId = kSentinel,
    ProjectMemoryConfidence? confidence,
    bool? protected,
    bool? active,
    Object? supersedesId = kSentinel,
    List<String>? coveredEntryIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectMemoryEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      sourceType: sourceType ?? this.sourceType,
      sourceId: resolve(sourceId, this.sourceId),
      confidence: confidence ?? this.confidence,
      protected: protected ?? this.protected,
      active: active ?? this.active,
      supersedesId: resolve(supersedesId, this.supersedesId),
      coveredEntryIds: coveredEntryIds ?? this.coveredEntryIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@MappableClass(ignoreNull: true)
class ProjectMemorySupersession with ProjectMemorySupersessionMappable {
  final String entryId;
  final String supersededById;

  const ProjectMemorySupersession({
    required this.entryId,
    required this.supersededById,
  });
}

/// The complete desired planning state returned by the planner.
///
/// Runtime task state, evidence, gate results, recovery incidents, and
/// protected memory are reconciled by code and are never accepted from this
/// model response as authoritative state.
@MappableClass(ignoreNull: true)
class ProjectDesiredPlan with ProjectDesiredPlanMappable {
  final int revision;
  final List<ProjectPlanRevisionTrigger> triggers;
  final String summary;
  final String rationale;

  /// Whether the planner supplied all required plan collections with valid
  /// collection shapes. Directly constructed plans default to complete, while
  /// model-parsed plans mark omitted or malformed collections as incomplete.
  final bool hasCompleteCollections;
  final List<String> assumptions;
  final List<ProjectCriterion> criteria;
  final List<ProjectMilestone> milestones;
  final List<Task> tasks;

  /// Source task IDs that the builder is replacing with fresh child tasks.
  /// This is persisted with pending approvals so approving a split applies the
  /// same immutable-history rule as an immediate commit.
  final List<String> splitTaskIds;
  final List<String> deferredTaskIds;
  final List<String> obsoleteTaskIds;
  final List<ProjectMemoryEntry> memoryAdditions;
  final List<ProjectMemorySupersession> memorySupersessions;
  final List<PendingProjectQuestion> openQuestions;
  final bool requiresApproval;
  final String approvalReason;
  final DateTime createdAt;

  const ProjectDesiredPlan({
    required this.revision,
    this.triggers = const [],
    required this.summary,
    required this.rationale,
    this.hasCompleteCollections = true,
    this.assumptions = const [],
    this.criteria = const [],
    this.milestones = const [],
    this.tasks = const [],
    this.splitTaskIds = const [],
    this.deferredTaskIds = const [],
    this.obsoleteTaskIds = const [],
    this.memoryAdditions = const [],
    this.memorySupersessions = const [],
    this.openQuestions = const [],
    this.requiresApproval = false,
    this.approvalReason = '',
    required this.createdAt,
  });
}

@MappableClass(ignoreNull: true)
class ProjectPlanRevision with ProjectPlanRevisionMappable {
  final int revision;
  final ProjectPlanRevisionTrigger trigger;
  final String summary;
  final String rationale;
  final List<String> addedTaskIds;
  final List<String> updatedTaskIds;
  final List<String> removedTaskIds;
  final List<String> criterionChanges;
  final List<String> milestoneChanges;
  final List<String> validationWarnings;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final ProjectPlanRevisionApprover? approvedBy;

  const ProjectPlanRevision({
    required this.revision,
    required this.trigger,
    required this.summary,
    required this.rationale,
    this.addedTaskIds = const [],
    this.updatedTaskIds = const [],
    this.removedTaskIds = const [],
    this.criterionChanges = const [],
    this.milestoneChanges = const [],
    this.validationWarnings = const [],
    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
  });
}

@MappableClass(ignoreNull: true)
class PendingProjectPlanApproval with PendingProjectPlanApprovalMappable {
  final int revision;
  final String reason;
  final String summary;
  final List<String> highRiskChanges;
  final List<String> highRiskReasonCodes;
  final DateTime createdAt;
  final ProjectDesiredPlan? desiredPlan;

  const PendingProjectPlanApproval({
    required this.revision,
    required this.reason,
    required this.summary,
    this.highRiskChanges = const [],
    this.highRiskReasonCodes = const [],
    required this.createdAt,
    this.desiredPlan,
  });
}

@MappableEnum(defaultValue: ProjectRecoveryIncidentStatus.active)
enum ProjectRecoveryIncidentStatus { active, resolved, exhausted }

extension ProjectRecoveryIncidentStatusWire on ProjectRecoveryIncidentStatus {
  String get wire => name;
}

@MappableClass(ignoreNull: true)
class ProjectCompletionReviewCheckpoint
    with ProjectCompletionReviewCheckpointMappable {
  final ProjectCompletionReviewReason reason;
  @MappableField(hook: JsonStringHook())
  final String evidenceFingerprint;
  @MappableField(hook: JsonNullableStringHook())
  final String? milestoneId;
  @MappableField(hook: JsonDateHook())
  final DateTime reviewedAt;

  const ProjectCompletionReviewCheckpoint({
    required this.reason,
    required this.evidenceFingerprint,
    this.milestoneId,
    required this.reviewedAt,
  });
}

@MappableClass(ignoreNull: true, hook: ProjectStateJsonHook())
class ProjectState with ProjectStateMappable {
  static const int defaultMaxIterations = 25;
  static const int defaultMaxFailedTasks = 3;

  /// Revision of the canonical project snapshot.
  @MappableField(hook: JsonIntHook(min: 0))
  final int persistenceRevision;
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook(fallback: 'Untitled project'))
  final String title;
  @MappableField(hook: JsonStringHook())
  final String originalGoal;
  @MappableField(hook: JsonStringHook())
  final String refinedGoal;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectCriterion> criteria;
  @MappableField(hook: JsonStringListHook())
  final List<String> constraints;
  @MappableField(hook: JsonStringListHook())
  final List<String> taskIds;
  @MappableField(hook: JsonStringListHook())
  final List<String> currentBatchTaskIds;
  @MappableField(hook: JsonIntHook(min: 0))
  final int currentBatchIndex;
  @MappableField(hook: JsonIntHook(min: 0))
  final int currentBatchPlanRevision;
  @MappableField(hook: JsonBoolHook())
  final bool currentBatchProgressObserved;
  @MappableField(hook: JsonNullableStringHook())
  final String? pendingReplanReason;
  @MappableField(hook: JsonObjectListHook())
  final List<Task> tasks;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskArtifact> artifacts;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectRecoveryIncident> recoveryIncidents;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectEvidence> evidence;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectMilestone> milestones;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectMemoryEntry> memory;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectPlanRevision> planHistory;
  final PendingProjectPlanApproval? pendingPlanApproval;
  final List<ProjectPlanRevisionTrigger> pendingReplanTriggers;
  final ProjectCompletionReviewCheckpoint? completionReviewCheckpoint;
  @MappableField(hook: JsonObjectListHook())
  final List<PendingProjectQuestion> openQuestions;
  final ProjectStatus status;
  @MappableField(hook: JsonIntHook())
  final int iterationCount;
  @MappableField(
    hook: JsonIntHook(fallback: ProjectState.defaultMaxIterations, min: 0),
  )
  final int maxIterations;
  @MappableField(
    hook: JsonIntHook(
      fallback: ProjectState.defaultMaxFailedTasks,
      min: 1,
      max: 100,
    ),
  )
  final int maxFailedTasks;
  @MappableField(hook: JsonNullableStringHook())
  final String? activeTaskId;
  @MappableField(hook: JsonNullableStringHook())
  final String? chatSessionId;
  @MappableField(hook: JsonStringHook())
  final String completionSummary;
  final ProjectBlocker? blocker;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectDecisionRecord> decisions;
  final ProjectDiagnostics diagnostics;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? completedAt;

  ProjectState({
    this.persistenceRevision = 0,
    required this.id,
    required this.title,
    required this.originalGoal,
    required this.refinedGoal,
    required this.criteria,
    required this.constraints,
    List<Task>? tasks,
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
    List<ProjectPlanRevision>? planHistory,
    this.pendingPlanApproval,
    this.pendingReplanTriggers = const [],
    this.completionReviewCheckpoint,
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
  }) : tasks = tasks ?? const [],
       taskIds = taskIds ?? tasks?.map((task) => task.id).toList() ?? const [],
       artifacts = artifacts ?? const [],
       recoveryIncidents = recoveryIncidents ?? const [],
       evidence = evidence ?? const [],
       milestones = milestones ?? const [],
       memory = memory ?? const [],
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

  List<String> criterionStatementsFor(Task task) => [
    for (final criterionId in task.criterionIds)
      criterionStatement(criterionId),
  ];

  Task? taskById(String id) {
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

  ProjectState copyWith({
    int? persistenceRevision,
    String? id,
    String? title,
    String? originalGoal,
    String? refinedGoal,
    List<ProjectCriterion>? criteria,
    List<String>? constraints,
    List<Task>? tasks,
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
    List<ProjectPlanRevision>? planHistory,
    Object? pendingPlanApproval = kSentinel,
    List<ProjectPlanRevisionTrigger>? pendingReplanTriggers,
    Object? completionReviewCheckpoint = kSentinel,
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
    return ProjectState(
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

typedef ProjectDocument = ProjectState;

@MappableClass(ignoreNull: true)
class ProjectRecoveryIncident with ProjectRecoveryIncidentMappable {
  static const int defaultMaxAttempts = 3;

  @MappableField(hook: JsonStringHook(fallback: 'recovery_incident'))
  final String id;
  final ProjectRecoveryIncidentStatus status;
  @MappableField(hook: JsonStringListHook())
  final List<String> sourceTaskIds;
  @MappableField(hook: JsonStringListHook())
  final List<String> sourceTaskTitles;
  @MappableField(hook: JsonStringHook())
  final String failedGateId;
  @MappableField(hook: JsonNullableStringHook())
  final String? command;
  @MappableField(hook: JsonNullableStringHook())
  final String? workingDirectory;
  @MappableField(hook: JsonStringHook())
  final String failureSummary;
  @MappableField(hook: JsonIntHook())
  final int attemptCount;
  @MappableField(
    hook: JsonIntHook(
      fallback: ProjectRecoveryIncident.defaultMaxAttempts,
      min: 1,
      max: 100,
    ),
  )
  final int maxAttempts;
  @MappableField(hook: JsonStringListHook())
  final List<String> recoveryTaskIds;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? resolvedAt;

  const ProjectRecoveryIncident({
    required this.id,
    required this.status,
    required this.sourceTaskIds,
    required this.sourceTaskTitles,
    required this.failedGateId,
    this.command,
    this.workingDirectory,
    required this.failureSummary,
    required this.attemptCount,
    this.maxAttempts = defaultMaxAttempts,
    required this.recoveryTaskIds,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
  });

  ProjectRecoveryIncident copyWith({
    String? id,
    ProjectRecoveryIncidentStatus? status,
    List<String>? sourceTaskIds,
    List<String>? sourceTaskTitles,
    Object? command = kSentinel,
    Object? workingDirectory = kSentinel,
    String? failedGateId,
    String? failureSummary,
    int? attemptCount,
    int? maxAttempts,
    List<String>? recoveryTaskIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? resolvedAt = kSentinel,
  }) {
    return ProjectRecoveryIncident(
      id: id ?? this.id,
      status: status ?? this.status,
      sourceTaskIds: sourceTaskIds ?? this.sourceTaskIds,
      sourceTaskTitles: sourceTaskTitles ?? this.sourceTaskTitles,
      failedGateId: failedGateId ?? this.failedGateId,
      command: resolve(command, this.command),
      workingDirectory: resolve(workingDirectory, this.workingDirectory),
      failureSummary: failureSummary ?? this.failureSummary,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      recoveryTaskIds: recoveryTaskIds ?? this.recoveryTaskIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resolvedAt: resolve(resolvedAt, this.resolvedAt),
    );
  }
}

class TaskResult {
  final String taskId;
  final TaskStatus status;
  final String summary;
  final String memoryUpdate;
  final List<TaskArtifact> artifacts;
  final List<TaskGateResult> gateResults;
  final List<TaskEvidenceClaim> evidenceClaims;
  final String? finalRunId;
  final int toolCallCount;
  final String? userQuestion;
  final String? error;
  final bool projectReplanRequested;

  const TaskResult({
    required this.taskId,
    required this.status,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
    this.gateResults = const [],
    this.evidenceClaims = const [],
    this.finalRunId,
    required this.toolCallCount,
    this.userQuestion,
    this.error,
    this.projectReplanRequested = false,
  });
}

class ProjectEvaluation {
  final String taskId;
  final bool taskAccepted;
  final bool projectComplete;
  final String summary;
  final List<String> completedCriteria;
  final List<String> remainingCriteria;
  final List<String> newKnownFacts;
  final List<TaskArtifact> artifacts;
  final List<TaskGateResult> gateResults;
  final List<Task> taskAdditions;
  final List<PendingProjectQuestion> openQuestions;
  final String? failureReason;
  final bool projectReplanRequested;

  const ProjectEvaluation({
    required this.taskId,
    required this.taskAccepted,
    required this.projectComplete,
    required this.summary,
    required this.completedCriteria,
    required this.remainingCriteria,
    required this.newKnownFacts,
    required this.artifacts,
    this.gateResults = const [],
    required this.taskAdditions,
    required this.openQuestions,
    this.failureReason,
    this.projectReplanRequested = false,
  });
}

@MappableClass(ignoreNull: true)
class ProjectDecisionRecord with ProjectDecisionRecordMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  final ProjectDecisionType decision;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonStringHook())
  final String memoryUpdate;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskId;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskTitle;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskPrompt;
  @MappableField(hook: JsonNullableStringHook())
  final String? error;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;

  const ProjectDecisionRecord({
    required this.id,
    required this.decision,
    required this.summary,
    required this.memoryUpdate,
    required this.createdAt,
    this.taskId,
    this.taskTitle,
    this.taskPrompt,
    this.error,
  });

  ProjectDecisionRecord copyWith({
    String? id,
    ProjectDecisionType? decision,
    String? summary,
    String? memoryUpdate,
    Object? taskId = kSentinel,
    Object? taskTitle = kSentinel,
    Object? taskPrompt = kSentinel,
    Object? error = kSentinel,
    DateTime? createdAt,
  }) {
    return ProjectDecisionRecord(
      id: id ?? this.id,
      decision: decision ?? this.decision,
      summary: summary ?? this.summary,
      memoryUpdate: memoryUpdate ?? this.memoryUpdate,
      taskId: resolve(taskId, this.taskId),
      taskTitle: resolve(taskTitle, this.taskTitle),
      taskPrompt: resolve(taskPrompt, this.taskPrompt),
      error: resolve(error, this.error),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  ProjectDecisionRecord copyWithTask({String? taskId, String? taskTitle}) {
    return copyWith(taskId: taskId, taskTitle: taskTitle);
  }
}

@MappableClass(ignoreNull: true)
class ProjectBlocker with ProjectBlockerMappable {
  final ProjectBlockerType type;
  @MappableField(hook: JsonStringHook())
  final String message;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskId;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;

  const ProjectBlocker({
    required this.type,
    required this.message,
    required this.createdAt,
    this.taskId,
  });
}

@MappableClass(ignoreNull: true)
class PendingProjectQuestion with PendingProjectQuestionMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook())
  final String question;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;

  const PendingProjectQuestion({
    required this.id,
    required this.question,
    required this.createdAt,
  });
}

class ProjectSummary {
  final String id;
  final String title;
  final ProjectStatus status;
  final DateTime updatedAt;
  final String? activeTaskId;
  final String? chatSessionId;

  const ProjectSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.activeTaskId,
    this.chatSessionId,
  });
}

String projectTaskFingerprint(String objective, List<String> criteria) {
  final parts = [
    objective,
    ...criteria,
  ].map(_normaliseFingerprintPart).where((item) => item.isNotEmpty).toList();
  return parts.join('|').ifEmpty(_normaliseFingerprintPart(objective));
}

String _normaliseFingerprintPart(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
