import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;

enum ExecutionMode { chat, refine, plan, job, continueJob }

enum JobStatus {
  draft,
  planned,
  running,
  paused,
  blocked,
  completed,
  failed,
  cancelled,
}

enum JobStepStatus {
  pending,
  approved,
  running,
  completed,
  blocked,
  failed,
  skipped,
}

enum JobRunStatus {
  running,
  completed,
  blocked,
  failed,
  cancelled,
  skipped,
  needsReplan,
  replanned,
}

extension ExecutionModeWire on ExecutionMode {
  String get wire => switch (this) {
    ExecutionMode.continueJob => 'continue_job',
    _ => name,
  };

  String get label => switch (this) {
    ExecutionMode.chat => 'Chat',
    ExecutionMode.refine => 'Refine',
    ExecutionMode.plan => 'Plan',
    ExecutionMode.job => 'Job',
    ExecutionMode.continueJob => 'Continue Job',
  };
}

extension JobStatusWire on JobStatus {
  String get wire => name;
}

extension JobStepStatusWire on JobStepStatus {
  String get wire => name;
}

extension JobRunStatusWire on JobRunStatus {
  String get wire => switch (this) {
    JobRunStatus.needsReplan => 'needs_replan',
    _ => name,
  };
}

ExecutionMode parseExecutionMode(Object? value) => _parseEnum(
  ExecutionMode.values,
  value,
  ExecutionMode.chat,
  aliases: {'continue_job': ExecutionMode.continueJob},
);

JobStatus parseJobStatus(Object? value) =>
    _parseEnum(JobStatus.values, value, JobStatus.paused);

JobStepStatus parseJobStepStatus(Object? value) =>
    _parseEnum(JobStepStatus.values, value, JobStepStatus.pending);

JobRunStatus parseJobRunStatus(Object? value) => _parseEnum(
  JobRunStatus.values,
  value,
  JobRunStatus.completed,
  aliases: {'needs_replan': JobRunStatus.needsReplan},
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

class RefinedJobBrief {
  final String title;
  final String goal;
  final List<String> constraints;
  final List<String> successCriteria;
  final List<String> assumptions;
  final List<String> questions;

  const RefinedJobBrief({
    required this.title,
    required this.goal,
    this.constraints = const [],
    this.successCriteria = const [],
    this.assumptions = const [],
    this.questions = const [],
  });

  factory RefinedJobBrief.fromJson(Map<String, dynamic> json) {
    return RefinedJobBrief(
      title: jsonString(json['title'], fallback: 'Untitled job'),
      goal: jsonString(json['goal'] ?? json['objective']),
      constraints: jsonStringList(json['constraints']),
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      assumptions: jsonStringList(json['assumptions']),
      questions: jsonStringList(
        json['questions'] ?? json['clarifyingQuestions'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'goal': goal,
    'constraints': constraints,
    'successCriteria': successCriteria,
    'assumptions': assumptions,
    'questions': questions,
  };
}

class JobDocument {
  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final String id;
  final String title;
  final String originalPrompt;
  final String goal;
  final List<String> constraints;
  final List<String> successCriteria;
  final List<JobStep> steps;
  final JobStatus status;
  final String? currentStepId;
  final String memorySummary;
  final List<JobRun> runs;
  final PendingJobApproval? pendingApproval;
  final PendingJobQuestion? pendingQuestion;
  final String? chatSessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const JobDocument({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.title,
    required this.originalPrompt,
    required this.goal,
    required this.constraints,
    required this.successCriteria,
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
    this.completedAt,
  });

  JobDocument copyWith({
    int? schemaVersion,
    String? id,
    String? title,
    String? originalPrompt,
    String? goal,
    List<String>? constraints,
    List<String>? successCriteria,
    List<JobStep>? steps,
    JobStatus? status,
    Object? currentStepId = kSentinel,
    String? memorySummary,
    List<JobRun>? runs,
    Object? pendingApproval = kSentinel,
    Object? pendingQuestion = kSentinel,
    Object? chatSessionId = kSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return JobDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      title: title ?? this.title,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      goal: goal ?? this.goal,
      constraints: constraints ?? this.constraints,
      successCriteria: successCriteria ?? this.successCriteria,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      currentStepId: resolve(currentStepId, this.currentStepId),
      memorySummary: memorySummary ?? this.memorySummary,
      runs: runs ?? this.runs,
      pendingApproval: resolve(pendingApproval, this.pendingApproval),
      pendingQuestion: resolve(pendingQuestion, this.pendingQuestion),
      chatSessionId: resolve(chatSessionId, this.chatSessionId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
    );
  }

  JobStep? get currentStep =>
      currentStepId == null ? null : stepById(currentStepId!);

  JobStep? get nextRunnableStep => steps
      .where(
        (step) =>
            step.status == JobStepStatus.pending ||
            step.status == JobStepStatus.approved ||
            step.status == JobStepStatus.blocked ||
            step.status == JobStepStatus.failed,
      )
      .firstOrNull;

  bool get isTerminal =>
      status == JobStatus.completed ||
      status == JobStatus.cancelled ||
      status == JobStatus.failed;

  JobStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }

  factory JobDocument.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return JobDocument(
      schemaVersion: jsonInt(json['schemaVersion'] ?? json['schema_version']),
      id: jsonString(json['id']),
      title: jsonString(json['title'], fallback: 'Untitled job'),
      originalPrompt: jsonString(
        json['originalPrompt'] ?? json['original_prompt'],
      ),
      goal: jsonString(json['goal'] ?? json['objective']),
      constraints: jsonStringList(json['constraints']),
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      steps: jsonMapList(json['steps']).map(JobStep.fromJson).toList(),
      status: parseJobStatus(json['status']),
      currentStepId: jsonNullableString(
        json['currentStepId'] ?? json['current_step_id'],
      ),
      memorySummary: jsonString(
        json['memorySummary'] ?? json['memory_summary'],
      ),
      runs: jsonMapList(json['runs']).map(JobRun.fromJson).toList(),
      pendingApproval:
          json['pendingApproval'] == null && json['pending_approval'] == null
          ? null
          : PendingJobApproval.fromJson(
              jsonMap(json['pendingApproval'] ?? json['pending_approval']),
            ),
      pendingQuestion:
          json['pendingQuestion'] == null && json['pending_question'] == null
          ? null
          : PendingJobQuestion.fromJson(
              jsonMap(json['pendingQuestion'] ?? json['pending_question']),
            ),
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
    'steps': steps.map((step) => step.toJson()).toList(),
    'status': status.wire,
    if (currentStepId != null) 'currentStepId': currentStepId,
    'memorySummary': memorySummary,
    'runs': runs.map((run) => run.toJson()).toList(),
    if (pendingApproval != null) 'pendingApproval': pendingApproval!.toJson(),
    if (pendingQuestion != null) 'pendingQuestion': pendingQuestion!.toJson(),
    if (chatSessionId != null) 'chatSessionId': chatSessionId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
  };
}

typedef JobSnapshot = JobDocument;

class JobStep {
  final String id;
  final String title;
  final String objective;
  final List<String> instructions;
  final bool mayEditFiles;
  final List<JobArtifact> artifacts;
  final JobStepStatus status;

  const JobStep({
    required this.id,
    required this.title,
    required this.objective,
    required this.instructions,
    required this.mayEditFiles,
    required this.artifacts,
    required this.status,
  });

  JobStep copyWith({
    String? id,
    String? title,
    String? objective,
    List<String>? instructions,
    bool? mayEditFiles,
    List<JobArtifact>? artifacts,
    JobStepStatus? status,
  }) {
    return JobStep(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      instructions: instructions ?? this.instructions,
      mayEditFiles: mayEditFiles ?? this.mayEditFiles,
      artifacts: artifacts ?? this.artifacts,
      status: status ?? this.status,
    );
  }

  factory JobStep.fromJson(Map<String, dynamic> json) {
    return JobStep(
      id: jsonString(json['id']),
      title: jsonString(json['title'], fallback: 'Untitled step'),
      objective: jsonString(json['objective']),
      instructions: jsonStringList(json['instructions']),
      mayEditFiles: jsonBool(json['mayEditFiles'] ?? json['may_edit_files']),
      artifacts: jsonMapList(
        json['artifacts'],
      ).map(JobArtifact.fromJson).toList(),
      status: parseJobStepStatus(json['status']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'objective': objective,
    'instructions': instructions,
    'mayEditFiles': mayEditFiles,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'status': status.wire,
  };
}

class JobArtifact {
  final String path;
  final String? description;
  final String? stepId;
  final DateTime? createdAt;

  const JobArtifact({
    required this.path,
    this.description,
    this.stepId,
    this.createdAt,
  });

  factory JobArtifact.fromJson(Map<String, dynamic> json) {
    return JobArtifact(
      path: jsonString(json['path']),
      description: jsonNullableString(json['description']),
      stepId: jsonNullableString(json['stepId'] ?? json['step_id']),
      createdAt: jsonNullableDate(json['createdAt'] ?? json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    if (description != null) 'description': description,
    if (stepId != null) 'stepId': stepId,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };
}

class JobRun {
  final String runId;
  final String stepId;
  final JobRunStatus status;
  final String summary;
  final String memoryUpdate;
  final List<JobToolCallRecord> toolCalls;
  final List<JobArtifact> artifacts;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? replanReason;
  final String? error;

  const JobRun({
    required this.runId,
    required this.stepId,
    required this.status,
    required this.summary,
    required this.memoryUpdate,
    required this.toolCalls,
    required this.artifacts,
    required this.startedAt,
    this.completedAt,
    this.replanReason,
    this.error,
  });

  JobRun copyWith({
    String? runId,
    String? stepId,
    JobRunStatus? status,
    String? summary,
    String? memoryUpdate,
    List<JobToolCallRecord>? toolCalls,
    List<JobArtifact>? artifacts,
    DateTime? startedAt,
    Object? completedAt = kSentinel,
    Object? replanReason = kSentinel,
    Object? error = kSentinel,
  }) {
    return JobRun(
      runId: runId ?? this.runId,
      stepId: stepId ?? this.stepId,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      memoryUpdate: memoryUpdate ?? this.memoryUpdate,
      toolCalls: toolCalls ?? this.toolCalls,
      artifacts: artifacts ?? this.artifacts,
      startedAt: startedAt ?? this.startedAt,
      completedAt: resolve(completedAt, this.completedAt),
      replanReason: resolve(replanReason, this.replanReason),
      error: resolve(error, this.error),
    );
  }

  factory JobRun.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return JobRun(
      runId: jsonString(json['runId'] ?? json['run_id']),
      stepId: jsonString(json['stepId'] ?? json['step_id']),
      status: parseJobRunStatus(json['status']),
      summary: jsonString(json['summary']),
      memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
      toolCalls: jsonMapList(
        json['toolCalls'] ?? json['tool_calls'],
      ).map(JobToolCallRecord.fromJson).toList(),
      artifacts: jsonMapList(
        json['artifacts'],
      ).map(JobArtifact.fromJson).toList(),
      startedAt: jsonDate(
        json['startedAt'] ?? json['started_at'],
        fallback: now,
      ),
      completedAt: jsonNullableDate(
        json['completedAt'] ?? json['completed_at'],
      ),
      replanReason: jsonNullableString(
        json['replanReason'] ?? json['replan_reason'],
      ),
      error: jsonNullableString(json['error']),
    );
  }

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'stepId': stepId,
    'status': status.wire,
    'summary': summary,
    'memoryUpdate': memoryUpdate,
    'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (replanReason != null) 'replanReason': replanReason,
    if (error != null) 'error': error,
  };
}

class JobToolCallRecord {
  final String id;
  final String stepId;
  final String runId;
  final String toolName;
  final Object? arguments;
  final String? resultSummary;
  final String? error;
  final DateTime timestamp;

  const JobToolCallRecord({
    required this.id,
    required this.stepId,
    required this.runId,
    required this.toolName,
    required this.timestamp,
    this.arguments,
    this.resultSummary,
    this.error,
  });

  factory JobToolCallRecord.fromJson(Map<String, dynamic> json) {
    return JobToolCallRecord(
      id: jsonString(json['id']),
      stepId: jsonString(json['stepId'] ?? json['step_id']),
      runId: jsonString(json['runId'] ?? json['run_id']),
      toolName: jsonString(json['toolName'] ?? json['tool_name']),
      arguments: json['arguments'],
      resultSummary: jsonNullableString(
        json['resultSummary'] ?? json['result_summary'],
      ),
      error: jsonNullableString(json['error']),
      timestamp: jsonDate(json['timestamp'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'stepId': stepId,
    'runId': runId,
    'toolName': toolName,
    if (arguments != null) 'arguments': arguments,
    if (resultSummary != null) 'resultSummary': resultSummary,
    if (error != null) 'error': error,
    'timestamp': timestamp.toIso8601String(),
  };
}

class PendingJobApproval {
  final String stepId;
  final String reason;
  final DateTime createdAt;

  const PendingJobApproval({
    required this.stepId,
    required this.reason,
    required this.createdAt,
  });

  factory PendingJobApproval.fromJson(Map<String, dynamic> json) {
    return PendingJobApproval(
      stepId: jsonString(json['stepId'] ?? json['step_id']),
      reason: jsonString(json['reason']),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'stepId': stepId,
    'reason': reason,
    'createdAt': createdAt.toIso8601String(),
  };
}

class PendingJobQuestion {
  final String id;
  final String stepId;
  final String question;
  final DateTime createdAt;

  const PendingJobQuestion({
    required this.id,
    required this.stepId,
    required this.question,
    required this.createdAt,
  });

  factory PendingJobQuestion.fromJson(Map<String, dynamic> json) {
    return PendingJobQuestion(
      id: jsonString(json['id']),
      stepId: jsonString(json['stepId'] ?? json['step_id']),
      question: jsonString(json['question']),
      createdAt: jsonDate(
        json['createdAt'] ?? json['created_at'],
        fallback: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'stepId': stepId,
    'question': question,
    'createdAt': createdAt.toIso8601String(),
  };
}
