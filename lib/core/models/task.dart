import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/serialization/json_hooks.dart';

part 'task.mapper.dart';

enum ExecutionMode { chat, refine, task, project, continueTask }

@MappableEnum(defaultValue: TaskStatus.paused)
enum TaskStatus {
  draft,
  planned,
  running,
  paused,
  blocked,
  completed,
  failed,
  cancelled,
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

TaskStatus parseTaskStatus(Object? value) =>
    _parseEnum(TaskStatus.values, value, TaskStatus.paused);

T _parseEnum<T extends Enum>(
  List<T> values,
  Object? value,
  T fallback, {
  Map<String, T> aliases = const {},
}) {
  final raw = value?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty) return fallback;
  final normalised = raw.replaceAll('-', '_');
  final alias = aliases[normalised];
  if (alias != null) return alias;
  for (final item in values) {
    if (item.name.toLowerCase() == normalised) return item;
  }
  return fallback;
}

@MappableClass(
  hook: JsonModelHook(
    aliases: {
      'goal': ['objective'],
      'successCriteria': ['success_criteria'],
      'questions': ['clarifyingQuestions'],
    },
  ),
)
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

@MappableClass(
  ignoreNull: true,
  hook: JsonModelHook(
    aliases: {
      'goal': ['objective'],
    },
    omitEmpty: {'gates'},
  ),
)
class TaskDocument with TaskDocumentMappable {
  static const int currentSchemaVersion = 2;

  @MappableField(hook: JsonIntHook())
  final int schemaVersion;
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonStringHook(fallback: 'Untitled task'))
  final String title;
  @MappableField(hook: JsonStringHook())
  final String originalPrompt;
  @MappableField(hook: JsonStringHook())
  final String goal;
  @MappableField(hook: JsonStringListHook())
  final List<String> constraints;
  @MappableField(hook: JsonStringListHook())
  final List<String> successCriteria;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskGate> gates;
  @MappableField(hook: JsonObjectListHook())
  final List<TaskStep> steps;
  @MappableField(hook: EnumAliasHook({}))
  final TaskStatus status;
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
  @MappableField(hook: JsonDateHook())
  final DateTime createdAt;
  @MappableField(hook: JsonDateHook())
  final DateTime updatedAt;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? completedAt;

  const TaskDocument({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.title,
    required this.originalPrompt,
    required this.goal,
    required this.constraints,
    required this.successCriteria,
    this.gates = const [],
    required this.steps,
    required this.status,
    required this.currentStepId,
    required this.memorySummary,
    required this.runs,
    required this.createdAt,
    required this.updatedAt,
    this.pendingApproval,
    this.pendingQuestion,
    this.chatSessionId,
    this.projectId,
    this.completedAt,
  });

  TaskDocument copyWith({
    int? schemaVersion,
    String? id,
    String? title,
    String? originalPrompt,
    String? goal,
    List<String>? constraints,
    List<String>? successCriteria,
    List<TaskGate>? gates,
    List<TaskStep>? steps,
    TaskStatus? status,
    Object? currentStepId = kSentinel,
    String? memorySummary,
    List<TaskRun>? runs,
    Object? pendingApproval = kSentinel,
    Object? pendingQuestion = kSentinel,
    Object? chatSessionId = kSentinel,
    Object? projectId = kSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return TaskDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      title: title ?? this.title,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      goal: goal ?? this.goal,
      constraints: constraints ?? this.constraints,
      successCriteria: successCriteria ?? this.successCriteria,
      gates: gates ?? this.gates,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      currentStepId: resolve(currentStepId, this.currentStepId),
      memorySummary: memorySummary ?? this.memorySummary,
      runs: runs ?? this.runs,
      pendingApproval: resolve(pendingApproval, this.pendingApproval),
      pendingQuestion: resolve(pendingQuestion, this.pendingQuestion),
      chatSessionId: resolve(chatSessionId, this.chatSessionId),
      projectId: resolve(projectId, this.projectId),
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
      status == TaskStatus.cancelled ||
      status == TaskStatus.failed;

  TaskStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }
}

typedef TaskSnapshot = TaskDocument;

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
  @MappableField(hook: EnumAliasHook({}))
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
  @MappableField(hook: EnumAliasHook({}))
  final TaskGateStatus status;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> details;
  @MappableField(hook: JsonDateHook())
  final DateTime evaluatedAt;

  const TaskGateResult({
    required this.gateId,
    required this.status,
    required this.summary,
    this.details = const {},
    required this.evaluatedAt,
  });
}

@MappableClass(ignoreNull: true)
class TaskArtifact with TaskArtifactMappable {
  @MappableField(hook: JsonStringHook())
  final String path;
  @MappableField(hook: JsonNullableStringHook())
  final String? description;
  @MappableField(hook: JsonNullableStringHook())
  final String? stepId;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? createdAt;

  const TaskArtifact({
    required this.path,
    this.description,
    this.stepId,
    this.createdAt,
  });
}

@MappableClass(
  ignoreNull: true,
  hook: JsonModelHook(omitEmpty: {'gateResults'}),
)
class TaskRun with TaskRunMappable {
  @MappableField(hook: JsonStringHook())
  final String runId;
  @MappableField(hook: JsonStringHook())
  final String stepId;
  @MappableField(hook: EnumAliasHook({'needsreplan': 'needs_replan'}))
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
  @MappableField(hook: JsonNullableStringHook())
  final String? error;
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
    this.error,
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
