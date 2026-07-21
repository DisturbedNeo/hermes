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
  cancelled,
}

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
    _ => name,
  };
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
  static const int currentSchemaVersion = 2;
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
  @MappableField(hook: JsonStringListHook())
  final List<String> successCriteria;
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
  @MappableField(hook: JsonStringListHook())
  final List<String> knownFacts;
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
    required this.successCriteria,
    required this.constraints,
    List<ProjectTask>? backlog,
    ProjectTask? currentTask,
    List<ProjectTask>? completedTasks,
    List<ProjectTask>? failedTasks,
    List<ProjectArtifact>? artifacts,
    List<ProjectRecoveryIncident>? recoveryIncidents,
    List<String>? knownFacts,
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
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  }) : originalGoal = originalGoal ?? originalPrompt ?? '',
       refinedGoal =
           refinedGoal ?? goal ?? originalGoal ?? originalPrompt ?? '',
       backlog = backlog ?? _legacyBacklog(tasks, activeTaskId),
       currentTask = currentTask ?? _legacyCurrentTask(tasks, activeTaskId),
       completedTasks = completedTasks ?? _legacyCompletedTasks(tasks),
       failedTasks = failedTasks ?? _legacyFailedTasks(tasks),
       artifacts = artifacts ?? const [],
       recoveryIncidents = recoveryIncidents ?? const [],
       knownFacts =
           knownFacts ??
           [
             if (memorySummary?.trim().isNotEmpty == true)
               memorySummary!.trim(),
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

  String get memorySummary => knownFacts.join('\n\n');

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

  ProjectState copyWith({
    int? schemaVersion,
    String? id,
    String? title,
    String? originalGoal,
    String? refinedGoal,
    List<String>? successCriteria,
    List<String>? constraints,
    List<ProjectTask>? backlog,
    Object? currentTask = kSentinel,
    List<ProjectTask>? completedTasks,
    List<ProjectTask>? failedTasks,
    List<ProjectArtifact>? artifacts,
    List<ProjectRecoveryIncident>? recoveryIncidents,
    List<String>? knownFacts,
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
      successCriteria: successCriteria ?? this.successCriteria,
      constraints: constraints ?? this.constraints,
      backlog: backlog ?? this.backlog,
      currentTask: resolve(currentTask, this.currentTask),
      completedTasks: completedTasks ?? this.completedTasks,
      failedTasks: failedTasks ?? this.failedTasks,
      artifacts: artifacts ?? this.artifacts,
      recoveryIncidents: recoveryIncidents ?? this.recoveryIncidents,
      knownFacts: knownFacts ?? this.knownFacts,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
    );
  }
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
  final List<String> relevantSuccessCriteria;
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
    required this.relevantSuccessCriteria,
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
  });

  ProjectTask copyWith({
    String? id,
    String? title,
    String? objective,
    List<String>? relevantSuccessCriteria,
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
        relevantSuccessCriteria ?? this.relevantSuccessCriteria;
    return ProjectTask(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: nextObjective,
      relevantSuccessCriteria: nextCriteria,
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
    required this.path,
    required this.description,
    required this.kind,
    required this.createdAt,
  });

  ProjectArtifact copyWith({
    String? id,
    Object? projectTaskId = kSentinel,
    Object? taskDocumentId = kSentinel,
    String? path,
    String? description,
    String? kind,
    DateTime? createdAt,
  }) {
    return ProjectArtifact(
      id: id ?? this.id,
      projectTaskId: resolve(projectTaskId, this.projectTaskId),
      taskDocumentId: resolve(taskDocumentId, this.taskDocumentId),
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
  final int toolCallCount;
  final String? userQuestion;
  final String? error;

  const TaskResult({
    required this.taskDocumentId,
    required this.status,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
    this.gateResults = const [],
    required this.toolCallCount,
    this.userQuestion,
    this.error,
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
