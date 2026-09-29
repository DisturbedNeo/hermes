import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/shared_kernel/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/shared_kernel/planning_metrics.dart';
import 'package:hermes/shared_kernel/json_hooks.dart';
import 'package:hermes/shared_kernel/task_planning_types.dart';
import 'package:hermes/shared_kernel/task_execution_contracts.dart';

export 'package:hermes/shared_kernel/task_planning_types.dart';
export 'package:hermes/shared_kernel/task_execution_contracts.dart';
export 'package:hermes/shared_kernel/task_tool_contracts.dart';

part 'task.mapper.dart';

enum ExecutionMode { chat, refine, task, project, continueTask }

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

@MappableEnum(defaultValue: TaskToolCallOutcome.succeeded)
enum TaskToolCallOutcome { succeeded, denied, failed, skipped }

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

/// TaskAggregate-planning DTO used by the task planner prompt. The canonical task
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
    ExecutionMode.task => 'TaskAggregate',
    ExecutionMode.project => 'Project',
    ExecutionMode.continueTask => 'Continue TaskAggregate',
  };
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

extension TaskToolCallOutcomeWire on TaskToolCallOutcome {
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
class TaskAggregate with TaskAggregateMappable {
  /// Revision of the canonical task snapshot. This is runtime metadata and
  /// is omitted from the document nested in the persistence envelope.
  @MappableField(hook: JsonIntHook(min: 0))
  final int persistenceRevision;
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
  final PlanningMetrics planningMetrics;

  /// Non-null when a safe fallback was used because task planning did not
  /// produce a committed executable plan.
  @MappableField(hook: JsonNullableStringHook())
  final String? planningError;

  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? completedAt;

  const TaskAggregate({
    this.persistenceRevision = 0,
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
    this.planningError,
    this.completedAt,
  }) : originalPrompt = originalPrompt ?? objective ?? '',
       objective = objective ?? originalPrompt ?? '';

  TaskAggregate copyWith({
    int? persistenceRevision,
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
    Object? planningError = kSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return TaskAggregate(
      persistenceRevision: persistenceRevision ?? this.persistenceRevision,
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
      planningError: resolve(planningError, this.planningError),
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
  const TaskJsonHook()
    : super(
        omitEmpty: const {'gates'},
        removeKeys: const {'persistenceRevision'},
      );
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

typedef Task = TaskAggregate;
