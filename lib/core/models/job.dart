import 'package:hermes/core/models/tool_definition.dart';

enum ExecutionMode { chat, refine, plan, job, continueJob }

enum AutonomyLevel { manual, checkpointed, automatic }

enum JobDomain { development, creativeWriting, research, general, unknown }

enum RiskLevel { low, medium, high }

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

enum PhaseStatus {
  pending,
  running,
  reviewing,
  completed,
  failed,
  skipped,
  blocked,
}

enum TerminalPolicy { none, readonly, workspaceMutating, unrestrictedWorkspace }

enum ReviewStatus { passed, failed, warning, blocked }

enum ReviewerType { none, model, deterministic, hybrid, human }

enum ReviewRecommendation {
  continueJob,
  retryPhase,
  askUser,
  revisePlan,
  stopJob,
}

enum PhaseRunStatus { running, completed, failed, blocked, reviewFailed }

enum OpenQuestionStatus { open, answered, dismissed }

enum ArtifactFormat { markdown, json, yaml, text, code, other }

enum ReplanScope { currentPhase, remainingPhases, entireJob }

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

extension AutonomyLevelWire on AutonomyLevel {
  String get wire => name;
}

extension JobDomainWire on JobDomain {
  String get wire => switch (this) {
    JobDomain.creativeWriting => 'creative_writing',
    _ => name,
  };
}

extension RiskLevelWire on RiskLevel {
  String get wire => name;
}

extension JobStatusWire on JobStatus {
  String get wire => name;
}

extension PhaseStatusWire on PhaseStatus {
  String get wire => name;
}

extension TerminalPolicyWire on TerminalPolicy {
  String get wire => switch (this) {
    TerminalPolicy.workspaceMutating => 'workspace_mutating',
    TerminalPolicy.unrestrictedWorkspace => 'unrestricted_workspace',
    _ => name,
  };
}

extension ReviewStatusWire on ReviewStatus {
  String get wire => name;
}

extension ReviewerTypeWire on ReviewerType {
  String get wire => name;
}

extension ReviewRecommendationWire on ReviewRecommendation {
  String get wire => switch (this) {
    ReviewRecommendation.continueJob => 'continue',
    ReviewRecommendation.retryPhase => 'retry_phase',
    ReviewRecommendation.askUser => 'ask_user',
    ReviewRecommendation.revisePlan => 'revise_plan',
    ReviewRecommendation.stopJob => 'stop_job',
  };
}

extension PhaseRunStatusWire on PhaseRunStatus {
  String get wire => switch (this) {
    PhaseRunStatus.reviewFailed => 'review_failed',
    _ => name,
  };
}

extension OpenQuestionStatusWire on OpenQuestionStatus {
  String get wire => name;
}

extension ArtifactFormatWire on ArtifactFormat {
  String get wire => name;
}

extension ReplanScopeWire on ReplanScope {
  String get wire => switch (this) {
    ReplanScope.currentPhase => 'current_phase',
    ReplanScope.remainingPhases => 'remaining_phases',
    ReplanScope.entireJob => 'entire_job',
  };

  String get label => switch (this) {
    ReplanScope.currentPhase => 'Current Phase',
    ReplanScope.remainingPhases => 'Remaining Phases',
    ReplanScope.entireJob => 'Entire Job',
  };
}

ExecutionMode parseExecutionMode(Object? value) => _parseEnum(
  ExecutionMode.values,
  value,
  ExecutionMode.chat,
  aliases: {'continue_job': ExecutionMode.continueJob},
);

AutonomyLevel parseAutonomyLevel(Object? value) =>
    _parseEnum(AutonomyLevel.values, value, AutonomyLevel.checkpointed);

JobDomain parseJobDomain(Object? value) => _parseEnum(
  JobDomain.values,
  value,
  JobDomain.unknown,
  aliases: {'creative_writing': JobDomain.creativeWriting},
);

RiskLevel parseRiskLevel(Object? value) =>
    _parseEnum(RiskLevel.values, value, RiskLevel.medium);

JobStatus parseJobStatus(Object? value) =>
    _parseEnum(JobStatus.values, value, JobStatus.planned);

PhaseStatus parsePhaseStatus(Object? value) =>
    _parseEnum(PhaseStatus.values, value, PhaseStatus.pending);

TerminalPolicy parseTerminalPolicy(Object? value) => _parseEnum(
  TerminalPolicy.values,
  value,
  TerminalPolicy.none,
  aliases: {
    'read_only': TerminalPolicy.readonly,
    'workspace_mutating': TerminalPolicy.workspaceMutating,
    'unrestricted_workspace': TerminalPolicy.unrestrictedWorkspace,
  },
);

ReviewStatus parseReviewStatus(Object? value) =>
    _parseEnum(ReviewStatus.values, value, ReviewStatus.warning);

ReviewerType parseReviewerType(Object? value) =>
    _parseEnum(ReviewerType.values, value, ReviewerType.hybrid);

ReviewRecommendation parseReviewRecommendation(Object? value) => _parseEnum(
  ReviewRecommendation.values,
  value,
  ReviewRecommendation.continueJob,
  aliases: {
    'continue': ReviewRecommendation.continueJob,
    'continue_job': ReviewRecommendation.continueJob,
    'retry_phase': ReviewRecommendation.retryPhase,
    'ask_user': ReviewRecommendation.askUser,
    'revise_plan': ReviewRecommendation.revisePlan,
    'stop_job': ReviewRecommendation.stopJob,
  },
);

PhaseRunStatus parsePhaseRunStatus(Object? value) => _parseEnum(
  PhaseRunStatus.values,
  value,
  PhaseRunStatus.running,
  aliases: {'review_failed': PhaseRunStatus.reviewFailed},
);

OpenQuestionStatus parseOpenQuestionStatus(Object? value) =>
    _parseEnum(OpenQuestionStatus.values, value, OpenQuestionStatus.open);

ArtifactFormat? parseArtifactFormat(Object? value) {
  if (value == null) return null;
  return _parseEnum(ArtifactFormat.values, value, ArtifactFormat.other);
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
  final alias = aliases[normalised];
  if (alias != null) return alias;
  for (final item in values) {
    if (item.name.toLowerCase() == normalised) return item;
  }
  return fallback;
}

class WorkspaceMetadata {
  final String? workspaceName;
  final List<String> rootFiles;
  final String? detectedProjectType;
  final List<String> packageManagerFiles;
  final bool gitAvailable;
  final List<String> existingJobIds;

  const WorkspaceMetadata({
    this.workspaceName,
    this.rootFiles = const [],
    this.detectedProjectType,
    this.packageManagerFiles = const [],
    this.gitAvailable = false,
    this.existingJobIds = const [],
  });

  Map<String, dynamic> toJson() => {
    if (workspaceName != null) 'workspaceName': workspaceName,
    'rootFiles': rootFiles,
    if (detectedProjectType != null) 'detectedProjectType': detectedProjectType,
    'packageManagerFiles': packageManagerFiles,
    'gitAvailable': gitAvailable,
    'existingJobIds': existingJobIds,
  };
}

class PromptRefinerInput {
  final String userPrompt;
  final WorkspaceMetadata? workspaceMetadata;
  final List<ToolDefinition> availableTools;
  final ExecutionMode userSelectedMode;
  final String? selectedPromptPreset;
  final String? recentChatSummary;

  const PromptRefinerInput({
    required this.userPrompt,
    required this.availableTools,
    required this.userSelectedMode,
    this.workspaceMetadata,
    this.selectedPromptPreset,
    this.recentChatSummary,
  });

  Map<String, dynamic> toJson() => {
    'userPrompt': userPrompt,
    if (workspaceMetadata != null) 'workspaceMetadata': workspaceMetadata,
    if (selectedPromptPreset != null)
      'selectedPromptPreset': selectedPromptPreset,
    if (recentChatSummary != null) 'recentChatSummary': recentChatSummary,
    'userSelectedMode': userSelectedMode.wire,
    'availableTools': availableTools.map(_toolDefinitionToJson).toList(),
  };
}

class TaskBrief {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String title;
  final String originalPrompt;
  final String objective;
  final List<String> successCriteria;
  final List<String> constraints;
  final List<String> nonGoals;
  final List<String> assumptions;
  final List<ClarifyingQuestion> clarifyingQuestions;
  final ExecutionMode recommendedMode;
  final AutonomyLevel recommendedAutonomy;
  final List<RequiredOutput> requiredOutputs;
  final JobDomain domain;
  final RiskLevel riskLevel;

  const TaskBrief({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.title,
    required this.originalPrompt,
    required this.objective,
    required this.successCriteria,
    required this.constraints,
    required this.nonGoals,
    required this.assumptions,
    required this.clarifyingQuestions,
    required this.recommendedMode,
    required this.recommendedAutonomy,
    required this.requiredOutputs,
    required this.domain,
    required this.riskLevel,
  });

  TaskBrief copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? title,
    String? originalPrompt,
    String? objective,
    List<String>? successCriteria,
    List<String>? constraints,
    List<String>? nonGoals,
    List<String>? assumptions,
    List<ClarifyingQuestion>? clarifyingQuestions,
    ExecutionMode? recommendedMode,
    AutonomyLevel? recommendedAutonomy,
    List<RequiredOutput>? requiredOutputs,
    JobDomain? domain,
    RiskLevel? riskLevel,
  }) {
    return TaskBrief(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: title ?? this.title,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      objective: objective ?? this.objective,
      successCriteria: successCriteria ?? this.successCriteria,
      constraints: constraints ?? this.constraints,
      nonGoals: nonGoals ?? this.nonGoals,
      assumptions: assumptions ?? this.assumptions,
      clarifyingQuestions: clarifyingQuestions ?? this.clarifyingQuestions,
      recommendedMode: recommendedMode ?? this.recommendedMode,
      recommendedAutonomy: recommendedAutonomy ?? this.recommendedAutonomy,
      requiredOutputs: requiredOutputs ?? this.requiredOutputs,
      domain: domain ?? this.domain,
      riskLevel: riskLevel ?? this.riskLevel,
    );
  }

  factory TaskBrief.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return TaskBrief(
      id: _string(json['id'], fallback: ''),
      createdAt: _date(json['createdAt'] ?? json['created_at'], fallback: now),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at'], fallback: now),
      title: _string(json['title'], fallback: 'Untitled job'),
      originalPrompt: _string(
        json['originalPrompt'] ?? json['original_prompt'],
      ),
      objective: _string(json['objective']),
      successCriteria: _stringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      constraints: _stringList(json['constraints']),
      nonGoals: _stringList(json['nonGoals'] ?? json['non_goals']),
      assumptions: _stringList(json['assumptions']),
      clarifyingQuestions: _mapList(
        json['clarifyingQuestions'] ?? json['clarifying_questions'],
      ).map(ClarifyingQuestion.fromJson).toList(),
      recommendedMode: parseExecutionMode(
        json['recommendedMode'] ?? json['recommended_mode'],
      ),
      recommendedAutonomy: parseAutonomyLevel(
        json['recommendedAutonomy'] ?? json['recommended_autonomy'],
      ),
      requiredOutputs: _mapList(
        json['requiredOutputs'] ?? json['required_outputs'],
      ).map(RequiredOutput.fromJson).toList(),
      domain: parseJobDomain(json['domain']),
      riskLevel: parseRiskLevel(json['riskLevel'] ?? json['risk_level']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'title': title,
    'originalPrompt': originalPrompt,
    'objective': objective,
    'successCriteria': successCriteria,
    'constraints': constraints,
    'nonGoals': nonGoals,
    'assumptions': assumptions,
    'clarifyingQuestions': clarifyingQuestions.map((q) => q.toJson()).toList(),
    'recommendedMode': recommendedMode.wire,
    'recommendedAutonomy': recommendedAutonomy.wire,
    'requiredOutputs': requiredOutputs.map((o) => o.toJson()).toList(),
    'domain': domain.wire,
    'riskLevel': riskLevel.wire,
  };
}

class ClarifyingQuestion {
  final String id;
  final String question;
  final bool required;
  final String? defaultAssumption;
  final String? impactIfUnanswered;
  final String? answer;

  const ClarifyingQuestion({
    required this.id,
    required this.question,
    required this.required,
    this.defaultAssumption,
    this.impactIfUnanswered,
    this.answer,
  });

  ClarifyingQuestion copyWith({
    String? id,
    String? question,
    bool? required,
    Object? defaultAssumption = _sentinel,
    Object? impactIfUnanswered = _sentinel,
    Object? answer = _sentinel,
  }) {
    return ClarifyingQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      required: required ?? this.required,
      defaultAssumption: identical(defaultAssumption, _sentinel)
          ? this.defaultAssumption
          : defaultAssumption as String?,
      impactIfUnanswered: identical(impactIfUnanswered, _sentinel)
          ? this.impactIfUnanswered
          : impactIfUnanswered as String?,
      answer: identical(answer, _sentinel) ? this.answer : answer as String?,
    );
  }

  factory ClarifyingQuestion.fromJson(Map<String, dynamic> json) {
    return ClarifyingQuestion(
      id: _string(json['id']),
      question: _string(json['question']),
      required: _bool(json['required']),
      defaultAssumption: _nullableString(
        json['defaultAssumption'] ?? json['default_assumption'],
      ),
      impactIfUnanswered: _nullableString(
        json['impactIfUnanswered'] ?? json['impact_if_unanswered'],
      ),
      answer: _nullableString(json['answer']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'required': required,
    if (defaultAssumption != null) 'defaultAssumption': defaultAssumption,
    if (impactIfUnanswered != null) 'impactIfUnanswered': impactIfUnanswered,
    if (answer != null) 'answer': answer,
  };
}

class RequiredOutput {
  final String path;
  final String? description;
  final bool required;

  const RequiredOutput({
    required this.path,
    this.description,
    this.required = true,
  });

  factory RequiredOutput.fromJson(Map<String, dynamic> json) {
    return RequiredOutput(
      path: _string(json['path']),
      description: _nullableString(json['description']),
      required: _bool(json['required'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    if (description != null) 'description': description,
    'required': required,
  };
}

class JobSpec {
  final int version;
  final String id;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String taskBriefId;
  final JobStatus status;
  final JobDomain domain;
  final AutonomyLevel autonomy;
  final String? promptPresetId;
  final List<String> promptModules;
  final List<String> globalConstraints;
  final List<String> globalSuccessCriteria;
  final ToolPolicy toolPolicy;
  final StopPolicy stopPolicy;
  final List<JobPhase> phases;

  const JobSpec({
    required this.version,
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.taskBriefId,
    required this.status,
    required this.domain,
    required this.autonomy,
    required this.globalConstraints,
    required this.globalSuccessCriteria,
    required this.toolPolicy,
    required this.stopPolicy,
    required this.phases,
    this.description,
    this.promptPresetId,
    this.promptModules = const [],
  });

  JobSpec copyWith({
    int? version,
    String? id,
    String? title,
    Object? description = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? taskBriefId,
    JobStatus? status,
    JobDomain? domain,
    AutonomyLevel? autonomy,
    Object? promptPresetId = _sentinel,
    List<String>? promptModules,
    List<String>? globalConstraints,
    List<String>? globalSuccessCriteria,
    ToolPolicy? toolPolicy,
    StopPolicy? stopPolicy,
    List<JobPhase>? phases,
  }) {
    return JobSpec(
      version: version ?? this.version,
      id: id ?? this.id,
      title: title ?? this.title,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      taskBriefId: taskBriefId ?? this.taskBriefId,
      status: status ?? this.status,
      domain: domain ?? this.domain,
      autonomy: autonomy ?? this.autonomy,
      promptPresetId: identical(promptPresetId, _sentinel)
          ? this.promptPresetId
          : promptPresetId as String?,
      promptModules: promptModules ?? this.promptModules,
      globalConstraints: globalConstraints ?? this.globalConstraints,
      globalSuccessCriteria:
          globalSuccessCriteria ?? this.globalSuccessCriteria,
      toolPolicy: toolPolicy ?? this.toolPolicy,
      stopPolicy: stopPolicy ?? this.stopPolicy,
      phases: phases ?? this.phases,
    );
  }

  factory JobSpec.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return JobSpec(
      version: _int(json['version'], fallback: 1),
      id: _string(json['id']),
      title: _string(json['title'], fallback: 'Untitled job'),
      description: _nullableString(json['description']),
      createdAt: _date(json['createdAt'] ?? json['created_at'], fallback: now),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at'], fallback: now),
      taskBriefId: _string(json['taskBriefId'] ?? json['task_brief_id']),
      status: parseJobStatus(json['status']),
      domain: parseJobDomain(json['domain']),
      autonomy: parseAutonomyLevel(json['autonomy']),
      promptPresetId: _nullableString(
        json['promptPresetId'] ?? json['prompt_preset_id'],
      ),
      promptModules: _stringList(
        json['promptModules'] ?? json['prompt_modules'],
      ),
      globalConstraints: _stringList(
        json['globalConstraints'] ??
            json['constraints'] ??
            json['global_constraints'],
      ),
      globalSuccessCriteria: _stringList(
        json['globalSuccessCriteria'] ??
            json['successCriteria'] ??
            json['global_success_criteria'],
      ),
      toolPolicy: ToolPolicy.fromJson(
        _map(json['toolPolicy'] ?? json['tool_policy']),
      ),
      stopPolicy: StopPolicy.fromJson(
        _map(json['stopPolicy'] ?? json['stop_policy']),
      ),
      phases: _mapList(json['phases']).map(JobPhase.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'taskBriefId': taskBriefId,
    'status': status.wire,
    'domain': domain.wire,
    'autonomy': autonomy.wire,
    if (promptPresetId != null) 'promptPresetId': promptPresetId,
    'promptModules': promptModules,
    'globalConstraints': globalConstraints,
    'globalSuccessCriteria': globalSuccessCriteria,
    'toolPolicy': toolPolicy.toJson(),
    'stopPolicy': stopPolicy.toJson(),
    'phases': phases.map((phase) => phase.toJson()).toList(),
  };
}

class ToolPolicy {
  final List<String> defaultAllowed;
  final List<String> defaultDisallowed;
  final TerminalToolPolicy? terminal;

  const ToolPolicy({
    this.defaultAllowed = const [],
    this.defaultDisallowed = const [],
    this.terminal,
  });

  factory ToolPolicy.fromJson(Map<String, dynamic> json) {
    return ToolPolicy(
      defaultAllowed: _stringList(
        json['defaultAllowed'] ?? json['default_allowed'],
      ),
      defaultDisallowed: _stringList(
        json['defaultDisallowed'] ?? json['default_disallowed'],
      ),
      terminal: json['terminal'] == null
          ? null
          : TerminalToolPolicy.fromJson(_map(json['terminal'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'defaultAllowed': defaultAllowed,
    'defaultDisallowed': defaultDisallowed,
    if (terminal != null) 'terminal': terminal!.toJson(),
  };
}

class TerminalToolPolicy {
  final bool allowed;
  final TerminalPolicy policy;
  final List<String> allowedCommands;
  final List<String> deniedCommands;

  const TerminalToolPolicy({
    required this.allowed,
    required this.policy,
    this.allowedCommands = const [],
    this.deniedCommands = const [],
  });

  factory TerminalToolPolicy.fromJson(Map<String, dynamic> json) {
    return TerminalToolPolicy(
      allowed: _bool(json['allowed']),
      policy: parseTerminalPolicy(json['policy']),
      allowedCommands: _stringList(
        json['allowedCommands'] ?? json['allowed_commands'],
      ),
      deniedCommands: _stringList(
        json['deniedCommands'] ?? json['denied_commands'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'allowed': allowed,
    'policy': policy.wire,
    'allowedCommands': allowedCommands,
    'deniedCommands': deniedCommands,
  };
}

class StopPolicy {
  final int? maxTotalPhases;
  final int? maxPhaseTerminalCommands;
  final int? maxPhaseFilesRead;
  final int? maxPhaseRetries;
  final int? maxRuntimeSeconds;
  final bool? stopOnRequiredQuestion;
  final bool? stopOnLowConfidence;

  const StopPolicy({
    this.maxTotalPhases,
    this.maxPhaseTerminalCommands,
    this.maxPhaseFilesRead,
    this.maxPhaseRetries,
    this.maxRuntimeSeconds,
    this.stopOnRequiredQuestion,
    this.stopOnLowConfidence,
  });

  factory StopPolicy.fromJson(Map<String, dynamic> json) {
    return StopPolicy(
      maxTotalPhases: _nullableInt(
        json['maxTotalPhases'] ?? json['max_total_phases'],
      ),
      maxPhaseTerminalCommands: _nullableInt(
        json['maxPhaseTerminalCommands'] ?? json['max_phase_terminal_commands'],
      ),
      maxPhaseFilesRead: _nullableInt(
        json['maxPhaseFilesRead'] ?? json['max_phase_files_read'],
      ),
      maxPhaseRetries: _nullableInt(
        json['maxPhaseRetries'] ?? json['max_phase_retries'],
      ),
      maxRuntimeSeconds: _nullableInt(
        json['maxRuntimeSeconds'] ?? json['max_runtime_seconds'],
      ),
      stopOnRequiredQuestion: _nullableBool(
        json['stopOnRequiredQuestion'] ?? json['stop_on_required_question'],
      ),
      stopOnLowConfidence: _nullableBool(
        json['stopOnLowConfidence'] ?? json['stop_on_low_confidence'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    if (maxTotalPhases != null) 'maxTotalPhases': maxTotalPhases,
    if (maxPhaseTerminalCommands != null)
      'maxPhaseTerminalCommands': maxPhaseTerminalCommands,
    if (maxPhaseFilesRead != null) 'maxPhaseFilesRead': maxPhaseFilesRead,
    if (maxPhaseRetries != null) 'maxPhaseRetries': maxPhaseRetries,
    if (maxRuntimeSeconds != null) 'maxRuntimeSeconds': maxRuntimeSeconds,
    if (stopOnRequiredQuestion != null)
      'stopOnRequiredQuestion': stopOnRequiredQuestion,
    if (stopOnLowConfidence != null) 'stopOnLowConfidence': stopOnLowConfidence,
  };
}

class JobPhase {
  final String id;
  final String title;
  final String objective;
  final PhaseStatus status;
  final List<PhaseInput> inputs;
  final List<PhaseOutput> expectedOutputs;
  final List<String> allowedTools;
  final List<String> disallowedTools;
  final TerminalPolicy terminalPolicy;
  final List<String> promptModules;
  final List<String> instructions;
  final List<String> completionCriteria;
  final PhaseValidation? validation;
  final ReviewPolicy review;
  final bool humanCheckpoint;
  final StopPolicy? stopPolicy;
  final RetryPolicy? retryPolicy;

  const JobPhase({
    required this.id,
    required this.title,
    required this.objective,
    required this.status,
    required this.inputs,
    required this.expectedOutputs,
    required this.allowedTools,
    required this.terminalPolicy,
    required this.completionCriteria,
    required this.review,
    required this.humanCheckpoint,
    this.disallowedTools = const [],
    this.promptModules = const [],
    this.instructions = const [],
    this.validation,
    this.stopPolicy,
    this.retryPolicy,
  });

  JobPhase copyWith({
    String? id,
    String? title,
    String? objective,
    PhaseStatus? status,
    List<PhaseInput>? inputs,
    List<PhaseOutput>? expectedOutputs,
    List<String>? allowedTools,
    List<String>? disallowedTools,
    TerminalPolicy? terminalPolicy,
    List<String>? promptModules,
    List<String>? instructions,
    List<String>? completionCriteria,
    Object? validation = _sentinel,
    ReviewPolicy? review,
    bool? humanCheckpoint,
    Object? stopPolicy = _sentinel,
    Object? retryPolicy = _sentinel,
  }) {
    return JobPhase(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      status: status ?? this.status,
      inputs: inputs ?? this.inputs,
      expectedOutputs: expectedOutputs ?? this.expectedOutputs,
      allowedTools: allowedTools ?? this.allowedTools,
      disallowedTools: disallowedTools ?? this.disallowedTools,
      terminalPolicy: terminalPolicy ?? this.terminalPolicy,
      promptModules: promptModules ?? this.promptModules,
      instructions: instructions ?? this.instructions,
      completionCriteria: completionCriteria ?? this.completionCriteria,
      validation: identical(validation, _sentinel)
          ? this.validation
          : validation as PhaseValidation?,
      review: review ?? this.review,
      humanCheckpoint: humanCheckpoint ?? this.humanCheckpoint,
      stopPolicy: identical(stopPolicy, _sentinel)
          ? this.stopPolicy
          : stopPolicy as StopPolicy?,
      retryPolicy: identical(retryPolicy, _sentinel)
          ? this.retryPolicy
          : retryPolicy as RetryPolicy?,
    );
  }

  factory JobPhase.fromJson(Map<String, dynamic> json) {
    return JobPhase(
      id: _string(json['id']),
      title: _string(json['title'], fallback: 'Untitled phase'),
      objective: _string(json['objective']),
      status: parsePhaseStatus(json['status']),
      inputs: _mapList(json['inputs']).map(PhaseInput.fromJson).toList(),
      expectedOutputs: _mapList(
        json['expectedOutputs'] ?? json['outputs'] ?? json['expected_outputs'],
      ).map(PhaseOutput.fromJson).toList(),
      allowedTools: _stringList(json['allowedTools'] ?? json['allowed_tools']),
      disallowedTools: _stringList(
        json['disallowedTools'] ?? json['disallowed_tools'],
      ),
      terminalPolicy: parseTerminalPolicy(
        json['terminalPolicy'] ?? json['terminal_policy'],
      ),
      promptModules: _stringList(
        json['promptModules'] ?? json['prompt_modules'],
      ),
      instructions: _stringList(json['instructions']),
      completionCriteria: _stringList(
        json['completionCriteria'] ?? json['completion_criteria'],
      ),
      validation: json['validation'] == null
          ? null
          : PhaseValidation.fromJson(_map(json['validation'])),
      review: ReviewPolicy.fromJson(_map(json['review'])),
      humanCheckpoint: _bool(
        json['humanCheckpoint'] ?? json['human_checkpoint'],
      ),
      stopPolicy: json['stopPolicy'] == null && json['stop_policy'] == null
          ? null
          : StopPolicy.fromJson(
              _map(json['stopPolicy'] ?? json['stop_policy']),
            ),
      retryPolicy: json['retryPolicy'] == null && json['retry_policy'] == null
          ? null
          : RetryPolicy.fromJson(
              _map(json['retryPolicy'] ?? json['retry_policy']),
            ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'objective': objective,
    'status': status.wire,
    'inputs': inputs.map((input) => input.toJson()).toList(),
    'expectedOutputs': expectedOutputs
        .map((output) => output.toJson())
        .toList(),
    'allowedTools': allowedTools,
    'disallowedTools': disallowedTools,
    'terminalPolicy': terminalPolicy.wire,
    'promptModules': promptModules,
    'instructions': instructions,
    'completionCriteria': completionCriteria,
    if (validation != null) 'validation': validation!.toJson(),
    'review': review.toJson(),
    'humanCheckpoint': humanCheckpoint,
    if (stopPolicy != null) 'stopPolicy': stopPolicy!.toJson(),
    if (retryPolicy != null) 'retryPolicy': retryPolicy!.toJson(),
  };
}

class PhaseInput {
  final String path;
  final bool required;
  final String? description;

  const PhaseInput({
    required this.path,
    required this.required,
    this.description,
  });

  factory PhaseInput.fromJson(Map<String, dynamic> json) {
    return PhaseInput(
      path: _string(json['path']),
      required: _bool(json['required'], fallback: true),
      description: _nullableString(json['description']),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'required': required,
    if (description != null) 'description': description,
  };
}

class PhaseOutput {
  final String path;
  final bool required;
  final String? description;
  final ArtifactFormat? format;

  const PhaseOutput({
    required this.path,
    required this.required,
    this.description,
    this.format,
  });

  factory PhaseOutput.fromJson(Map<String, dynamic> json) {
    return PhaseOutput(
      path: _string(json['path']),
      required: _bool(json['required'], fallback: true),
      description: _nullableString(json['description']),
      format: parseArtifactFormat(json['format']),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'required': required,
    if (description != null) 'description': description,
    if (format != null) 'format': format!.wire,
  };
}

class PhaseValidation {
  final List<String> requiredSections;
  final List<String> requiredPatterns;
  final List<String> forbiddenPatterns;
  final List<String> mustExist;
  final List<String> mustNotModify;

  const PhaseValidation({
    this.requiredSections = const [],
    this.requiredPatterns = const [],
    this.forbiddenPatterns = const [],
    this.mustExist = const [],
    this.mustNotModify = const [],
  });

  factory PhaseValidation.fromJson(Map<String, dynamic> json) {
    return PhaseValidation(
      requiredSections: _stringList(
        json['requiredSections'] ?? json['required_sections'],
      ),
      requiredPatterns: _stringList(
        json['requiredPatterns'] ?? json['required_patterns'],
      ),
      forbiddenPatterns: _stringList(
        json['forbiddenPatterns'] ?? json['forbidden_patterns'],
      ),
      mustExist: _stringList(json['mustExist'] ?? json['must_exist']),
      mustNotModify: _stringList(
        json['mustNotModify'] ?? json['must_not_modify'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'requiredSections': requiredSections,
    'requiredPatterns': requiredPatterns,
    'forbiddenPatterns': forbiddenPatterns,
    'mustExist': mustExist,
    'mustNotModify': mustNotModify,
  };
}

class ReviewPolicy {
  final bool required;
  final ReviewerType reviewer;
  final List<String> criteria;

  const ReviewPolicy({
    required this.required,
    required this.reviewer,
    this.criteria = const [],
  });

  factory ReviewPolicy.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) {
      return const ReviewPolicy(required: true, reviewer: ReviewerType.hybrid);
    }
    return ReviewPolicy(
      required: _bool(json['required'], fallback: true),
      reviewer: parseReviewerType(json['reviewer']),
      criteria: _stringList(json['criteria']),
    );
  }

  Map<String, dynamic> toJson() => {
    'required': required,
    'reviewer': reviewer.wire,
    'criteria': criteria,
  };
}

class RetryPolicy {
  final int maxRetries;
  final bool retryOnReviewFailure;
  final bool retryOnMissingOutput;

  const RetryPolicy({
    this.maxRetries = 1,
    this.retryOnReviewFailure = true,
    this.retryOnMissingOutput = true,
  });

  factory RetryPolicy.fromJson(Map<String, dynamic> json) {
    return RetryPolicy(
      maxRetries: _int(json['maxRetries'] ?? json['max_retries'], fallback: 1),
      retryOnReviewFailure: _bool(
        json['retryOnReviewFailure'] ?? json['retry_on_review_failure'],
        fallback: true,
      ),
      retryOnMissingOutput: _bool(
        json['retryOnMissingOutput'] ?? json['retry_on_missing_output'],
        fallback: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'maxRetries': maxRetries,
    'retryOnReviewFailure': retryOnReviewFailure,
    'retryOnMissingOutput': retryOnMissingOutput,
  };
}

class JobTemplate {
  final String id;
  final String name;
  final JobDomain domain;
  final String description;
  final List<String> requiredInputs;
  final AutonomyLevel defaultAutonomy;
  final List<JobPhase> phases;
  final List<String> defaultConstraints;
  final List<String> defaultSuccessCriteria;
  final List<String> recommendedPromptModules;

  const JobTemplate({
    required this.id,
    required this.name,
    required this.domain,
    required this.description,
    required this.defaultAutonomy,
    required this.phases,
    this.requiredInputs = const [],
    this.defaultConstraints = const [],
    this.defaultSuccessCriteria = const [],
    this.recommendedPromptModules = const [],
  });

  factory JobTemplate.fromJson(Map<String, dynamic> json) {
    return JobTemplate(
      id: _string(json['id']),
      name: _string(json['name']),
      domain: parseJobDomain(json['domain']),
      description: _string(json['description']),
      requiredInputs: _stringList(
        json['requiredInputs'] ?? json['required_inputs'],
      ),
      defaultAutonomy: parseAutonomyLevel(
        json['defaultAutonomy'] ?? json['default_autonomy'],
      ),
      phases: _mapList(json['phases']).map(JobPhase.fromJson).toList(),
      defaultConstraints: _stringList(
        json['defaultConstraints'] ?? json['default_constraints'],
      ),
      defaultSuccessCriteria: _stringList(
        json['defaultSuccessCriteria'] ?? json['default_success_criteria'],
      ),
      recommendedPromptModules: _stringList(
        json['recommendedPromptModules'] ?? json['recommended_prompt_modules'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'domain': domain.wire,
    'description': description,
    'requiredInputs': requiredInputs,
    'defaultAutonomy': defaultAutonomy.wire,
    'phases': phases.map((phase) => phase.toJson()).toList(),
    'defaultConstraints': defaultConstraints,
    'defaultSuccessCriteria': defaultSuccessCriteria,
    'recommendedPromptModules': recommendedPromptModules,
  };
}

class JobState {
  final String jobId;
  final String? chatSessionId;
  final JobStatus status;
  final String? currentPhaseId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime updatedAt;
  final List<String> completedPhases;
  final List<String> failedPhases;
  final List<String> skippedPhases;
  final List<JobArtifact> artifacts;
  final List<OpenQuestion> openQuestions;
  final List<PendingFileApproval> pendingApprovals;
  final List<String> assumptions;
  final List<String> risks;
  final List<PhaseRun> phaseRuns;
  final String latestSummary;

  const JobState({
    required this.jobId,
    required this.status,
    required this.updatedAt,
    required this.completedPhases,
    required this.failedPhases,
    required this.skippedPhases,
    required this.artifacts,
    required this.openQuestions,
    required this.assumptions,
    required this.risks,
    required this.phaseRuns,
    required this.latestSummary,
    this.chatSessionId,
    this.currentPhaseId,
    this.startedAt,
    this.completedAt,
    this.pendingApprovals = const [],
  });

  JobState copyWith({
    String? jobId,
    Object? chatSessionId = _sentinel,
    JobStatus? status,
    Object? currentPhaseId = _sentinel,
    Object? startedAt = _sentinel,
    Object? completedAt = _sentinel,
    DateTime? updatedAt,
    List<String>? completedPhases,
    List<String>? failedPhases,
    List<String>? skippedPhases,
    List<JobArtifact>? artifacts,
    List<OpenQuestion>? openQuestions,
    List<PendingFileApproval>? pendingApprovals,
    List<String>? assumptions,
    List<String>? risks,
    List<PhaseRun>? phaseRuns,
    String? latestSummary,
  }) {
    return JobState(
      jobId: jobId ?? this.jobId,
      chatSessionId: identical(chatSessionId, _sentinel)
          ? this.chatSessionId
          : chatSessionId as String?,
      status: status ?? this.status,
      currentPhaseId: identical(currentPhaseId, _sentinel)
          ? this.currentPhaseId
          : currentPhaseId as String?,
      startedAt: identical(startedAt, _sentinel)
          ? this.startedAt
          : startedAt as DateTime?,
      completedAt: identical(completedAt, _sentinel)
          ? this.completedAt
          : completedAt as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
      completedPhases: completedPhases ?? this.completedPhases,
      failedPhases: failedPhases ?? this.failedPhases,
      skippedPhases: skippedPhases ?? this.skippedPhases,
      artifacts: artifacts ?? this.artifacts,
      openQuestions: openQuestions ?? this.openQuestions,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
      assumptions: assumptions ?? this.assumptions,
      risks: risks ?? this.risks,
      phaseRuns: phaseRuns ?? this.phaseRuns,
      latestSummary: latestSummary ?? this.latestSummary,
    );
  }

  factory JobState.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return JobState(
      jobId: _string(json['jobId'] ?? json['job_id']),
      chatSessionId: _nullableString(
        json['chatSessionId'] ?? json['chat_session_id'],
      ),
      status: parseJobStatus(json['status']),
      currentPhaseId: _nullableString(
        json['currentPhaseId'] ?? json['current_phase_id'],
      ),
      startedAt: _nullableDate(json['startedAt'] ?? json['started_at']),
      completedAt: _nullableDate(json['completedAt'] ?? json['completed_at']),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at'], fallback: now),
      completedPhases: _stringList(
        json['completedPhases'] ?? json['completed_phases'],
      ),
      failedPhases: _stringList(json['failedPhases'] ?? json['failed_phases']),
      skippedPhases: _stringList(
        json['skippedPhases'] ?? json['skipped_phases'],
      ),
      artifacts: _mapList(json['artifacts']).map(JobArtifact.fromJson).toList(),
      openQuestions: _mapList(
        json['openQuestions'] ?? json['open_questions'],
      ).map(OpenQuestion.fromJson).toList(),
      pendingApprovals: _mapList(
        json['pendingApprovals'] ?? json['pending_approvals'],
      ).map(PendingFileApproval.fromJson).toList(),
      assumptions: _stringList(json['assumptions']),
      risks: _stringList(json['risks']),
      phaseRuns: _mapList(
        json['phaseRuns'] ?? json['phase_runs'],
      ).map(PhaseRun.fromJson).toList(),
      latestSummary: _string(json['latestSummary'] ?? json['latest_summary']),
    );
  }

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    if (chatSessionId != null) 'chatSessionId': chatSessionId,
    'status': status.wire,
    if (currentPhaseId != null) 'currentPhaseId': currentPhaseId,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'completedPhases': completedPhases,
    'failedPhases': failedPhases,
    'skippedPhases': skippedPhases,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'openQuestions': openQuestions
        .map((question) => question.toJson())
        .toList(),
    if (pendingApprovals.isNotEmpty)
      'pendingApprovals': pendingApprovals
          .map((approval) => approval.toJson())
          .toList(),
    'assumptions': assumptions,
    'risks': risks,
    'phaseRuns': phaseRuns.map((run) => run.toJson()).toList(),
    'latestSummary': latestSummary,
  };
}

class JobArtifact {
  final String path;
  final String producedByPhaseId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? description;

  const JobArtifact({
    required this.path,
    required this.producedByPhaseId,
    required this.createdAt,
    this.updatedAt,
    this.description,
  });

  factory JobArtifact.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return JobArtifact(
      path: _string(json['path']),
      producedByPhaseId: _string(
        json['producedByPhaseId'] ?? json['produced_by_phase_id'],
      ),
      createdAt: _date(json['createdAt'] ?? json['created_at'], fallback: now),
      updatedAt: _nullableDate(json['updatedAt'] ?? json['updated_at']),
      description: _nullableString(json['description']),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'producedByPhaseId': producedByPhaseId,
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (description != null) 'description': description,
  };
}

class OpenQuestion {
  final String id;
  final String? phaseId;
  final String question;
  final bool required;
  final String? reason;
  final OpenQuestionStatus status;
  final String? answer;

  const OpenQuestion({
    required this.id,
    required this.question,
    required this.required,
    required this.status,
    this.phaseId,
    this.reason,
    this.answer,
  });

  factory OpenQuestion.fromJson(Map<String, dynamic> json) {
    return OpenQuestion(
      id: _string(json['id']),
      phaseId: _nullableString(json['phaseId'] ?? json['phase_id']),
      question: _string(json['question']),
      required: _bool(json['required']),
      reason: _nullableString(json['reason']),
      status: parseOpenQuestionStatus(json['status']),
      answer: _nullableString(json['answer']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (phaseId != null) 'phaseId': phaseId,
    'question': question,
    'required': required,
    if (reason != null) 'reason': reason,
    'status': status.wire,
    if (answer != null) 'answer': answer,
  };
}

class FileChangeSummary {
  final String path;
  final String changeType;
  final String toolName;
  final int addedLines;
  final int removedLines;
  final String? diff;
  final String? summary;

  const FileChangeSummary({
    required this.path,
    required this.changeType,
    required this.toolName,
    required this.addedLines,
    required this.removedLines,
    this.diff,
    this.summary,
  });

  factory FileChangeSummary.fromJson(Map<String, dynamic> json) {
    return FileChangeSummary(
      path: _string(json['path']),
      changeType: _string(json['changeType'] ?? json['change_type']),
      toolName: _string(json['toolName'] ?? json['tool_name']),
      addedLines: _int(json['addedLines'] ?? json['added_lines']),
      removedLines: _int(json['removedLines'] ?? json['removed_lines']),
      diff: _nullableString(json['diff']),
      summary: _nullableString(json['summary']),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'changeType': changeType,
    'toolName': toolName,
    'addedLines': addedLines,
    'removedLines': removedLines,
    if (diff != null) 'diff': diff,
    if (summary != null) 'summary': summary,
  };
}

class PendingFileApproval {
  final String id;
  final String phaseId;
  final String runId;
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String path;
  final String? sourcePath;
  final String changeType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<FileApprovalHunk> hunks;
  final String? summary;

  const PendingFileApproval({
    required this.id,
    required this.phaseId,
    required this.runId,
    required this.toolCallId,
    required this.toolName,
    required this.arguments,
    required this.path,
    required this.changeType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.hunks,
    this.sourcePath,
    this.summary,
  });

  PendingFileApproval copyWith({
    String? id,
    String? phaseId,
    String? runId,
    String? toolCallId,
    String? toolName,
    Map<String, dynamic>? arguments,
    String? path,
    Object? sourcePath = _sentinel,
    String? changeType,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<FileApprovalHunk>? hunks,
    Object? summary = _sentinel,
  }) {
    return PendingFileApproval(
      id: id ?? this.id,
      phaseId: phaseId ?? this.phaseId,
      runId: runId ?? this.runId,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      path: path ?? this.path,
      sourcePath: identical(sourcePath, _sentinel)
          ? this.sourcePath
          : sourcePath as String?,
      changeType: changeType ?? this.changeType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hunks: hunks ?? this.hunks,
      summary: identical(summary, _sentinel)
          ? this.summary
          : summary as String?,
    );
  }

  factory PendingFileApproval.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PendingFileApproval(
      id: _string(json['id']),
      phaseId: _string(json['phaseId'] ?? json['phase_id']),
      runId: _string(json['runId'] ?? json['run_id']),
      toolCallId: _string(json['toolCallId'] ?? json['tool_call_id']),
      toolName: _string(json['toolName'] ?? json['tool_name']),
      arguments: _map(json['arguments']),
      path: _string(json['path']),
      sourcePath: _nullableString(json['sourcePath'] ?? json['source_path']),
      changeType: _string(json['changeType'] ?? json['change_type']),
      status: _string(json['status'], fallback: 'pending'),
      createdAt: _date(json['createdAt'] ?? json['created_at'], fallback: now),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at'], fallback: now),
      hunks: _mapList(json['hunks']).map(FileApprovalHunk.fromJson).toList(),
      summary: _nullableString(json['summary']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phaseId': phaseId,
    'runId': runId,
    'toolCallId': toolCallId,
    'toolName': toolName,
    'arguments': arguments,
    'path': path,
    if (sourcePath != null) 'sourcePath': sourcePath,
    'changeType': changeType,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'hunks': hunks.map((hunk) => hunk.toJson()).toList(),
    if (summary != null) 'summary': summary,
  };
}

class FileApprovalHunk {
  final String id;
  final String status;
  final int oldStart;
  final int newStart;
  final List<String> oldLines;
  final List<String> newLines;
  final String diff;
  final String? summary;

  const FileApprovalHunk({
    required this.id,
    required this.status,
    required this.oldStart,
    required this.newStart,
    required this.oldLines,
    required this.newLines,
    required this.diff,
    this.summary,
  });

  FileApprovalHunk copyWith({
    String? id,
    String? status,
    int? oldStart,
    int? newStart,
    List<String>? oldLines,
    List<String>? newLines,
    String? diff,
    Object? summary = _sentinel,
  }) {
    return FileApprovalHunk(
      id: id ?? this.id,
      status: status ?? this.status,
      oldStart: oldStart ?? this.oldStart,
      newStart: newStart ?? this.newStart,
      oldLines: oldLines ?? this.oldLines,
      newLines: newLines ?? this.newLines,
      diff: diff ?? this.diff,
      summary: identical(summary, _sentinel)
          ? this.summary
          : summary as String?,
    );
  }

  factory FileApprovalHunk.fromJson(Map<String, dynamic> json) {
    return FileApprovalHunk(
      id: _string(json['id']),
      status: _string(json['status'], fallback: 'pending'),
      oldStart: _int(json['oldStart'] ?? json['old_start']),
      newStart: _int(json['newStart'] ?? json['new_start']),
      oldLines: _rawStringList(json['oldLines'] ?? json['old_lines']),
      newLines: _rawStringList(json['newLines'] ?? json['new_lines']),
      diff: _string(json['diff']),
      summary: _nullableString(json['summary']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'oldStart': oldStart,
    'newStart': newStart,
    'oldLines': oldLines,
    'newLines': newLines,
    'diff': diff,
    if (summary != null) 'summary': summary,
  };
}

class PhaseRun {
  final String phaseId;
  final String runId;
  final PhaseRunStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<ToolCallRecord> toolCalls;
  final List<String> filesRead;
  final List<String> filesWritten;
  final List<String> filesPatched;
  final List<FileChangeSummary> fileChanges;
  final List<String> terminalCommands;
  final String summary;
  final ReviewResult? reviewResult;
  final String? error;

  const PhaseRun({
    required this.phaseId,
    required this.runId,
    required this.status,
    required this.startedAt,
    required this.toolCalls,
    required this.filesRead,
    required this.filesWritten,
    required this.filesPatched,
    required this.terminalCommands,
    required this.summary,
    this.fileChanges = const [],
    this.completedAt,
    this.reviewResult,
    this.error,
  });

  PhaseRun copyWith({
    String? phaseId,
    String? runId,
    PhaseRunStatus? status,
    DateTime? startedAt,
    Object? completedAt = _sentinel,
    List<ToolCallRecord>? toolCalls,
    List<String>? filesRead,
    List<String>? filesWritten,
    List<String>? filesPatched,
    List<FileChangeSummary>? fileChanges,
    List<String>? terminalCommands,
    String? summary,
    Object? reviewResult = _sentinel,
    Object? error = _sentinel,
  }) {
    return PhaseRun(
      phaseId: phaseId ?? this.phaseId,
      runId: runId ?? this.runId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: identical(completedAt, _sentinel)
          ? this.completedAt
          : completedAt as DateTime?,
      toolCalls: toolCalls ?? this.toolCalls,
      filesRead: filesRead ?? this.filesRead,
      filesWritten: filesWritten ?? this.filesWritten,
      filesPatched: filesPatched ?? this.filesPatched,
      fileChanges: fileChanges ?? this.fileChanges,
      terminalCommands: terminalCommands ?? this.terminalCommands,
      summary: summary ?? this.summary,
      reviewResult: identical(reviewResult, _sentinel)
          ? this.reviewResult
          : reviewResult as ReviewResult?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  factory PhaseRun.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return PhaseRun(
      phaseId: _string(json['phaseId'] ?? json['phase_id']),
      runId: _string(json['runId'] ?? json['run_id']),
      status: parsePhaseRunStatus(json['status']),
      startedAt: _date(json['startedAt'] ?? json['started_at'], fallback: now),
      completedAt: _nullableDate(json['completedAt'] ?? json['completed_at']),
      toolCalls: _mapList(
        json['toolCalls'] ?? json['tool_calls'],
      ).map(ToolCallRecord.fromJson).toList(),
      filesRead: _stringList(json['filesRead'] ?? json['files_read']),
      filesWritten: _stringList(json['filesWritten'] ?? json['files_written']),
      filesPatched: _stringList(json['filesPatched'] ?? json['files_patched']),
      fileChanges: _mapList(
        json['fileChanges'] ?? json['file_changes'],
      ).map(FileChangeSummary.fromJson).toList(),
      terminalCommands: _stringList(
        json['terminalCommands'] ?? json['terminal_commands'],
      ),
      summary: _string(json['summary']),
      reviewResult:
          json['reviewResult'] == null && json['review_result'] == null
          ? null
          : ReviewResult.fromJson(
              _map(json['reviewResult'] ?? json['review_result']),
            ),
      error: _nullableString(json['error']),
    );
  }

  Map<String, dynamic> toJson() => {
    'phaseId': phaseId,
    'runId': runId,
    'status': status.wire,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    'filesRead': filesRead,
    'filesWritten': filesWritten,
    'filesPatched': filesPatched,
    if (fileChanges.isNotEmpty)
      'fileChanges': fileChanges.map((change) => change.toJson()).toList(),
    'terminalCommands': terminalCommands,
    'summary': summary,
    if (reviewResult != null) 'reviewResult': reviewResult!.toJson(),
    if (error != null) 'error': error,
  };
}

class ToolCallRecord {
  final String id;
  final String jobId;
  final String phaseId;
  final String runId;
  final String toolName;
  final Object? arguments;
  final String? resultSummary;
  final String? error;
  final DateTime timestamp;

  const ToolCallRecord({
    required this.id,
    required this.jobId,
    required this.phaseId,
    required this.runId,
    required this.toolName,
    required this.timestamp,
    this.arguments,
    this.resultSummary,
    this.error,
  });

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) {
    return ToolCallRecord(
      id: _string(json['id']),
      jobId: _string(json['jobId'] ?? json['job_id']),
      phaseId: _string(json['phaseId'] ?? json['phase_id']),
      runId: _string(json['runId'] ?? json['run_id']),
      toolName: _string(json['toolName'] ?? json['tool_name']),
      arguments: json['arguments'],
      resultSummary: _nullableString(
        json['resultSummary'] ?? json['result_summary'],
      ),
      error: _nullableString(json['error']),
      timestamp: _date(json['timestamp'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'phaseId': phaseId,
    'runId': runId,
    'toolName': toolName,
    if (arguments != null) 'arguments': arguments,
    if (resultSummary != null) 'resultSummary': resultSummary,
    if (error != null) 'error': error,
    'timestamp': timestamp.toIso8601String(),
  };
}

class ReviewResult {
  final String phaseId;
  final ReviewStatus status;
  final List<DeterministicCheckResult> deterministicChecks;
  final ModelReviewResult? modelReview;
  final String summary;
  final List<ReviewIssue> issues;
  final ReviewRecommendation recommendation;

  const ReviewResult({
    required this.phaseId,
    required this.status,
    required this.deterministicChecks,
    required this.summary,
    required this.issues,
    required this.recommendation,
    this.modelReview,
  });

  factory ReviewResult.fromJson(Map<String, dynamic> json) {
    return ReviewResult(
      phaseId: _string(json['phaseId'] ?? json['phase_id']),
      status: parseReviewStatus(json['status']),
      deterministicChecks: _mapList(
        json['deterministicChecks'] ?? json['deterministic_checks'],
      ).map(DeterministicCheckResult.fromJson).toList(),
      modelReview: json['modelReview'] == null && json['model_review'] == null
          ? null
          : ModelReviewResult.fromJson(
              _map(json['modelReview'] ?? json['model_review']),
            ),
      summary: _string(json['summary']),
      issues: _mapList(json['issues']).map(ReviewIssue.fromJson).toList(),
      recommendation: parseReviewRecommendation(json['recommendation']),
    );
  }

  Map<String, dynamic> toJson() => {
    'phaseId': phaseId,
    'status': status.wire,
    'deterministicChecks': deterministicChecks
        .map((check) => check.toJson())
        .toList(),
    if (modelReview != null) 'modelReview': modelReview!.toJson(),
    'summary': summary,
    'issues': issues.map((issue) => issue.toJson()).toList(),
    'recommendation': recommendation.wire,
  };
}

class DeterministicCheckResult {
  final String id;
  final bool passed;
  final String message;

  const DeterministicCheckResult({
    required this.id,
    required this.passed,
    required this.message,
  });

  factory DeterministicCheckResult.fromJson(Map<String, dynamic> json) {
    return DeterministicCheckResult(
      id: _string(json['id']),
      passed: _bool(json['passed']),
      message: _string(json['message']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'passed': passed,
    'message': message,
  };
}

class ModelReviewResult {
  final bool passed;
  final String confidence;
  final String summary;
  final List<CriteriaResult> criteriaResults;

  const ModelReviewResult({
    required this.passed,
    required this.confidence,
    required this.summary,
    required this.criteriaResults,
  });

  factory ModelReviewResult.fromJson(Map<String, dynamic> json) {
    return ModelReviewResult(
      passed: _bool(json['passed']),
      confidence: _string(json['confidence'], fallback: 'low'),
      summary: _string(json['summary']),
      criteriaResults: _mapList(
        json['criteriaResults'] ?? json['criteria_results'],
      ).map(CriteriaResult.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'passed': passed,
    'confidence': confidence,
    'summary': summary,
    'criteriaResults': criteriaResults
        .map((result) => result.toJson())
        .toList(),
  };
}

class CriteriaResult {
  final String criterion;
  final bool passed;
  final String? evidence;
  final String? comment;

  const CriteriaResult({
    required this.criterion,
    required this.passed,
    this.evidence,
    this.comment,
  });

  factory CriteriaResult.fromJson(Map<String, dynamic> json) {
    return CriteriaResult(
      criterion: _string(json['criterion']),
      passed: _bool(json['passed']),
      evidence: _nullableString(json['evidence']),
      comment: _nullableString(json['comment']),
    );
  }

  Map<String, dynamic> toJson() => {
    'criterion': criterion,
    'passed': passed,
    if (evidence != null) 'evidence': evidence,
    if (comment != null) 'comment': comment,
  };
}

class ReviewIssue {
  final String severity;
  final String message;
  final String? suggestedAction;

  const ReviewIssue({
    required this.severity,
    required this.message,
    this.suggestedAction,
  });

  factory ReviewIssue.fromJson(Map<String, dynamic> json) {
    return ReviewIssue(
      severity: _string(json['severity'], fallback: 'warning'),
      message: _string(json['message']),
      suggestedAction: _nullableString(
        json['suggestedAction'] ?? json['suggested_action'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'severity': severity,
    'message': message,
    if (suggestedAction != null) 'suggestedAction': suggestedAction,
  };
}

class JobSnapshot {
  final TaskBrief taskBrief;
  final JobSpec spec;
  final JobState state;

  const JobSnapshot({
    required this.taskBrief,
    required this.spec,
    required this.state,
  });

  JobSnapshot copyWith({TaskBrief? taskBrief, JobSpec? spec, JobState? state}) {
    return JobSnapshot(
      taskBrief: taskBrief ?? this.taskBrief,
      spec: spec ?? this.spec,
      state: state ?? this.state,
    );
  }
}

Map<String, dynamic> _toolDefinitionToJson(ToolDefinition tool) => {
  'id': tool.id,
  'name': tool.name,
  'description': tool.description,
  'schema': tool.schema,
};

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

List<String> _rawStringList(Object? value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  if (value is String) return [value];
  return const [];
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final string = value.toString();
  return string.isEmpty ? fallback : string;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final string = value.toString().trim();
  return string.isEmpty ? null : string;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalised = value.trim().toLowerCase();
    if (normalised == 'true' || normalised == 'yes' || normalised == '1') {
      return true;
    }
    if (normalised == 'false' || normalised == 'no' || normalised == '0') {
      return false;
    }
  }
  return fallback;
}

bool? _nullableBool(Object? value) {
  if (value == null) return null;
  return _bool(value);
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return _int(value);
}

DateTime _date(Object? value, {required DateTime fallback}) {
  return _nullableDate(value) ?? fallback;
}

DateTime? _nullableDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value.toString());
}

const Object _sentinel = Object();
