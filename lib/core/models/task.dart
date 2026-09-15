import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'task.mapper.dart';

enum ExecutionMode { chat, refine, task, project, continueTask }

@MappableEnum(defaultValue: TaskStatus.paused)
enum TaskStatus {
  draft,
  queued,
  planned,
  running,
  paused,
  blocked,
  completed,
  failed,
  rejected,
  split,
  deferred,
  obsolete,
  cancelled,
}

@MappableEnum(defaultValue: TaskPriority.normal)
enum TaskPriority { critical, high, normal, low }

@MappableEnum(defaultValue: TaskRisk.unknown)
enum TaskRisk { high, medium, low, unknown }

@MappableEnum(defaultValue: ProjectRiskReduction.none)
enum ProjectRiskReduction { high, medium, low, none }

@MappableEnum(defaultValue: TaskEffort.small)
enum TaskEffort { small, medium, large }

@MappableEnum(defaultValue: ProjectEvidenceType.taskClaim)
enum ProjectEvidenceType {
  gate,
  artifact,
  command,
  @MappableValue('task_claim')
  taskClaim,
  @MappableValue('user_approval')
  userApproval,
}

@MappableEnum(defaultValue: TaskStepStatus.pending)
enum TaskStepStatus {
  pending,
  approved,
  running,
  completed,
  blocked,
  failed,
  skipped,
}

@MappableEnum(defaultValue: TaskRunStatus.completed)
enum TaskRunStatus {
  running,
  completed,
  blocked,
  failed,
  cancelled,
  skipped,
  @MappableValue('needs_replan')
  needsReplan,
  replanned,
}

@MappableEnum(defaultValue: TaskGateStatus.pending)
enum TaskGateStatus { passed, failed, pending, advisory }

@MappableEnum(defaultValue: TaskToolCallOutcome.succeeded)
enum TaskToolCallOutcome { succeeded, denied, failed, skipped }

@MappableEnum(defaultValue: TaskToolErrorDisposition.fatal)
enum TaskToolErrorDisposition { advisory, retryable, fatal }

@MappableEnum(defaultValue: TaskGateFailureDisposition.repairable)
enum TaskGateFailureDisposition { repairable, blocking }

@MappableEnum(defaultValue: TaskEvidenceClaimType.taskClaim)
enum TaskEvidenceClaimType {
  gate,
  artifact,
  command,
  @MappableValue('task_claim')
  taskClaim,
  @MappableValue('user_approval')
  userApproval,
}

@MappableEnum(defaultValue: TaskEvidenceClaimStrength.advisory)
enum TaskEvidenceClaimStrength { advisory, supporting, conclusive }

/// Project outcome context supplied transiently while a bounded task runs.
@MappableClass(ignoreNull: true)
class TaskProjectCriterion with TaskProjectCriterionMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook())
  final String statement;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool required;
  @MappableField(hook: JsonStringHook(fallback: 'mixed'))
  final String verificationMode;

  const TaskProjectCriterion({
    required this.id,
    required this.statement,
    this.required = true,
    this.verificationMode = 'mixed',
  });
}

/// Evidence contract owned by the canonical task model.
@MappableClass(ignoreNull: true)
class TaskEvidenceExpectation with TaskEvidenceExpectationMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  final ProjectEvidenceType type;
  @MappableField(hook: JsonStringListHook())
  final List<String> criterionIds;
  @MappableField(hook: JsonStringHook())
  final String description;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool required;
  @MappableField(hook: JsonNullableStringHook())
  final String? sourceRef;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> details;

  const TaskEvidenceExpectation({
    required this.id,
    this.type = ProjectEvidenceType.taskClaim,
    this.criterionIds = const [],
    required this.description,
    this.required = true,
    this.sourceRef,
    this.details = const {},
  });
}

/// Task-planning DTO used by the task planner prompt. The canonical task
/// record uses [TaskEvidenceExpectation] and its typed evidence enum.
@MappableClass(ignoreNull: true)
class TaskProjectEvidenceExpectation
    with TaskProjectEvidenceExpectationMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook(fallback: 'task_claim'))
  final String type;
  @MappableField(hook: JsonStringListHook())
  final List<String> criterionIds;
  @MappableField(hook: JsonStringHook())
  final String description;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool required;
  @MappableField(hook: JsonNullableStringHook())
  final String? sourceRef;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> details;

  const TaskProjectEvidenceExpectation({
    required this.id,
    this.type = 'task_claim',
    this.criterionIds = const [],
    required this.description,
    this.required = true,
    this.sourceRef,
    this.details = const {},
  });
}

extension ExecutionModeWire on ExecutionMode {
  String get wire => switch (this) {
    ExecutionMode.continueTask => 'continue_task',
    _ => name,
  };

  String get label => switch (this) {
    ExecutionMode.chat => 'Chat',
    ExecutionMode.refine => 'Refine',
    ExecutionMode.task => 'Task',
    ExecutionMode.project => 'Project',
    ExecutionMode.continueTask => 'Continue Task',
  };
}

extension TaskStatusWire on TaskStatus {
  String get wire => name;
}

extension TaskStepStatusWire on TaskStepStatus {
  String get wire => name;
}

extension TaskRunStatusWire on TaskRunStatus {
  String get wire => switch (this) {
    TaskRunStatus.needsReplan => 'needs_replan',
    _ => name,
  };
}

extension TaskGateStatusWire on TaskGateStatus {
  String get wire => name;
}

extension TaskToolCallOutcomeWire on TaskToolCallOutcome {
  String get wire => name;
}

extension TaskToolErrorDispositionWire on TaskToolErrorDisposition {
  String get wire => name;
}

extension TaskGateFailureDispositionWire on TaskGateFailureDisposition {
  String get wire => name;
}

@MappableClass(hook: JsonModelHook())
class RefinedTaskBrief with RefinedTaskBriefMappable {
  @MappableField(hook: JsonStringHook(fallback: 'Untitled task'))
  final String title;
  @MappableField(hook: JsonStringHook())
  final String goal;
  @MappableField(hook: JsonStringListHook())
  final List<String> constraints;
  @MappableField(hook: JsonStringListHook())
  final List<String> successCriteria;
  @MappableField(hook: JsonStringListHook())
  final List<String> assumptions;
  @MappableField(hook: JsonStringListHook())
  final List<String> questions;

  const RefinedTaskBrief({
    required this.title,
    required this.goal,
    this.constraints = const [],
    this.successCriteria = const [],
    this.assumptions = const [],
    this.questions = const [],
  });
}

@MappableClass(ignoreNull: true, hook: TaskJsonHook())
class Task with TaskMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook(fallback: 'Untitled task'))
  final String title;
  @MappableField(hook: JsonStringHook())
  final String originalPrompt;
  @MappableField(hook: JsonStringHook())
  final String objective;
  @MappableField(hook: JsonStringListHook())
  final List<String> constraints;
  @MappableField(hook: JsonStringListHook())
  final List<String> successCriteria;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskGate> gates;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskStep> steps;
  final TaskStatus status;
  @MappableField(hook: JsonStringListHook())
  final List<String> criterionIds;
  @MappableField(hook: JsonNullableStringHook())
  final String? milestoneId;
  @MappableField(hook: JsonStringListHook())
  final List<String> dependsOnTaskIds;
  final TaskPriority priority;
  final TaskRisk risk;
  final ProjectRiskReduction riskReduction;
  final TaskEffort effort;
  @MappableField(hook: JsonStringHook())
  final String selectionRationale;
  @MappableField(hook: JsonIntHook(fallback: 1, min: 1))
  final int revisionIntroduced;
  @MappableField(hook: JsonIntHook(fallback: 1, min: 1))
  final int revisionUpdated;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskEvidenceExpectation> expectedEvidence;
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
  final List<TaskArtifact> expectedArtifacts;
  @MappableField(hook: JsonNullableStringHook())
  final String? recoveryIncidentId;
  @MappableField(hook: JsonStringHook())
  final String fingerprint;
  @MappableField(hook: JsonNullableStringHook())
  final String? rejectionReason;
  final TaskFailure? failure;
  @MappableField(hook: JsonNullableStringHook())
  final String? currentStepId;
  @MappableField(hook: JsonStringHook())
  final String memorySummary;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskRun> runs;
  final PendingTaskApproval? pendingApproval;
  final PendingTaskQuestion? pendingQuestion;
  @MappableField(hook: JsonNullableStringHook())
  final String? chatSessionId;
  @MappableField(hook: JsonNullableStringHook())
  final String? projectId;
  @MappableField(hook: OmitEmptyPlanningMetricsHook())
  final PlanningMetrics planningMetrics;

  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? completedAt;

  const Task({
    required this.id,
    required this.title,
    String? originalPrompt,
    String? objective,
    this.constraints = const [],
    this.successCriteria = const [],
    this.gates = const [],
    this.steps = const [],
    this.status = TaskStatus.paused,
    this.criterionIds = const [],
    this.milestoneId,
    this.dependsOnTaskIds = const [],
    this.priority = TaskPriority.normal,
    this.risk = TaskRisk.unknown,
    this.riskReduction = ProjectRiskReduction.none,
    this.effort = TaskEffort.small,
    this.selectionRationale = '',
    this.revisionIntroduced = 1,
    this.revisionUpdated = 1,
    this.expectedEvidence = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.context = const [],
    this.expectedArtifacts = const [],
    this.recoveryIncidentId,
    this.fingerprint = '',
    this.rejectionReason,
    this.failure,
    this.currentStepId,
    this.memorySummary = '',
    this.runs = const [],
    required this.createdAt,
    required this.updatedAt,
    this.pendingApproval,
    this.pendingQuestion,
    this.chatSessionId,
    this.projectId,
    this.planningMetrics = const PlanningMetrics(),
    this.completedAt,
  }) : originalPrompt = originalPrompt ?? objective ?? '',
       objective = objective ?? originalPrompt ?? '';

  Task copyWith({
    String? id,
    String? title,
    String? originalPrompt,
    String? objective,
    List<String>? constraints,
    List<String>? successCriteria,
    List<TaskGate>? gates,
    List<TaskStep>? steps,
    TaskStatus? status,
    List<String>? criterionIds,
    Object? milestoneId = kSentinel,
    List<String>? dependsOnTaskIds,
    TaskPriority? priority,
    TaskRisk? risk,
    ProjectRiskReduction? riskReduction,
    TaskEffort? effort,
    String? selectionRationale,
    int? revisionIntroduced,
    int? revisionUpdated,
    List<TaskEvidenceExpectation>? expectedEvidence,
    List<String>? readPaths,
    List<String>? writePaths,
    List<String>? doneCriteria,
    List<String>? outOfScope,
    List<String>? context,
    List<TaskArtifact>? expectedArtifacts,
    Object? recoveryIncidentId = kSentinel,
    String? fingerprint,
    Object? rejectionReason = kSentinel,
    Object? failure = kSentinel,
    Object? currentStepId = kSentinel,
    String? memorySummary,
    List<TaskRun>? runs,
    Object? pendingApproval = kSentinel,
    Object? pendingQuestion = kSentinel,
    Object? chatSessionId = kSentinel,
    Object? projectId = kSentinel,
    PlanningMetrics? planningMetrics,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      objective: objective ?? this.objective,
      constraints: constraints ?? this.constraints,
      successCriteria: successCriteria ?? this.successCriteria,
      gates: gates ?? this.gates,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      criterionIds: criterionIds ?? this.criterionIds,
      milestoneId: resolve(milestoneId, this.milestoneId),
      dependsOnTaskIds: dependsOnTaskIds ?? this.dependsOnTaskIds,
      priority: priority ?? this.priority,
      risk: risk ?? this.risk,
      riskReduction: riskReduction ?? this.riskReduction,
      effort: effort ?? this.effort,
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
      recoveryIncidentId: resolve(recoveryIncidentId, this.recoveryIncidentId),
      fingerprint: fingerprint ?? this.fingerprint,
      rejectionReason: resolve(rejectionReason, this.rejectionReason),
      failure: resolve(failure, this.failure),
      currentStepId: resolve(currentStepId, this.currentStepId),
      memorySummary: memorySummary ?? this.memorySummary,
      runs: runs ?? this.runs,
      pendingApproval: resolve(pendingApproval, this.pendingApproval),
      pendingQuestion: resolve(pendingQuestion, this.pendingQuestion),
      chatSessionId: resolve(chatSessionId, this.chatSessionId),
      projectId: resolve(projectId, this.projectId),
      planningMetrics: planningMetrics ?? this.planningMetrics,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
    );
  }

  TaskStep? get currentStep =>
      currentStepId == null ? null : stepById(currentStepId!);

  TaskStep? get nextRunnableStep => steps
      .where(
        (step) =>
            step.status == TaskStepStatus.pending ||
            step.status == TaskStepStatus.approved ||
            step.status == TaskStepStatus.blocked ||
            step.status == TaskStepStatus.failed,
      )
      .firstOrNull;

  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.rejected ||
      status == TaskStatus.split ||
      status == TaskStatus.cancelled ||
      status == TaskStatus.failed;

  TaskStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }
}

class TaskJsonHook extends JsonModelHook {
  const TaskJsonHook() : super(omitEmpty: const {'gates'});
}

@MappableClass(ignoreNull: true, hook: JsonModelHook(omitEmpty: {'gates'}))
class TaskStep with TaskStepMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook(fallback: 'Untitled step'))
  final String title;
  @MappableField(hook: JsonStringHook())
  final String objective;
  @MappableField(hook: JsonStringListHook())
  final List<String> instructions;
  @MappableField(hook: JsonBoolHook())
  final bool mayEditFiles;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskArtifact> artifacts;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskGate> gates;
  final TaskStepStatus status;

  const TaskStep({
    required this.id,
    required this.title,
    required this.objective,
    required this.instructions,
    required this.mayEditFiles,
    required this.artifacts,
    this.gates = const [],
    required this.status,
  });

  TaskStep copyWith({
    String? id,
    String? title,
    String? objective,
    List<String>? instructions,
    bool? mayEditFiles,
    List<TaskArtifact>? artifacts,
    List<TaskGate>? gates,
    TaskStepStatus? status,
  }) {
    return TaskStep(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      instructions: instructions ?? this.instructions,
      mayEditFiles: mayEditFiles ?? this.mayEditFiles,
      artifacts: artifacts ?? this.artifacts,
      gates: gates ?? this.gates,
      status: status ?? this.status,
    );
  }
}

@MappableClass(ignoreNull: true, hook: JsonModelHook(omitEmpty: {'params'}))
class TaskGate with TaskGateMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool required;
  @MappableField(hook: JsonStringHook(fallback: 'step'))
  final String scope;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> params;
  @MappableField(hook: JsonNullableStringHook())
  final String? description;

  const TaskGate({
    required this.id,
    this.required = true,
    this.scope = 'step',
    this.params = const {},
    this.description,
  });
}

@MappableClass(ignoreNull: true, hook: JsonModelHook(omitEmpty: {'details'}))
class TaskGateResult with TaskGateResultMappable {
  @MappableField(hook: JsonStringHook())
  final String gateId;
  final TaskGateStatus status;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> details;
  final TaskGateFailureDisposition? failureDisposition;
  @MappableField(hook: JsonDateHook())
  final DateTime evaluatedAt;

  const TaskGateResult({
    required this.gateId,
    required this.status,
    required this.summary,
    this.details = const {},
    this.failureDisposition,
    required this.evaluatedAt,
  });
}

@MappableClass(ignoreNull: true)
class TaskFailure with TaskFailureMappable {
  @MappableField(hook: JsonNullableStringHook())
  final String? gateId;
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

  const TaskFailure({
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

@MappableClass(ignoreNull: true, hook: TaskArtifactJsonHook())
class TaskArtifact with TaskArtifactMappable {
  @MappableField(hook: JsonStringHook())
  final String path;
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonNullableStringHook())
  final String? description;
  @MappableField(hook: JsonNullableStringHook())
  final String? stepId;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskId;
  @MappableField(hook: JsonNullableStringHook())
  final String? runId;
  @MappableField(hook: JsonNullableStringHook())
  @MappableField(hook: JsonStringHook(fallback: 'file'))
  final String kind;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? createdAt;

  const TaskArtifact({
    required this.path,
    this.id = '',
    this.description,
    this.stepId,
    this.taskId,
    this.runId,
    this.kind = 'file',
    this.createdAt,
  });

  TaskArtifact copyWith({
    String? path,
    String? id,
    Object? description = kSentinel,
    Object? stepId = kSentinel,
    Object? taskId = kSentinel,
    Object? runId = kSentinel,
    String? kind,
    Object? createdAt = kSentinel,
  }) {
    return TaskArtifact(
      path: path ?? this.path,
      id: id ?? this.id,
      description: resolve(description, this.description),
      stepId: resolve(stepId, this.stepId),
      taskId: resolve(taskId, this.taskId),
      runId: resolve(runId, this.runId),
      kind: kind ?? this.kind,
      createdAt: resolve(createdAt, this.createdAt),
    );
  }
}

class TaskArtifactJsonHook extends JsonModelHook {
  const TaskArtifactJsonHook();

  @override
  Object? afterEncode(Object? value) {
    if (value is! Map) return value;
    final encoded = Map<String, dynamic>.from(value);
    if (encoded['id'] == '') encoded.remove('id');
    if (encoded['kind'] == 'file') encoded.remove('kind');
    return encoded;
  }
}

@MappableClass(ignoreNull: true)
class TaskEvidenceClaim with TaskEvidenceClaimMappable {
  @MappableField(hook: JsonStringHook())
  final String criterionId;
  @MappableField(hook: JsonStringHook())
  final String claim;
  final TaskEvidenceClaimType evidenceType;
  @MappableField(hook: JsonStringHook())
  final String sourceRef;
  final TaskEvidenceClaimStrength suggestedStrength;
  @MappableField(hook: JsonNullableStringHook())
  final String? expectationId;
  @MappableField(hook: JsonNullableStringHook())
  final String? runId;

  const TaskEvidenceClaim({
    required this.criterionId,
    required this.claim,
    this.evidenceType = TaskEvidenceClaimType.taskClaim,
    required this.sourceRef,
    this.suggestedStrength = TaskEvidenceClaimStrength.advisory,
    this.expectationId,
    this.runId,
  });
}

@MappableClass(
  ignoreNull: true,
  hook: JsonModelHook(omitEmpty: {'gateResults', 'evidenceClaims'}),
)
class TaskRun with TaskRunMappable {
  @MappableField(hook: JsonStringHook())
  final String runId;
  @MappableField(hook: JsonStringHook())
  final String stepId;
  final TaskRunStatus status;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonStringHook())
  final String memoryUpdate;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskToolCallRecord> toolCalls;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskArtifact> artifacts;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskGateResult> gateResults;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskEvidenceClaim> evidenceClaims;
  @MappableField(hook: JsonDateHook())
  final DateTime startedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? completedAt;
  @MappableField(hook: JsonNullableStringHook())
  final String? replanReason;
  @MappableField(hook: JsonNullableStringHook())
  final String? error;

  const TaskRun({
    required this.runId,
    required this.stepId,
    required this.status,
    required this.summary,
    required this.memoryUpdate,
    required this.toolCalls,
    required this.artifacts,
    this.gateResults = const [],
    this.evidenceClaims = const [],
    required this.startedAt,
    this.completedAt,
    this.replanReason,
    this.error,
  });

  TaskRun copyWith({
    String? runId,
    String? stepId,
    TaskRunStatus? status,
    String? summary,
    String? memoryUpdate,
    List<TaskToolCallRecord>? toolCalls,
    List<TaskArtifact>? artifacts,
    List<TaskGateResult>? gateResults,
    List<TaskEvidenceClaim>? evidenceClaims,
    DateTime? startedAt,
    Object? completedAt = kSentinel,
    Object? replanReason = kSentinel,
    Object? error = kSentinel,
  }) {
    return TaskRun(
      runId: runId ?? this.runId,
      stepId: stepId ?? this.stepId,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      memoryUpdate: memoryUpdate ?? this.memoryUpdate,
      toolCalls: toolCalls ?? this.toolCalls,
      artifacts: artifacts ?? this.artifacts,
      gateResults: gateResults ?? this.gateResults,
      evidenceClaims: evidenceClaims ?? this.evidenceClaims,
      startedAt: startedAt ?? this.startedAt,
      completedAt: resolve(completedAt, this.completedAt),
      replanReason: resolve(replanReason, this.replanReason),
      error: resolve(error, this.error),
    );
  }
}

@MappableClass(ignoreNull: true)
class TaskToolError with TaskToolErrorMappable {
  @MappableField(hook: JsonStringHook(fallback: 'unknown_tool_error'))
  final String code;
  @MappableField(hook: JsonStringHook())
  final String message;
  final TaskToolErrorDisposition disposition;

  const TaskToolError({
    required this.code,
    required this.message,
    required this.disposition,
  });
}

@MappableClass(ignoreNull: true)
class TaskToolCallRecord with TaskToolCallRecordMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook())
  final String stepId;
  @MappableField(hook: JsonStringHook())
  final String runId;
  @MappableField(hook: JsonStringHook())
  final String toolName;
  final Object? arguments;
  final Object? result;
  @MappableField(hook: JsonNullableStringHook())
  final String? resultSummary;
  final TaskToolCallOutcome outcome;
  @MappableField(hook: JsonNullableStringHook())
  final String? operationKey;
  final TaskToolError? toolError;
  @MappableField(hook: JsonDateHook())
  final DateTime timestamp;

  const TaskToolCallRecord({
    required this.id,
    required this.stepId,
    required this.runId,
    required this.toolName,
    required this.timestamp,
    this.arguments,
    this.result,
    this.resultSummary,
    this.outcome = TaskToolCallOutcome.succeeded,
    this.operationKey,
    this.toolError,
  });
}

@MappableClass(ignoreNull: true)
class PendingTaskApproval with PendingTaskApprovalMappable {
  @MappableField(hook: JsonStringHook())
  final String stepId;
  @MappableField(hook: JsonStringHook())
  final String reason;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;

  const PendingTaskApproval({
    required this.stepId,
    required this.reason,
    required this.createdAt,
  });
}

@MappableClass(ignoreNull: true)
class PendingTaskQuestion with PendingTaskQuestionMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook())
  final String stepId;
  @MappableField(hook: JsonStringHook())
  final String question;
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;

  const PendingTaskQuestion({
    required this.id,
    required this.stepId,
    required this.question,
    required this.createdAt,
  });
}
