import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/models/task.dart';

enum ProjectStatus {
  initializing,
  active,
  paused,
  runningTask,
  reviewingTask,
  waitingForUser,
  blocked,
  completed,
  failed,
  cancelled,
}

enum ProjectPhase { discovery, planning, execution, verification, finalization }

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

enum ProjectBlockerType {
  question,
  taskApproval,
  taskBlocked,
  taskFailed,
  budget,
  validation,
  duplicateTask,
  oversizedTask,
  maxFailures,
  error,
}

enum ProjectDecisionType {
  createTask,
  complete,
  blocked,
  rejectTask,
  splitTask,
  evaluateTask,
  refreshBacklog,
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
    ProjectBlockerType.duplicateTask => 'duplicate_task',
    ProjectBlockerType.oversizedTask => 'oversized_task',
    ProjectBlockerType.maxFailures => 'max_failures',
    _ => name,
  };
}

extension ProjectDecisionTypeWire on ProjectDecisionType {
  String get wire => switch (this) {
    ProjectDecisionType.createTask => 'create_task',
    ProjectDecisionType.rejectTask => 'reject_task',
    ProjectDecisionType.splitTask => 'split_task',
    ProjectDecisionType.evaluateTask => 'evaluate_task',
    ProjectDecisionType.refreshBacklog => 'refresh_backlog',
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

ProjectPhase parseProjectPhase(Object? value) =>
    _parseEnum(ProjectPhase.values, value, ProjectPhase.discovery);

ProjectTaskStatus parseProjectTaskStatus(Object? value) =>
    _parseEnum(ProjectTaskStatus.values, value, ProjectTaskStatus.queued);

ProjectBlockerType parseProjectBlockerType(Object? value) => _parseEnum(
  ProjectBlockerType.values,
  value,
  ProjectBlockerType.error,
  aliases: {
    'task_approval': ProjectBlockerType.taskApproval,
    'task_blocked': ProjectBlockerType.taskBlocked,
    'task_failed': ProjectBlockerType.taskFailed,
    'duplicate_task': ProjectBlockerType.duplicateTask,
    'oversized_task': ProjectBlockerType.oversizedTask,
    'max_failures': ProjectBlockerType.maxFailures,
  },
);

ProjectDecisionType parseProjectDecisionType(Object? value) => _parseEnum(
  ProjectDecisionType.values,
  value,
  ProjectDecisionType.blocked,
  aliases: {
    'create_task': ProjectDecisionType.createTask,
    'reject_task': ProjectDecisionType.rejectTask,
    'split_task': ProjectDecisionType.splitTask,
    'evaluate_task': ProjectDecisionType.evaluateTask,
    'refresh_backlog': ProjectDecisionType.refreshBacklog,
  },
);

int parseOptionalLimit(Object? value, {required int fallback}) {
  final parsed = jsonInt(value, fallback: fallback);
  return parsed < 0 ? 0 : parsed;
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

class ProjectState {
  static const int currentSchemaVersion = 2;
  static const int defaultMaxIterations = 25;
  static const int defaultMaxFailedTasks = 3;

  final int schemaVersion;
  final String id;
  final String title;
  final String originalGoal;
  final String refinedGoal;
  final List<String> successCriteria;
  final List<String> constraints;
  final List<ProjectTask> backlog;
  final ProjectTask? currentTask;
  final List<ProjectTask> completedTasks;
  final List<ProjectTask> failedTasks;
  final List<ProjectArtifact> artifacts;
  final List<String> knownFacts;
  final List<PendingProjectQuestion> openQuestions;
  final ProjectStatus status;
  final ProjectPhase phase;
  final int iterationCount;
  final int maxIterations;
  final int maxFailedTasks;
  final String? activeTaskId;
  final String? chatSessionId;
  final String completionSummary;
  final ProjectBlocker? blocker;
  final List<ProjectDecisionRecord> decisions;
  final DateTime createdAt;
  final DateTime updatedAt;
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

  factory ProjectState.fromJson(Map<String, dynamic> json) {
    final rawVersion = jsonInt(json['schemaVersion'] ?? json['schema_version']);
    if (rawVersion < currentSchemaVersion ||
        (!json.containsKey('originalGoal') &&
            !json.containsKey('original_goal') &&
            json.containsKey('originalPrompt'))) {
      return _fromLegacyJson(json);
    }

    final now = DateTime.now();
    final rawCurrentTask = json['currentTask'] ?? json['current_task'];
    return ProjectState(
      schemaVersion: currentSchemaVersion,
      id: jsonString(json['id']),
      title: jsonString(json['title'], fallback: 'Untitled project'),
      originalGoal: jsonString(
        json['originalGoal'] ??
            json['original_goal'] ??
            json['originalPrompt'] ??
            json['original_prompt'],
      ),
      refinedGoal: jsonString(
        json['refinedGoal'] ??
            json['refined_goal'] ??
            json['goal'] ??
            json['objective'],
      ),
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      constraints: jsonStringList(json['constraints']),
      backlog: jsonMapList(json['backlog']).map(ProjectTask.fromJson).toList(),
      currentTask: rawCurrentTask is Map
          ? ProjectTask.fromJson(Map<String, dynamic>.from(rawCurrentTask))
          : null,
      completedTasks: jsonMapList(
        json['completedTasks'] ?? json['completed_tasks'],
      ).map(ProjectTask.fromJson).toList(),
      failedTasks: jsonMapList(
        json['failedTasks'] ?? json['failed_tasks'],
      ).map(ProjectTask.fromJson).toList(),
      artifacts: jsonMapList(
        json['artifacts'],
      ).map(ProjectArtifact.fromJson).toList(),
      knownFacts: jsonStringList(json['knownFacts'] ?? json['known_facts']),
      openQuestions: _openQuestionsFromJson(json),
      status: parseProjectStatus(json['status']),
      phase: parseProjectPhase(json['phase']),
      iterationCount: jsonInt(
        json['iterationCount'] ?? json['iteration_count'],
      ),
      maxIterations: parseOptionalLimit(
        json['maxIterations'] ?? json['max_iterations'],
        fallback: defaultMaxIterations,
      ),
      maxFailedTasks: jsonInt(
        json['maxFailedTasks'] ?? json['max_failed_tasks'],
        fallback: defaultMaxFailedTasks,
      ).clamp(1, 100).toInt(),
      activeTaskId: jsonNullableString(
        json['activeTaskId'] ?? json['active_task_id'],
      ),
      chatSessionId: jsonNullableString(
        json['chatSessionId'] ?? json['chat_session_id'],
      ),
      completionSummary: jsonString(
        json['completionSummary'] ?? json['completion_summary'],
      ),
      blocker: json['blocker'] == null
          ? null
          : ProjectBlocker.fromJson(jsonMap(json['blocker'])),
      decisions: jsonMapList(
        json['decisions'],
      ).map(ProjectDecisionRecord.fromJson).toList(),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: now,
      ),
      updatedAt: jsonDate(
        json['updatedAt'] ?? json['updated_at'],
        fallback: now,
      ),
      completedAt: jsonNullableDate(
        json['completedAt'] ?? json['completed_at'],
      ),
    );
  }

  static ProjectState _fromLegacyJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final originalGoal = jsonString(
      json['originalPrompt'] ?? json['original_prompt'],
    );
    final refinedGoal = jsonString(
      json['goal'] ?? json['objective'],
      fallback: originalGoal,
    );
    final activeTaskId = jsonNullableString(
      json['activeTaskId'] ?? json['active_task_id'],
    );
    final legacyTasks = jsonMapList(
      json['tasks'],
    ).map(ProjectTaskRef.fromJson).toList();
    final backlog = <ProjectTask>[];
    final completedTasks = <ProjectTask>[];
    final failedTasks = <ProjectTask>[];
    ProjectTask? currentTask;

    for (final task in legacyTasks) {
      final projectTask = ProjectTask.fromLegacyRef(task);
      if (task.taskId == activeTaskId && !task.status.isTerminal) {
        currentTask = projectTask.copyWith(status: ProjectTaskStatus.running);
      } else if (task.status == TaskStatus.completed) {
        completedTasks.add(
          projectTask.copyWith(status: ProjectTaskStatus.completed),
        );
      } else if (task.status == TaskStatus.failed ||
          task.status == TaskStatus.cancelled ||
          task.status == TaskStatus.blocked) {
        failedTasks.add(projectTask.copyWith(status: ProjectTaskStatus.failed));
      } else {
        backlog.add(projectTask.copyWith(status: ProjectTaskStatus.queued));
      }
    }

    final pendingQuestion =
        json['pendingQuestion'] == null && json['pending_question'] == null
        ? null
        : PendingProjectQuestion.fromJson(
            jsonMap(json['pendingQuestion'] ?? json['pending_question']),
          );
    final openQuestions = [?pendingQuestion];
    final rawStatus = (json['status'] ?? '').toString().trim().toLowerCase();
    final status = switch (rawStatus.replaceAll('-', '_')) {
      'paused' => ProjectStatus.active,
      'running' => ProjectStatus.runningTask,
      'blocked' =>
        openQuestions.isNotEmpty
            ? ProjectStatus.waitingForUser
            : ProjectStatus.blocked,
      'completed' => ProjectStatus.completed,
      'failed' => ProjectStatus.failed,
      'cancelled' => ProjectStatus.cancelled,
      _ => parseProjectStatus(json['status']),
    };
    final memorySummary = jsonString(
      json['memorySummary'] ?? json['memory_summary'],
    );
    return ProjectState(
      schemaVersion: currentSchemaVersion,
      id: jsonString(json['id']),
      title: jsonString(json['title'], fallback: 'Untitled project'),
      originalGoal: originalGoal,
      refinedGoal: refinedGoal,
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      constraints: jsonStringList(json['constraints']),
      backlog: backlog,
      currentTask: currentTask,
      completedTasks: completedTasks,
      failedTasks: failedTasks,
      artifacts: const [],
      knownFacts: [if (memorySummary.trim().isNotEmpty) memorySummary.trim()],
      openQuestions: openQuestions,
      status: status,
      phase: status == ProjectStatus.completed
          ? ProjectPhase.finalization
          : currentTask != null
          ? ProjectPhase.execution
          : ProjectPhase.planning,
      iterationCount: completedTasks.length + failedTasks.length,
      maxIterations: defaultMaxIterations,
      maxFailedTasks: defaultMaxFailedTasks,
      activeTaskId: activeTaskId,
      chatSessionId: jsonNullableString(
        json['chatSessionId'] ?? json['chat_session_id'],
      ),
      completionSummary: jsonString(
        json['completionSummary'] ?? json['completion_summary'],
      ),
      blocker: json['blocker'] == null
          ? null
          : ProjectBlocker.fromJson(jsonMap(json['blocker'])),
      decisions: jsonMapList(
        json['decisions'],
      ).map(ProjectDecisionRecord.fromJson).toList(),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: now,
      ),
      updatedAt: jsonDate(
        json['updatedAt'] ?? json['updated_at'],
        fallback: now,
      ),
      completedAt: jsonNullableDate(
        json['completedAt'] ?? json['completed_at'],
      ),
    );
  }

  static List<PendingProjectQuestion> _openQuestionsFromJson(
    Map<String, dynamic> json,
  ) {
    final questions = jsonMapList(
      json['openQuestions'] ?? json['open_questions'],
    ).map(PendingProjectQuestion.fromJson).toList();
    if (questions.isNotEmpty) return questions;
    final raw = json['pendingQuestion'] ?? json['pending_question'];
    if (raw is Map) {
      return [PendingProjectQuestion.fromJson(Map<String, dynamic>.from(raw))];
    }
    return const [];
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'id': id,
    'title': title,
    'originalGoal': originalGoal,
    'refinedGoal': refinedGoal,
    'successCriteria': successCriteria,
    'constraints': constraints,
    'backlog': backlog.map((task) => task.toJson()).toList(),
    if (currentTask != null) 'currentTask': currentTask!.toJson(),
    'completedTasks': completedTasks.map((task) => task.toJson()).toList(),
    'failedTasks': failedTasks.map((task) => task.toJson()).toList(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'knownFacts': knownFacts,
    'openQuestions': openQuestions
        .map((question) => question.toJson())
        .toList(),
    'status': status.wire,
    'phase': phase.wire,
    'iterationCount': iterationCount,
    'maxIterations': maxIterations,
    'maxFailedTasks': maxFailedTasks,
    if (activeTaskId != null) 'activeTaskId': activeTaskId,
    if (chatSessionId != null) 'chatSessionId': chatSessionId,
    'completionSummary': completionSummary,
    if (blocker != null) 'blocker': blocker!.toJson(),
    'decisions': decisions.map((decision) => decision.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
  };
}

typedef ProjectDocument = ProjectState;
typedef ProjectSnapshot = ProjectState;

class ProjectTask {
  final String id;
  final String title;
  final String objective;
  final List<String> relevantSuccessCriteria;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> context;
  final List<ProjectArtifact> expectedArtifacts;
  final ProjectTaskStatus status;
  final String? taskDocumentId;
  final String fingerprint;
  final String? rejectionReason;
  final DateTime createdAt;
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
    required this.fingerprint,
    required this.rejectionReason,
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
    String? fingerprint,
    Object? rejectionReason = kSentinel,
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
      fingerprint:
          fingerprint ??
          this.fingerprint.ifEmpty(
            projectTaskFingerprint(nextObjective, nextCriteria),
          ),
      rejectionReason: resolve(rejectionReason, this.rejectionReason),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ProjectTask.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final objective = jsonString(json['objective'] ?? json['prompt']);
    final criteria = jsonStringList(
      json['relevantSuccessCriteria'] ??
          json['relevant_success_criteria'] ??
          json['successCriteria'] ??
          json['success_criteria'],
    );
    return ProjectTask(
      id: jsonString(json['id'], fallback: 'project_task'),
      title: jsonString(json['title'], fallback: 'Untitled task'),
      objective: objective,
      relevantSuccessCriteria: criteria,
      doneCriteria: jsonStringList(
        json['doneCriteria'] ?? json['done_criteria'],
      ),
      outOfScope: jsonStringList(json['outOfScope'] ?? json['out_of_scope']),
      context: jsonStringList(json['context']),
      expectedArtifacts: jsonMapList(
        json['expectedArtifacts'] ?? json['expected_artifacts'],
      ).map(ProjectArtifact.fromJson).toList(),
      status: parseProjectTaskStatus(json['status']),
      taskDocumentId: jsonNullableString(
        json['taskDocumentId'] ?? json['task_document_id'],
      ),
      fingerprint: jsonString(
        json['fingerprint'],
        fallback: projectTaskFingerprint(objective, criteria),
      ),
      rejectionReason: jsonNullableString(
        json['rejectionReason'] ?? json['rejection_reason'],
      ),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: now,
      ),
      updatedAt: jsonDate(
        json['updatedAt'] ?? json['updated_at'],
        fallback: now,
      ),
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
      fingerprint: projectTaskFingerprint(objective, criteria),
      rejectionReason: null,
      createdAt: ref.createdAt,
      updatedAt: ref.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'objective': objective,
    'relevantSuccessCriteria': relevantSuccessCriteria,
    'doneCriteria': doneCriteria,
    'outOfScope': outOfScope,
    'context': context,
    'expectedArtifacts': expectedArtifacts
        .map((artifact) => artifact.toJson())
        .toList(),
    'status': status.wire,
    if (taskDocumentId != null) 'taskDocumentId': taskDocumentId,
    'fingerprint': fingerprint,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class ProjectArtifact {
  final String id;
  final String? projectTaskId;
  final String? taskDocumentId;
  final String path;
  final String description;
  final String kind;
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

  factory ProjectArtifact.fromJson(Map<String, dynamic> json) {
    final path = jsonString(json['path']);
    return ProjectArtifact(
      id: jsonString(json['id'], fallback: path),
      projectTaskId: jsonNullableString(
        json['projectTaskId'] ?? json['project_task_id'],
      ),
      taskDocumentId: jsonNullableString(
        json['taskDocumentId'] ?? json['task_document_id'],
      ),
      path: path,
      description: jsonString(json['description']),
      kind: jsonString(json['kind'], fallback: 'file'),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (projectTaskId != null) 'projectTaskId': projectTaskId,
    if (taskDocumentId != null) 'taskDocumentId': taskDocumentId,
    'path': path,
    'description': description,
    'kind': kind,
    'createdAt': createdAt.toIso8601String(),
  };
}

class TaskResult {
  final String taskDocumentId;
  final TaskStatus status;
  final String summary;
  final String memoryUpdate;
  final List<ProjectArtifact> artifacts;
  final int toolCallCount;
  final String? userQuestion;
  final String? error;

  const TaskResult({
    required this.taskDocumentId,
    required this.status,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
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
    required this.backlogAdditions,
    required this.openQuestions,
    this.failureReason,
  });
}

class ProjectTaskRef {
  final String taskId;
  final String title;
  final TaskStatus status;
  final String summary;
  final DateTime createdAt;
  final DateTime updatedAt;
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

  factory ProjectTaskRef.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ProjectTaskRef(
      taskId: jsonString(json['taskId'] ?? json['task_id']),
      title: jsonString(json['title'], fallback: 'Untitled task'),
      status: parseTaskStatus(json['status']),
      summary: jsonString(json['summary']),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: now,
      ),
      updatedAt: jsonDate(
        json['updatedAt'] ?? json['updated_at'],
        fallback: now,
      ),
      completedAt: jsonNullableDate(
        json['completedAt'] ?? json['completed_at'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'title': title,
    'status': status.wire,
    'summary': summary,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
  };
}

class ProjectDecisionRecord {
  final String id;
  final ProjectDecisionType decision;
  final String summary;
  final String memoryUpdate;
  final String? taskId;
  final String? taskTitle;
  final String? taskPrompt;
  final String? error;
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

  factory ProjectDecisionRecord.fromJson(Map<String, dynamic> json) {
    return ProjectDecisionRecord(
      id: jsonString(json['id']),
      decision: parseProjectDecisionType(json['decision']),
      summary: jsonString(json['summary']),
      memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
      taskId: jsonNullableString(json['taskId'] ?? json['task_id']),
      taskTitle: jsonNullableString(json['taskTitle'] ?? json['task_title']),
      taskPrompt: jsonNullableString(json['taskPrompt'] ?? json['task_prompt']),
      error: jsonNullableString(json['error']),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'decision': decision.wire,
    'summary': summary,
    'memoryUpdate': memoryUpdate,
    if (taskId != null) 'taskId': taskId,
    if (taskTitle != null) 'taskTitle': taskTitle,
    if (taskPrompt != null) 'taskPrompt': taskPrompt,
    if (error != null) 'error': error,
    'createdAt': createdAt.toIso8601String(),
  };
}

class ProjectBlocker {
  final ProjectBlockerType type;
  final String message;
  final String? taskId;
  final DateTime createdAt;

  const ProjectBlocker({
    required this.type,
    required this.message,
    required this.createdAt,
    this.taskId,
  });

  factory ProjectBlocker.fromJson(Map<String, dynamic> json) {
    return ProjectBlocker(
      type: parseProjectBlockerType(json['type']),
      message: jsonString(json['message']),
      taskId: jsonNullableString(json['taskId'] ?? json['task_id']),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.wire,
    'message': message,
    if (taskId != null) 'taskId': taskId,
    'createdAt': createdAt.toIso8601String(),
  };
}

class PendingProjectQuestion {
  final String id;
  final String question;
  final DateTime createdAt;

  const PendingProjectQuestion({
    required this.id,
    required this.question,
    required this.createdAt,
  });

  factory PendingProjectQuestion.fromJson(Map<String, dynamic> json) {
    return PendingProjectQuestion(
      id: jsonString(json['id']),
      question: jsonString(json['question']),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'createdAt': createdAt.toIso8601String(),
  };
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
