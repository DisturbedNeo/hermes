import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/models/task.dart';

enum ProjectStatus { paused, running, blocked, completed, failed, cancelled }

enum ProjectBlockerType {
  question,
  taskApproval,
  taskBlocked,
  taskFailed,
  budget,
  error,
}

enum ProjectDecisionType { createTask, complete, blocked }

extension ProjectStatusWire on ProjectStatus {
  String get wire => name;
}

extension ProjectBlockerTypeWire on ProjectBlockerType {
  String get wire => switch (this) {
    ProjectBlockerType.taskApproval => 'task_approval',
    ProjectBlockerType.taskBlocked => 'task_blocked',
    ProjectBlockerType.taskFailed => 'task_failed',
    _ => name,
  };
}

extension ProjectDecisionTypeWire on ProjectDecisionType {
  String get wire => switch (this) {
    ProjectDecisionType.createTask => 'create_task',
    _ => name,
  };
}

ProjectStatus parseProjectStatus(Object? value) =>
    _parseEnum(ProjectStatus.values, value, ProjectStatus.paused);

ProjectBlockerType parseProjectBlockerType(Object? value) => _parseEnum(
  ProjectBlockerType.values,
  value,
  ProjectBlockerType.error,
  aliases: {
    'task_approval': ProjectBlockerType.taskApproval,
    'task_blocked': ProjectBlockerType.taskBlocked,
    'task_failed': ProjectBlockerType.taskFailed,
  },
);

ProjectDecisionType parseProjectDecisionType(Object? value) => _parseEnum(
  ProjectDecisionType.values,
  value,
  ProjectDecisionType.blocked,
  aliases: {'create_task': ProjectDecisionType.createTask},
);

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

class ProjectDocument {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String id;
  final String title;
  final String originalPrompt;
  final String goal;
  final List<String> constraints;
  final List<String> successCriteria;
  final ProjectStatus status;
  final String? activeTaskId;
  final String memorySummary;
  final String completionSummary;
  final List<ProjectTaskRef> tasks;
  final List<ProjectDecisionRecord> decisions;
  final PendingProjectQuestion? pendingQuestion;
  final ProjectBlocker? blocker;
  final String? chatSessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const ProjectDocument({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.title,
    required this.originalPrompt,
    required this.goal,
    required this.constraints,
    required this.successCriteria,
    required this.status,
    required this.activeTaskId,
    required this.memorySummary,
    required this.completionSummary,
    required this.tasks,
    required this.decisions,
    required this.createdAt,
    required this.updatedAt,
    this.pendingQuestion,
    this.blocker,
    this.chatSessionId,
    this.completedAt,
  });

  bool get isTerminal =>
      status == ProjectStatus.completed ||
      status == ProjectStatus.cancelled ||
      status == ProjectStatus.failed;

  ProjectTaskRef? taskRef(String taskId) {
    for (final task in tasks) {
      if (task.taskId == taskId) return task;
    }
    return null;
  }

  ProjectDocument copyWith({
    int? schemaVersion,
    String? id,
    String? title,
    String? originalPrompt,
    String? goal,
    List<String>? constraints,
    List<String>? successCriteria,
    ProjectStatus? status,
    Object? activeTaskId = kSentinel,
    String? memorySummary,
    String? completionSummary,
    List<ProjectTaskRef>? tasks,
    List<ProjectDecisionRecord>? decisions,
    Object? pendingQuestion = kSentinel,
    Object? blocker = kSentinel,
    Object? chatSessionId = kSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return ProjectDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      title: title ?? this.title,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      goal: goal ?? this.goal,
      constraints: constraints ?? this.constraints,
      successCriteria: successCriteria ?? this.successCriteria,
      status: status ?? this.status,
      activeTaskId: resolve(activeTaskId, this.activeTaskId),
      memorySummary: memorySummary ?? this.memorySummary,
      completionSummary: completionSummary ?? this.completionSummary,
      tasks: tasks ?? this.tasks,
      decisions: decisions ?? this.decisions,
      pendingQuestion: resolve(pendingQuestion, this.pendingQuestion),
      blocker: resolve(blocker, this.blocker),
      chatSessionId: resolve(chatSessionId, this.chatSessionId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
    );
  }

  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ProjectDocument(
      schemaVersion: jsonInt(json['schemaVersion'] ?? json['schema_version']),
      id: jsonString(json['id']),
      title: jsonString(json['title'], fallback: 'Untitled project'),
      originalPrompt: jsonString(
        json['originalPrompt'] ?? json['original_prompt'],
      ),
      goal: jsonString(json['goal'] ?? json['objective']),
      constraints: jsonStringList(json['constraints']),
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      status: parseProjectStatus(json['status']),
      activeTaskId: jsonNullableString(
        json['activeTaskId'] ?? json['active_task_id'],
      ),
      memorySummary: jsonString(
        json['memorySummary'] ?? json['memory_summary'],
      ),
      completionSummary: jsonString(
        json['completionSummary'] ?? json['completion_summary'],
      ),
      tasks: jsonMapList(json['tasks']).map(ProjectTaskRef.fromJson).toList(),
      decisions: jsonMapList(
        json['decisions'],
      ).map(ProjectDecisionRecord.fromJson).toList(),
      pendingQuestion:
          json['pendingQuestion'] == null && json['pending_question'] == null
          ? null
          : PendingProjectQuestion.fromJson(
              jsonMap(json['pendingQuestion'] ?? json['pending_question']),
            ),
      blocker: json['blocker'] == null
          ? null
          : ProjectBlocker.fromJson(jsonMap(json['blocker'])),
      chatSessionId: jsonNullableString(
        json['chatSessionId'] ?? json['chat_session_id'],
      ),
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
    'schemaVersion': schemaVersion,
    'id': id,
    'title': title,
    'originalPrompt': originalPrompt,
    'goal': goal,
    'constraints': constraints,
    'successCriteria': successCriteria,
    'status': status.wire,
    if (activeTaskId != null) 'activeTaskId': activeTaskId,
    'memorySummary': memorySummary,
    'completionSummary': completionSummary,
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'decisions': decisions.map((decision) => decision.toJson()).toList(),
    if (pendingQuestion != null) 'pendingQuestion': pendingQuestion!.toJson(),
    if (blocker != null) 'blocker': blocker!.toJson(),
    if (chatSessionId != null) 'chatSessionId': chatSessionId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
  };
}

typedef ProjectSnapshot = ProjectDocument;

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

  ProjectTaskRef copyWith({
    String? taskId,
    String? title,
    TaskStatus? status,
    String? summary,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return ProjectTaskRef(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
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
