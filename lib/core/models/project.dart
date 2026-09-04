import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'project.mapper.dart';
part 'project_json_migration.dart';

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

@MappableEnum(defaultValue: ProjectPhase.discovery)
enum ProjectPhase { discovery, planning, execution, verification, finalization }

@MappableEnum(defaultValue: ProjectTaskStatus.queued)
enum ProjectTaskStatus {
  queued,
  proposed,
  approved,
  running,
  completed,
  failed,
  rejected,
  split,
  deferred,
  obsolete,
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

@MappableEnum(defaultValue: ProjectEvidenceType.taskClaim)
enum ProjectEvidenceType {
  gate,
  artifact,
  command,
  @MappableValue('task_claim')
  taskClaim,
  @MappableValue('user_approval')
  userApproval,
  migrated,
}

@MappableEnum(defaultValue: ProjectEvidenceStatus.proposed)
enum ProjectEvidenceStatus { proposed, accepted, rejected, stale }

@MappableEnum(defaultValue: ProjectEvidenceStrength.advisory)
enum ProjectEvidenceStrength { advisory, supporting, conclusive }

@MappableEnum(defaultValue: ProjectMilestoneStatus.planned)
enum ProjectMilestoneStatus { planned, active, completed, blocked, cancelled }

@MappableEnum(defaultValue: ProjectTaskPriority.normal)
enum ProjectTaskPriority { critical, high, normal, low }

@MappableEnum(defaultValue: ProjectTaskRisk.unknown)
enum ProjectTaskRisk { high, medium, low, unknown }

@MappableEnum(defaultValue: ProjectRiskReduction.none)
enum ProjectRiskReduction { high, medium, low, none }

@MappableEnum(defaultValue: ProjectTaskEffort.small)
enum ProjectTaskEffort { small, medium, large }

@MappableEnum(defaultValue: ProjectTaskReadiness.ready)
enum ProjectTaskReadiness {
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
enum ProjectMemorySourceType { user, planner, task, gate, migration, system }

@MappableEnum(defaultValue: ProjectMemoryConfidence.inferred)
enum ProjectMemoryConfidence { confirmed, inferred, uncertain }

@MappableEnum(defaultValue: ProjectPlanRevisionTrigger.initialization)
enum ProjectPlanRevisionTrigger {
  initialization,
  migration,
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
  @MappableValue('task_approval')
  taskApproval,
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
  @MappableValue('refresh_backlog')
  refreshBacklog,
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

extension ProjectPhaseWire on ProjectPhase {
  String get wire => name;
}

extension ProjectTaskStatusWire on ProjectTaskStatus {
  String get wire => name;
}

extension ProjectBlockerTypeWire on ProjectBlockerType {
  String get wire => switch (this) {
    ProjectBlockerType.taskApproval => 'task_approval',
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
  final int completedTasksWithoutCriterionProgress;
  final int criterionReversals;
  final int noReadyTaskBlocks;
  final int userApprovals;
  final int userQuestions;
  final int consecutiveNoProgressIterations;
  @MappableField(hook: JsonStringListHook())
  final List<String> recentNoProgressTaskIds;

  const ProjectDiagnostics({
    this.projectModelCalls = 0,
    this.planRevisionAttempts = 0,
    this.invalidPlanProposals = 0,
    this.taskExecutions = 0,
    this.completedTaskExecutions = 0,
    this.completedTasksWithoutCriterionProgress = 0,
    this.criterionReversals = 0,
    this.noReadyTaskBlocks = 0,
    this.userApprovals = 0,
    this.userQuestions = 0,
    this.consecutiveNoProgressIterations = 0,
    this.recentNoProgressTaskIds = const [],
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
    int? completedTasksWithoutCriterionProgress,
    int? criterionReversals,
    int? noReadyTaskBlocks,
    int? userApprovals,
    int? userQuestions,
    int? consecutiveNoProgressIterations,
    List<String>? recentNoProgressTaskIds,
  }) {
    return ProjectDiagnostics(
      projectModelCalls: projectModelCalls ?? this.projectModelCalls,
      planRevisionAttempts: planRevisionAttempts ?? this.planRevisionAttempts,
      invalidPlanProposals: invalidPlanProposals ?? this.invalidPlanProposals,
      taskExecutions: taskExecutions ?? this.taskExecutions,
      completedTaskExecutions:
          completedTaskExecutions ?? this.completedTaskExecutions,
      completedTasksWithoutCriterionProgress:
          completedTasksWithoutCriterionProgress ??
          this.completedTasksWithoutCriterionProgress,
      criterionReversals: criterionReversals ?? this.criterionReversals,
      noReadyTaskBlocks: noReadyTaskBlocks ?? this.noReadyTaskBlocks,
      userApprovals: userApprovals ?? this.userApprovals,
      userQuestions: userQuestions ?? this.userQuestions,
      consecutiveNoProgressIterations:
          consecutiveNoProgressIterations ??
          this.consecutiveNoProgressIterations,
      recentNoProgressTaskIds:
          recentNoProgressTaskIds ?? this.recentNoProgressTaskIds,
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
    ProjectDecisionType.refreshBacklog => 'refresh_backlog',
    ProjectDecisionType.retryRecovery => 'retry_recovery',
    ProjectDecisionType.applyPlanRevision => 'apply_plan_revision',
    ProjectDecisionType.approvePlanRevision => 'approve_plan_revision',
    ProjectDecisionType.rejectPlanRevision => 'reject_plan_revision',
    _ => name,
  };
}

ProjectStatus parseProjectStatus(Object? value) => _parseEnum(
  ProjectStatus.values,
  value,
  ProjectStatus.active,
  aliases: {
    'running': ProjectStatus.runningTask,
    'running_task': ProjectStatus.runningTask,
    'runningtask': ProjectStatus.runningTask,
    'reviewing_task': ProjectStatus.reviewingTask,
    'reviewingtask': ProjectStatus.reviewingTask,
    'waiting_for_user': ProjectStatus.waitingForUser,
    'waitingforuser': ProjectStatus.waitingForUser,
  },
);

@MappableClass(ignoreNull: true)
class ProjectCriterion with ProjectCriterionMappable {
  final String id;
  final String statement;
  final bool required;
  final ProjectCriterionStatus status;
  final ProjectVerificationMode verificationMode;
  final List<String> evidenceIds;
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
    this.evidenceIds = const [],
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
    List<String>? evidenceIds,
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
      evidenceIds: evidenceIds ?? this.evidenceIds,
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
  final String? projectTaskId;
  final String? taskDocumentId;
  final String? taskRunId;
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
    this.projectTaskId,
    this.taskDocumentId,
    this.taskRunId,
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
    Object? projectTaskId = kSentinel,
    Object? taskDocumentId = kSentinel,
    Object? taskRunId = kSentinel,
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
      projectTaskId: resolve(projectTaskId, this.projectTaskId),
      taskDocumentId: resolve(taskDocumentId, this.taskDocumentId),
      taskRunId: resolve(taskRunId, this.taskRunId),
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
  final List<String> taskIds;
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
    this.taskIds = const [],
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });
}

@MappableClass(ignoreNull: true)
class ProjectEvidenceExpectation with ProjectEvidenceExpectationMappable {
  final String id;
  final ProjectEvidenceType type;
  final List<String> criterionIds;
  final String description;
  final bool required;
  final String? sourceRef;
  final Map<String, dynamic> details;

  const ProjectEvidenceExpectation({
    required this.id,
    required this.type,
    this.criterionIds = const [],
    required this.description,
    this.required = true,
    this.sourceRef,
    this.details = const {},
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

/// A proposed, non-authoritative edit to the rolling project plan.
///
/// Completed task history, evidence, gate results, and recovery incidents are
/// deliberately absent: a planner cannot propose mutations to those records.
@MappableClass(ignoreNull: true)
class ProjectPlanProposal with ProjectPlanProposalMappable {
  final int revision;
  final List<ProjectPlanRevisionTrigger> triggers;
  final String summary;
  final String rationale;
  final List<String> assumptions;
  final List<ProjectCriterion> criterionUpserts;
  final List<String> removedCriterionIds;
  final List<ProjectMilestone> milestoneUpserts;
  final List<String> removedMilestoneIds;
  final List<ProjectTask> taskAdditions;
  final List<ProjectTask> taskUpdates;
  final List<String> deferredTaskIds;
  final List<String> obsoleteTaskIds;
  final List<ProjectMemoryEntry> memoryAdditions;
  final List<ProjectMemorySupersession> memorySupersessions;
  final List<PendingProjectQuestion> openQuestions;
  final bool requiresApproval;
  final String approvalReason;
  final DateTime createdAt;

  const ProjectPlanProposal({
    required this.revision,
    this.triggers = const [],
    required this.summary,
    required this.rationale,
    this.assumptions = const [],
    this.criterionUpserts = const [],
    this.removedCriterionIds = const [],
    this.milestoneUpserts = const [],
    this.removedMilestoneIds = const [],
    this.taskAdditions = const [],
    this.taskUpdates = const [],
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
  final DateTime createdAt;
  final ProjectPlanProposal? proposal;

  const PendingProjectPlanApproval({
    required this.revision,
    required this.reason,
    required this.summary,
    this.highRiskChanges = const [],
    required this.createdAt,
    this.proposal,
  });
}

@MappableEnum(defaultValue: ProjectRecoveryIncidentStatus.active)
enum ProjectRecoveryIncidentStatus { active, resolved, exhausted }

extension ProjectRecoveryIncidentStatusWire on ProjectRecoveryIncidentStatus {
  String get wire => name;
}

T _parseEnum<T extends Enum>(
  List<T> values,
  Object? value,
  T fallback, {
  Map<String, T> aliases = const {},
}) {
  final raw = value?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty) return fallback;
  final normalised = raw.replaceAll('-', '_');
  final alias = aliases[normalised] ?? aliases[normalised.replaceAll('_', '')];
  if (alias != null) return alias;
  for (final item in values) {
    if (item.name.toLowerCase() == normalised ||
        item.name.toLowerCase() == normalised.replaceAll('_', '')) {
      return item;
    }
  }
  return fallback;
}

@MappableClass(ignoreNull: true, hook: ProjectStateJsonHook())
class ProjectState with ProjectStateMappable {
  static const int currentSchemaVersion = 3;
  static const int defaultMaxIterations = 25;
  static const int defaultMaxFailedTasks = 3;

  @MappableField(hook: JsonIntHook())
  final int schemaVersion;
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
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectTask> backlog;
  final ProjectTask? currentTask;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectTask> completedTasks;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectTask> failedTasks;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectArtifact> artifacts;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectRecoveryIncident> recoveryIncidents;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectEvidence> evidence;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectMilestone> milestones;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectMemoryEntry> memory;
  @MappableField(hook: JsonIntHook(fallback: 1, min: 1))
  final int currentRevision;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectPlanRevision> planHistory;
  final PendingProjectPlanApproval? pendingPlanApproval;
  final List<ProjectPlanRevisionTrigger> pendingReplanTriggers;
  @MappableField(hook: JsonObjectListHook())
  final List<PendingProjectQuestion> openQuestions;
  @MappableField(
    hook: EnumAliasHook({
      'running': 'running_task',
      'runningtask': 'running_task',
      'reviewingtask': 'reviewing_task',
      'waitingforuser': 'waiting_for_user',
    }),
  )
  final ProjectStatus status;
  @MappableField(hook: EnumAliasHook({}))
  final ProjectPhase phase;
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
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.title,
    String? originalGoal,
    String? refinedGoal,
    String? originalPrompt,
    String? goal,
    List<ProjectCriterion>? criteria,
    List<String>? successCriteria,
    required this.constraints,
    List<ProjectTask>? backlog,
    ProjectTask? currentTask,
    List<ProjectTask>? completedTasks,
    List<ProjectTask>? failedTasks,
    List<ProjectArtifact>? artifacts,
    List<ProjectRecoveryIncident>? recoveryIncidents,
    List<ProjectEvidence>? evidence,
    List<ProjectMilestone>? milestones,
    List<ProjectMemoryEntry>? memory,
    List<String>? knownFacts,
    int? currentRevision,
    List<ProjectPlanRevision>? planHistory,
    this.pendingPlanApproval,
    this.pendingReplanTriggers = const [],
    List<PendingProjectQuestion>? openQuestions,
    String? memorySummary,
    List<ProjectTaskRef>? tasks,
    PendingProjectQuestion? pendingQuestion,
    required this.status,
    ProjectPhase? phase,
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
  }) : originalGoal = originalGoal ?? originalPrompt ?? '',
       refinedGoal =
           refinedGoal ?? goal ?? originalGoal ?? originalPrompt ?? '',
       backlog = _bindTaskCriteria(
         backlog ?? _legacyBacklog(tasks, activeTaskId),
         criteria,
         successCriteria,
       ),
       currentTask = _bindSingleTaskCriteria(
         currentTask ?? _legacyCurrentTask(tasks, activeTaskId),
         criteria,
         successCriteria,
       ),
       completedTasks = _bindTaskCriteria(
         completedTasks ?? _legacyCompletedTasks(tasks),
         criteria,
         successCriteria,
       ),
       failedTasks = _bindTaskCriteria(
         failedTasks ?? _legacyFailedTasks(tasks),
         criteria,
         successCriteria,
       ),
       artifacts = artifacts ?? const [],
       recoveryIncidents = recoveryIncidents ?? const [],
       criteria =
           criteria ??
           _criteriaFromStatements(successCriteria ?? const [], createdAt),
       evidence = evidence ?? const [],
       milestones = milestones ?? const [],
       memory =
           memory ??
           _memoryFromFacts(
             knownFacts ??
                 [
                   if (memorySummary?.trim().isNotEmpty == true)
                     memorySummary!.trim(),
                 ],
             createdAt,
           ),
       currentRevision = currentRevision ?? 1,
       planHistory =
           planHistory ??
           [
             ProjectPlanRevision(
               revision: currentRevision ?? 1,
               trigger: ProjectPlanRevisionTrigger.initialization,
               summary: 'Initial project plan.',
               rationale: 'Created from the initial project definition.',
               createdAt: createdAt,
               approvedAt: createdAt,
               approvedBy: ProjectPlanRevisionApprover.automatic,
             ),
           ],
       openQuestions = openQuestions ?? [?pendingQuestion],
       phase =
           phase ??
           (status == ProjectStatus.completed
               ? ProjectPhase.finalization
               : currentTask != null || activeTaskId != null
               ? ProjectPhase.execution
               : ProjectPhase.planning),
       iterationCount =
           iterationCount ??
           (completedTasks?.length ??
               tasks
                   ?.where((task) => task.status == TaskStatus.completed)
                   .length ??
               0);

  bool get isTerminal =>
      status == ProjectStatus.completed ||
      status == ProjectStatus.cancelled ||
      status == ProjectStatus.failed;

  String get originalPrompt => originalGoal;

  String get goal => refinedGoal;

  List<String> get successCriteria => [
    for (final criterion in criteria) criterion.statement,
  ];

  List<String> get knownFacts => [
    for (final entry in memory)
      if (entry.active) entry.content,
  ];

  String get memorySummary => knownFacts.join('\n\n');

  String criterionStatement(String criterionId) {
    for (final criterion in criteria) {
      if (criterion.id == criterionId) return criterion.statement;
    }
    return criterionId;
  }

  List<String> criterionStatementsFor(ProjectTask task) => [
    for (final criterionId in task.criterionIds)
      criterionStatement(criterionId),
  ];

  PendingProjectQuestion? get pendingQuestion =>
      openQuestions.isEmpty ? null : openQuestions.first;

  List<ProjectTaskRef> get tasks {
    final refs = <ProjectTaskRef>[
      ...completedTasks.map(ProjectTaskRef.fromProjectTask),
      ...failedTasks.map(ProjectTaskRef.fromProjectTask),
      if (currentTask != null) ProjectTaskRef.fromProjectTask(currentTask!),
      ...backlog.map(ProjectTaskRef.fromProjectTask),
    ];
    final seen = <String>{};
    return [
      for (final ref in refs)
        if (seen.add(ref.taskId)) ref,
    ];
  }

  ProjectTask? taskById(String id) {
    if (currentTask?.id == id || currentTask?.taskDocumentId == id) {
      return currentTask;
    }
    for (final task in [...backlog, ...completedTasks, ...failedTasks]) {
      if (task.id == id || task.taskDocumentId == id) return task;
    }
    return null;
  }

  ProjectTaskRef? taskRef(String taskId) {
    for (final task in tasks) {
      if (task.taskId == taskId) return task;
    }
    return null;
  }

  static List<ProjectTask> _legacyBacklog(
    List<ProjectTaskRef>? tasks,
    String? activeTaskId,
  ) {
    if (tasks == null) return const [];
    return [
      for (final task in tasks)
        if (task.taskId != activeTaskId &&
            task.status != TaskStatus.completed &&
            task.status != TaskStatus.failed &&
            task.status != TaskStatus.cancelled &&
            task.status != TaskStatus.blocked)
          ProjectTask.fromLegacyRef(
            task,
          ).copyWith(status: ProjectTaskStatus.queued),
    ];
  }

  static ProjectTask? _legacyCurrentTask(
    List<ProjectTaskRef>? tasks,
    String? activeTaskId,
  ) {
    if (tasks == null || activeTaskId == null) return null;
    for (final task in tasks) {
      if (task.taskId == activeTaskId) {
        return ProjectTask.fromLegacyRef(
          task,
        ).copyWith(status: ProjectTaskStatus.running);
      }
    }
    return null;
  }

  static List<ProjectTask> _legacyCompletedTasks(List<ProjectTaskRef>? tasks) {
    if (tasks == null) return const [];
    return [
      for (final task in tasks)
        if (task.status == TaskStatus.completed)
          ProjectTask.fromLegacyRef(
            task,
          ).copyWith(status: ProjectTaskStatus.completed),
    ];
  }

  static List<ProjectTask> _legacyFailedTasks(List<ProjectTaskRef>? tasks) {
    if (tasks == null) return const [];
    return [
      for (final task in tasks)
        if (task.status == TaskStatus.failed ||
            task.status == TaskStatus.cancelled ||
            task.status == TaskStatus.blocked)
          ProjectTask.fromLegacyRef(
            task,
          ).copyWith(status: ProjectTaskStatus.failed),
    ];
  }

  static List<ProjectTask> _bindTaskCriteria(
    List<ProjectTask> tasks,
    List<ProjectCriterion>? structuredCriteria,
    List<String>? legacyCriteria,
  ) {
    return [
      for (final task in tasks)
        _bindSingleTaskCriteria(task, structuredCriteria, legacyCriteria)!,
    ];
  }

  static ProjectTask? _bindSingleTaskCriteria(
    ProjectTask? task,
    List<ProjectCriterion>? structuredCriteria,
    List<String>? legacyCriteria,
  ) {
    if (task == null) return null;
    final available =
        structuredCriteria ??
        _criteriaFromStatements(legacyCriteria ?? const [], task.createdAt);
    final byId = {
      for (final criterion in available) criterion.id: criterion.id,
    };
    final byStatement = {
      for (final criterion in available)
        _normaliseFingerprintPart(criterion.statement): criterion.id,
    };
    final ids = <String>[];
    final unmatched = <String>[];
    for (final value in task.criterionIds) {
      final id = byId[value] ?? byStatement[_normaliseFingerprintPart(value)];
      if (id == null) {
        unmatched.add(value);
      } else if (!ids.contains(id)) {
        ids.add(id);
      }
    }
    return task.copyWith(
      criterionIds: ids,
      context: [
        ...task.context,
        for (final value in unmatched)
          if (!task.context.contains('Unmatched project criterion: $value'))
            'Unmatched project criterion: $value',
      ],
    );
  }

  ProjectState copyWith({
    int? schemaVersion,
    String? id,
    String? title,
    String? originalGoal,
    String? refinedGoal,
    List<ProjectCriterion>? criteria,
    List<String>? successCriteria,
    List<String>? constraints,
    List<ProjectTask>? backlog,
    Object? currentTask = kSentinel,
    List<ProjectTask>? completedTasks,
    List<ProjectTask>? failedTasks,
    List<ProjectArtifact>? artifacts,
    List<ProjectRecoveryIncident>? recoveryIncidents,
    List<ProjectEvidence>? evidence,
    List<ProjectMilestone>? milestones,
    List<ProjectMemoryEntry>? memory,
    List<String>? knownFacts,
    int? currentRevision,
    List<ProjectPlanRevision>? planHistory,
    Object? pendingPlanApproval = kSentinel,
    List<ProjectPlanRevisionTrigger>? pendingReplanTriggers,
    List<PendingProjectQuestion>? openQuestions,
    Object? pendingQuestion = kSentinel,
    ProjectStatus? status,
    ProjectPhase? phase,
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
    final Object? resolvedPendingQuestion = resolve<Object?>(
      pendingQuestion,
      kSentinel,
    );
    final nextOpenQuestions = resolvedPendingQuestion == kSentinel
        ? openQuestions ?? this.openQuestions
        : resolvedPendingQuestion == null
        ? const <PendingProjectQuestion>[]
        : [resolvedPendingQuestion as PendingProjectQuestion];

    return ProjectState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      title: title ?? this.title,
      originalGoal: originalGoal ?? this.originalGoal,
      refinedGoal: refinedGoal ?? this.refinedGoal,
      criteria:
          criteria ??
          (successCriteria == null
              ? this.criteria
              : _criteriaFromStatements(
                  successCriteria,
                  updatedAt ?? this.updatedAt,
                )),
      constraints: constraints ?? this.constraints,
      backlog: backlog ?? this.backlog,
      currentTask: resolve(currentTask, this.currentTask),
      completedTasks: completedTasks ?? this.completedTasks,
      failedTasks: failedTasks ?? this.failedTasks,
      artifacts: artifacts ?? this.artifacts,
      recoveryIncidents: recoveryIncidents ?? this.recoveryIncidents,
      evidence: evidence ?? this.evidence,
      milestones: milestones ?? this.milestones,
      memory:
          memory ??
          (knownFacts == null
              ? this.memory
              : _mergeMemoryFacts(
                  this.memory,
                  knownFacts,
                  updatedAt ?? this.updatedAt,
                )),
      currentRevision: currentRevision ?? this.currentRevision,
      planHistory: planHistory ?? this.planHistory,
      pendingPlanApproval: resolve(
        pendingPlanApproval,
        this.pendingPlanApproval,
      ),
      pendingReplanTriggers:
          pendingReplanTriggers ?? this.pendingReplanTriggers,
      openQuestions: nextOpenQuestions,
      status: status ?? this.status,
      phase: phase ?? this.phase,
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

List<ProjectCriterion> _criteriaFromStatements(
  List<String> statements,
  DateTime timestamp,
) {
  return [
    for (var index = 0; index < statements.length; index++)
      ProjectCriterion(
        id: 'criterion_${(index + 1).toString().padLeft(3, '0')}',
        statement: statements[index],
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
  ];
}

List<ProjectMemoryEntry> _memoryFromFacts(
  List<String> facts,
  DateTime timestamp,
) {
  return [
    for (var index = 0; index < facts.length; index++)
      ProjectMemoryEntry(
        id: 'memory_${(index + 1).toString().padLeft(3, '0')}',
        kind: ProjectMemoryKind.fact,
        content: facts[index],
        sourceType: ProjectMemorySourceType.planner,
        confidence: ProjectMemoryConfidence.inferred,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
  ];
}

List<ProjectMemoryEntry> _mergeMemoryFacts(
  List<ProjectMemoryEntry> existing,
  List<String> facts,
  DateTime timestamp,
) {
  final activeByContent = <String, ProjectMemoryEntry>{
    for (final entry in existing)
      if (entry.active) _normaliseFingerprintPart(entry.content): entry,
  };
  final retainedIds = <String>{};
  final usedIds = {for (final entry in existing) entry.id};
  var nextIndex = existing.length + 1;
  final merged = <ProjectMemoryEntry>[
    for (final entry in existing)
      if (!entry.active) entry,
  ];
  for (final fact in facts) {
    final key = _normaliseFingerprintPart(fact);
    final retained = activeByContent[key];
    if (retained != null) {
      if (retainedIds.add(retained.id)) merged.add(retained);
      continue;
    }
    final fromUser =
        fact.startsWith('User answered:') ||
        fact.startsWith('User added project context:');
    var id = 'memory_${nextIndex.toString().padLeft(3, '0')}';
    while (usedIds.contains(id)) {
      nextIndex++;
      id = 'memory_${nextIndex.toString().padLeft(3, '0')}';
    }
    usedIds.add(id);
    merged.add(
      ProjectMemoryEntry(
        id: id,
        kind: fromUser ? ProjectMemoryKind.requirement : ProjectMemoryKind.fact,
        content: fact,
        sourceType: fromUser
            ? ProjectMemorySourceType.user
            : ProjectMemorySourceType.planner,
        confidence: fromUser
            ? ProjectMemoryConfidence.confirmed
            : ProjectMemoryConfidence.inferred,
        protected: fromUser,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    nextIndex++;
  }
  return merged;
}

typedef ProjectDocument = ProjectState;
typedef ProjectSnapshot = ProjectState;

@MappableClass(ignoreNull: true)
class ProjectRecoveryIncident with ProjectRecoveryIncidentMappable {
  static const int defaultMaxAttempts = 3;

  @MappableField(hook: JsonStringHook(fallback: 'recovery_incident'))
  final String id;
  @MappableField(hook: EnumAliasHook({}))
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

@MappableClass(ignoreNull: true, hook: ProjectTaskJsonHook())
class ProjectTask with ProjectTaskMappable {
  @MappableField(hook: JsonStringHook(fallback: 'project_task'))
  final String id;
  @MappableField(hook: JsonStringHook(fallback: 'Untitled task'))
  final String title;
  @MappableField(hook: JsonStringHook())
  final String objective;
  @MappableField(hook: JsonStringListHook())
  final List<String> criterionIds;
  @MappableField(hook: JsonNullableStringHook())
  final String? milestoneId;
  @MappableField(hook: JsonStringListHook())
  final List<String> dependsOnTaskIds;
  final ProjectTaskPriority priority;
  final ProjectTaskRisk risk;
  final ProjectRiskReduction riskReduction;
  final ProjectTaskEffort effort;
  final ProjectTaskReadiness readiness;
  @MappableField(hook: JsonStringListHook())
  final List<String> readinessReasons;
  @MappableField(hook: JsonStringHook())
  final String selectionRationale;
  @MappableField(hook: JsonIntHook(fallback: 1, min: 1))
  final int revisionIntroduced;
  @MappableField(hook: JsonIntHook(fallback: 1, min: 1))
  final int revisionUpdated;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectEvidenceExpectation> expectedEvidence;
  @MappableField(hook: JsonStringListHook())
  final List<String> readPaths;
  @MappableField(hook: JsonStringListHook())
  final List<String> writePaths;
  @MappableField(hook: JsonStringListHook())
  final List<String> doneCriteria;
  @MappableField(hook: JsonStringListHook())
  final List<String> outOfScope;
  @MappableField(hook: JsonStringListHook())
  final List<String> context;
  @MappableField(hook: JsonObjectListHook())
  final List<ProjectArtifact> expectedArtifacts;
  @MappableField(hook: EnumAliasHook({}))
  final ProjectTaskStatus status;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskDocumentId;
  @MappableField(hook: JsonNullableStringHook())
  final String? recoveryIncidentId;
  @MappableField(hook: JsonStringHook())
  final String fingerprint;
  @MappableField(hook: JsonNullableStringHook())
  final String? rejectionReason;
  final ProjectTaskFailure? failure;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;

  const ProjectTask({
    required this.id,
    required this.title,
    required this.objective,
    List<String>? criterionIds,
    List<String>? relevantSuccessCriteria,
    this.milestoneId,
    this.dependsOnTaskIds = const [],
    this.priority = ProjectTaskPriority.normal,
    this.risk = ProjectTaskRisk.unknown,
    this.riskReduction = ProjectRiskReduction.none,
    this.effort = ProjectTaskEffort.small,
    this.readiness = ProjectTaskReadiness.ready,
    this.readinessReasons = const [],
    this.selectionRationale = '',
    this.revisionIntroduced = 1,
    this.revisionUpdated = 1,
    this.expectedEvidence = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    required this.doneCriteria,
    required this.outOfScope,
    required this.context,
    required this.expectedArtifacts,
    required this.status,
    required this.taskDocumentId,
    this.recoveryIncidentId,
    required this.fingerprint,
    required this.rejectionReason,
    this.failure,
    required this.createdAt,
    required this.updatedAt,
  }) : criterionIds = criterionIds ?? relevantSuccessCriteria ?? const [];

  List<String> get relevantSuccessCriteria => criterionIds;

  ProjectTask copyWith({
    String? id,
    String? title,
    String? objective,
    List<String>? criterionIds,
    List<String>? relevantSuccessCriteria,
    Object? milestoneId = kSentinel,
    List<String>? dependsOnTaskIds,
    ProjectTaskPriority? priority,
    ProjectTaskRisk? risk,
    ProjectRiskReduction? riskReduction,
    ProjectTaskEffort? effort,
    ProjectTaskReadiness? readiness,
    List<String>? readinessReasons,
    String? selectionRationale,
    int? revisionIntroduced,
    int? revisionUpdated,
    List<ProjectEvidenceExpectation>? expectedEvidence,
    List<String>? readPaths,
    List<String>? writePaths,
    List<String>? doneCriteria,
    List<String>? outOfScope,
    List<String>? context,
    List<ProjectArtifact>? expectedArtifacts,
    ProjectTaskStatus? status,
    Object? taskDocumentId = kSentinel,
    Object? recoveryIncidentId = kSentinel,
    String? fingerprint,
    Object? rejectionReason = kSentinel,
    Object? failure = kSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextObjective = objective ?? this.objective;
    final nextCriteria =
        criterionIds ?? relevantSuccessCriteria ?? this.criterionIds;
    return ProjectTask(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: nextObjective,
      criterionIds: nextCriteria,
      milestoneId: resolve(milestoneId, this.milestoneId),
      dependsOnTaskIds: dependsOnTaskIds ?? this.dependsOnTaskIds,
      priority: priority ?? this.priority,
      risk: risk ?? this.risk,
      riskReduction: riskReduction ?? this.riskReduction,
      effort: effort ?? this.effort,
      readiness: readiness ?? this.readiness,
      readinessReasons: readinessReasons ?? this.readinessReasons,
      selectionRationale: selectionRationale ?? this.selectionRationale,
      revisionIntroduced: revisionIntroduced ?? this.revisionIntroduced,
      revisionUpdated: revisionUpdated ?? this.revisionUpdated,
      expectedEvidence: expectedEvidence ?? this.expectedEvidence,
      readPaths: readPaths ?? this.readPaths,
      writePaths: writePaths ?? this.writePaths,
      doneCriteria: doneCriteria ?? this.doneCriteria,
      outOfScope: outOfScope ?? this.outOfScope,
      context: context ?? this.context,
      expectedArtifacts: expectedArtifacts ?? this.expectedArtifacts,
      status: status ?? this.status,
      taskDocumentId: resolve(taskDocumentId, this.taskDocumentId),
      recoveryIncidentId: resolve(recoveryIncidentId, this.recoveryIncidentId),
      fingerprint:
          fingerprint ??
          this.fingerprint.ifEmpty(
            projectTaskFingerprint(nextObjective, nextCriteria),
          ),
      rejectionReason: resolve(rejectionReason, this.rejectionReason),
      failure: resolve(failure, this.failure),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ProjectTask.fromLegacyRef(ProjectTaskRef ref) {
    final objective = ref.summary.trim().isEmpty ? ref.title : ref.summary;
    final criteria = ref.summary.trim().isEmpty ? <String>[] : [ref.summary];
    return ProjectTask(
      id: 'project_task_${ref.taskId}',
      title: ref.title,
      objective: objective,
      relevantSuccessCriteria: criteria,
      doneCriteria: criteria.isEmpty ? ['Finish ${ref.title}.'] : criteria,
      outOfScope: const ['Do not expand this task into the full project.'],
      context: const [],
      expectedArtifacts: const [],
      status: switch (ref.status) {
        TaskStatus.completed => ProjectTaskStatus.completed,
        TaskStatus.failed || TaskStatus.cancelled => ProjectTaskStatus.failed,
        _ => ProjectTaskStatus.queued,
      },
      taskDocumentId: ref.taskId,
      recoveryIncidentId: null,
      fingerprint: projectTaskFingerprint(objective, criteria),
      rejectionReason: null,
      failure: null,
      createdAt: ref.createdAt,
      updatedAt: ref.updatedAt,
    );
  }
}

@MappableClass(ignoreNull: true)
class ProjectTaskFailure with ProjectTaskFailureMappable {
  @MappableField(hook: JsonNullableStringHook())
  final String? gateId;
  @MappableField(hook: EnumAliasHook({}))
  final TaskGateFailureDisposition disposition;
  @MappableField(hook: JsonStringHook())
  final String failureKey;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonStringListHook())
  final List<String> errorCodes;
  @MappableField(hook: JsonStringListHook())
  final List<String> toolCallIds;
  @MappableField(hook: JsonIntHook())
  final int advisoryErrorCount;
  @MappableField(hook: JsonIntHook())
  final int resolvedErrorCount;
  @MappableField(hook: JsonIntHook())
  final int unresolvedErrorCount;

  const ProjectTaskFailure({
    this.gateId,
    required this.disposition,
    required this.failureKey,
    required this.summary,
    this.errorCodes = const [],
    this.toolCallIds = const [],
    this.advisoryErrorCount = 0,
    this.resolvedErrorCount = 0,
    this.unresolvedErrorCount = 0,
  });
}

@MappableClass(ignoreNull: true, hook: ProjectArtifactJsonHook())
class ProjectArtifact with ProjectArtifactMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonNullableStringHook())
  final String? projectTaskId;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskDocumentId;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskRunId;
  @MappableField(hook: JsonStringHook())
  final String path;
  @MappableField(hook: JsonStringHook())
  final String description;
  @MappableField(hook: JsonStringHook(fallback: 'file'))
  final String kind;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;

  const ProjectArtifact({
    required this.id,
    required this.projectTaskId,
    required this.taskDocumentId,
    this.taskRunId,
    required this.path,
    required this.description,
    required this.kind,
    required this.createdAt,
  });

  ProjectArtifact copyWith({
    String? id,
    Object? projectTaskId = kSentinel,
    Object? taskDocumentId = kSentinel,
    Object? taskRunId = kSentinel,
    String? path,
    String? description,
    String? kind,
    DateTime? createdAt,
  }) {
    return ProjectArtifact(
      id: id ?? this.id,
      projectTaskId: resolve(projectTaskId, this.projectTaskId),
      taskDocumentId: resolve(taskDocumentId, this.taskDocumentId),
      taskRunId: resolve(taskRunId, this.taskRunId),
      path: path ?? this.path,
      description: description ?? this.description,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class TaskResult {
  final String taskDocumentId;
  @MappableField(hook: EnumAliasHook({}))
  final TaskStatus status;
  final String summary;
  final String memoryUpdate;
  final List<ProjectArtifact> artifacts;
  final List<TaskGateResult> gateResults;
  final List<TaskEvidenceClaim> evidenceClaims;
  final String? finalRunId;
  final int toolCallCount;
  final String? userQuestion;
  final String? error;
  final bool projectReplanRequested;

  const TaskResult({
    required this.taskDocumentId,
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
  final String projectTaskId;
  final bool taskAccepted;
  final bool projectComplete;
  final String summary;
  final List<String> completedCriteria;
  final List<String> remainingCriteria;
  final List<String> newKnownFacts;
  final List<ProjectArtifact> artifacts;
  final List<TaskGateResult> gateResults;
  final List<ProjectTask> backlogAdditions;
  final List<PendingProjectQuestion> openQuestions;
  final String? failureReason;
  final bool projectReplanRequested;

  const ProjectEvaluation({
    required this.projectTaskId,
    required this.taskAccepted,
    required this.projectComplete,
    required this.summary,
    required this.completedCriteria,
    required this.remainingCriteria,
    required this.newKnownFacts,
    required this.artifacts,
    this.gateResults = const [],
    required this.backlogAdditions,
    required this.openQuestions,
    this.failureReason,
    this.projectReplanRequested = false,
  });
}

@MappableClass(ignoreNull: true)
class ProjectTaskRef with ProjectTaskRefMappable {
  @MappableField(hook: JsonStringHook())
  final String taskId;
  @MappableField(hook: JsonStringHook(fallback: 'Untitled task'))
  final String title;
  final TaskStatus status;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? completedAt;

  const ProjectTaskRef({
    required this.taskId,
    required this.title,
    required this.status,
    required this.summary,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory ProjectTaskRef.fromProjectTask(ProjectTask task) {
    return ProjectTaskRef(
      taskId: task.taskDocumentId ?? task.id,
      title: task.title,
      status: switch (task.status) {
        ProjectTaskStatus.completed => TaskStatus.completed,
        ProjectTaskStatus.failed => TaskStatus.failed,
        ProjectTaskStatus.cancelled => TaskStatus.cancelled,
        ProjectTaskStatus.running => TaskStatus.running,
        ProjectTaskStatus.rejected ||
        ProjectTaskStatus.split => TaskStatus.blocked,
        _ => TaskStatus.paused,
      },
      summary: task.rejectionReason ?? task.objective,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      completedAt: task.status == ProjectTaskStatus.completed
          ? task.updatedAt
          : null,
    );
  }

  factory ProjectTaskRef.fromTask(TaskDocument task, {String summary = ''}) {
    return ProjectTaskRef(
      taskId: task.id,
      title: task.title,
      status: task.status,
      summary: summary,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      completedAt: task.completedAt,
    );
  }
}

@MappableClass(ignoreNull: true)
class ProjectDecisionRecord with ProjectDecisionRecordMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(
    hook: EnumAliasHook({
      'createtask': 'create_task',
      'createrecoverytask': 'create_recovery_task',
      'rejecttask': 'reject_task',
      'splittask': 'split_task',
      'evaluatetask': 'evaluate_task',
      'refreshbacklog': 'refresh_backlog',
      'retryrecovery': 'retry_recovery',
      'applyplanrevision': 'apply_plan_revision',
      'approveplanrevision': 'approve_plan_revision',
      'rejectplanrevision': 'reject_plan_revision',
    }),
  )
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
  @MappableField(
    hook: EnumAliasHook({
      'taskapproval': 'task_approval',
      'taskblocked': 'task_blocked',
      'taskfailed': 'task_failed',
      'recoveryfailed': 'recovery_failed',
      'duplicatetask': 'duplicate_task',
      'oversizedtask': 'oversized_task',
      'maxfailures': 'max_failures',
      'planapproval': 'plan_approval',
    }),
  )
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

extension on TaskStatus {
  bool get isTerminal =>
      this == TaskStatus.completed ||
      this == TaskStatus.cancelled ||
      this == TaskStatus.failed;
}
