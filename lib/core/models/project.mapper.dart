// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project.dart';

/// @nodoc

class ProjectStatusMapper extends EnumMapper<ProjectStatus> {
  ProjectStatusMapper._();

  static ProjectStatusMapper? _instance;
  static ProjectStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectStatusMapper._());
    }
    return _instance!;
  }

  static ProjectStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectStatus decode(dynamic value) {
    switch (value) {
      case r'initializing':
        return ProjectStatus.initializing;
      case r'active':
        return ProjectStatus.active;
      case r'paused':
        return ProjectStatus.paused;
      case 'running_task':
        return ProjectStatus.runningTask;
      case 'reviewing_task':
        return ProjectStatus.reviewingTask;
      case 'waiting_for_user':
        return ProjectStatus.waitingForUser;
      case r'blocked':
        return ProjectStatus.blocked;
      case r'completed':
        return ProjectStatus.completed;
      case r'failed':
        return ProjectStatus.failed;
      case r'cancelled':
        return ProjectStatus.cancelled;
      default:
        return ProjectStatus.values[1];
    }
  }

  @override
  dynamic encode(ProjectStatus self) {
    switch (self) {
      case ProjectStatus.initializing:
        return r'initializing';
      case ProjectStatus.active:
        return r'active';
      case ProjectStatus.paused:
        return r'paused';
      case ProjectStatus.runningTask:
        return 'running_task';
      case ProjectStatus.reviewingTask:
        return 'reviewing_task';
      case ProjectStatus.waitingForUser:
        return 'waiting_for_user';
      case ProjectStatus.blocked:
        return r'blocked';
      case ProjectStatus.completed:
        return r'completed';
      case ProjectStatus.failed:
        return r'failed';
      case ProjectStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension ProjectStatusMapperExtension on ProjectStatus {
  dynamic toValue() {
    ProjectStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectStatus>(this);
  }
}

/// @nodoc

class ProjectPhaseMapper extends EnumMapper<ProjectPhase> {
  ProjectPhaseMapper._();

  static ProjectPhaseMapper? _instance;
  static ProjectPhaseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectPhaseMapper._());
    }
    return _instance!;
  }

  static ProjectPhase fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectPhase decode(dynamic value) {
    switch (value) {
      case r'discovery':
        return ProjectPhase.discovery;
      case r'planning':
        return ProjectPhase.planning;
      case r'execution':
        return ProjectPhase.execution;
      case r'verification':
        return ProjectPhase.verification;
      case r'finalization':
        return ProjectPhase.finalization;
      default:
        return ProjectPhase.values[0];
    }
  }

  @override
  dynamic encode(ProjectPhase self) {
    switch (self) {
      case ProjectPhase.discovery:
        return r'discovery';
      case ProjectPhase.planning:
        return r'planning';
      case ProjectPhase.execution:
        return r'execution';
      case ProjectPhase.verification:
        return r'verification';
      case ProjectPhase.finalization:
        return r'finalization';
    }
  }
}

/// @nodoc

extension ProjectPhaseMapperExtension on ProjectPhase {
  String toValue() {
    ProjectPhaseMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectPhase>(this) as String;
  }
}

/// @nodoc

class ProjectTaskStatusMapper extends EnumMapper<ProjectTaskStatus> {
  ProjectTaskStatusMapper._();

  static ProjectTaskStatusMapper? _instance;
  static ProjectTaskStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskStatusMapper._());
    }
    return _instance!;
  }

  static ProjectTaskStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectTaskStatus decode(dynamic value) {
    switch (value) {
      case r'queued':
        return ProjectTaskStatus.queued;
      case r'proposed':
        return ProjectTaskStatus.proposed;
      case r'approved':
        return ProjectTaskStatus.approved;
      case r'running':
        return ProjectTaskStatus.running;
      case r'completed':
        return ProjectTaskStatus.completed;
      case r'failed':
        return ProjectTaskStatus.failed;
      case r'rejected':
        return ProjectTaskStatus.rejected;
      case r'split':
        return ProjectTaskStatus.split;
      case r'cancelled':
        return ProjectTaskStatus.cancelled;
      default:
        return ProjectTaskStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectTaskStatus self) {
    switch (self) {
      case ProjectTaskStatus.queued:
        return r'queued';
      case ProjectTaskStatus.proposed:
        return r'proposed';
      case ProjectTaskStatus.approved:
        return r'approved';
      case ProjectTaskStatus.running:
        return r'running';
      case ProjectTaskStatus.completed:
        return r'completed';
      case ProjectTaskStatus.failed:
        return r'failed';
      case ProjectTaskStatus.rejected:
        return r'rejected';
      case ProjectTaskStatus.split:
        return r'split';
      case ProjectTaskStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension ProjectTaskStatusMapperExtension on ProjectTaskStatus {
  String toValue() {
    ProjectTaskStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectTaskStatus>(this) as String;
  }
}

/// @nodoc

class ProjectBlockerTypeMapper extends EnumMapper<ProjectBlockerType> {
  ProjectBlockerTypeMapper._();

  static ProjectBlockerTypeMapper? _instance;
  static ProjectBlockerTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectBlockerTypeMapper._());
    }
    return _instance!;
  }

  static ProjectBlockerType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectBlockerType decode(dynamic value) {
    switch (value) {
      case r'question':
        return ProjectBlockerType.question;
      case 'task_approval':
        return ProjectBlockerType.taskApproval;
      case 'task_blocked':
        return ProjectBlockerType.taskBlocked;
      case 'task_failed':
        return ProjectBlockerType.taskFailed;
      case 'recovery_failed':
        return ProjectBlockerType.recoveryFailed;
      case r'budget':
        return ProjectBlockerType.budget;
      case r'validation':
        return ProjectBlockerType.validation;
      case 'duplicate_task':
        return ProjectBlockerType.duplicateTask;
      case 'oversized_task':
        return ProjectBlockerType.oversizedTask;
      case 'max_failures':
        return ProjectBlockerType.maxFailures;
      case r'error':
        return ProjectBlockerType.error;
      default:
        return ProjectBlockerType.values[10];
    }
  }

  @override
  dynamic encode(ProjectBlockerType self) {
    switch (self) {
      case ProjectBlockerType.question:
        return r'question';
      case ProjectBlockerType.taskApproval:
        return 'task_approval';
      case ProjectBlockerType.taskBlocked:
        return 'task_blocked';
      case ProjectBlockerType.taskFailed:
        return 'task_failed';
      case ProjectBlockerType.recoveryFailed:
        return 'recovery_failed';
      case ProjectBlockerType.budget:
        return r'budget';
      case ProjectBlockerType.validation:
        return r'validation';
      case ProjectBlockerType.duplicateTask:
        return 'duplicate_task';
      case ProjectBlockerType.oversizedTask:
        return 'oversized_task';
      case ProjectBlockerType.maxFailures:
        return 'max_failures';
      case ProjectBlockerType.error:
        return r'error';
    }
  }
}

/// @nodoc

extension ProjectBlockerTypeMapperExtension on ProjectBlockerType {
  dynamic toValue() {
    ProjectBlockerTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectBlockerType>(this);
  }
}

/// @nodoc

class ProjectDecisionTypeMapper extends EnumMapper<ProjectDecisionType> {
  ProjectDecisionTypeMapper._();

  static ProjectDecisionTypeMapper? _instance;
  static ProjectDecisionTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectDecisionTypeMapper._());
    }
    return _instance!;
  }

  static ProjectDecisionType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectDecisionType decode(dynamic value) {
    switch (value) {
      case 'create_task':
        return ProjectDecisionType.createTask;
      case 'create_recovery_task':
        return ProjectDecisionType.createRecoveryTask;
      case r'complete':
        return ProjectDecisionType.complete;
      case r'blocked':
        return ProjectDecisionType.blocked;
      case 'reject_task':
        return ProjectDecisionType.rejectTask;
      case 'split_task':
        return ProjectDecisionType.splitTask;
      case 'evaluate_task':
        return ProjectDecisionType.evaluateTask;
      case 'refresh_backlog':
        return ProjectDecisionType.refreshBacklog;
      case 'retry_recovery':
        return ProjectDecisionType.retryRecovery;
      default:
        return ProjectDecisionType.values[3];
    }
  }

  @override
  dynamic encode(ProjectDecisionType self) {
    switch (self) {
      case ProjectDecisionType.createTask:
        return 'create_task';
      case ProjectDecisionType.createRecoveryTask:
        return 'create_recovery_task';
      case ProjectDecisionType.complete:
        return r'complete';
      case ProjectDecisionType.blocked:
        return r'blocked';
      case ProjectDecisionType.rejectTask:
        return 'reject_task';
      case ProjectDecisionType.splitTask:
        return 'split_task';
      case ProjectDecisionType.evaluateTask:
        return 'evaluate_task';
      case ProjectDecisionType.refreshBacklog:
        return 'refresh_backlog';
      case ProjectDecisionType.retryRecovery:
        return 'retry_recovery';
    }
  }
}

/// @nodoc

extension ProjectDecisionTypeMapperExtension on ProjectDecisionType {
  dynamic toValue() {
    ProjectDecisionTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectDecisionType>(this);
  }
}

/// @nodoc

class ProjectRecoveryIncidentStatusMapper
    extends EnumMapper<ProjectRecoveryIncidentStatus> {
  ProjectRecoveryIncidentStatusMapper._();

  static ProjectRecoveryIncidentStatusMapper? _instance;
  static ProjectRecoveryIncidentStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectRecoveryIncidentStatusMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectRecoveryIncidentStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectRecoveryIncidentStatus decode(dynamic value) {
    switch (value) {
      case r'active':
        return ProjectRecoveryIncidentStatus.active;
      case r'resolved':
        return ProjectRecoveryIncidentStatus.resolved;
      case r'exhausted':
        return ProjectRecoveryIncidentStatus.exhausted;
      default:
        return ProjectRecoveryIncidentStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectRecoveryIncidentStatus self) {
    switch (self) {
      case ProjectRecoveryIncidentStatus.active:
        return r'active';
      case ProjectRecoveryIncidentStatus.resolved:
        return r'resolved';
      case ProjectRecoveryIncidentStatus.exhausted:
        return r'exhausted';
    }
  }
}

/// @nodoc

extension ProjectRecoveryIncidentStatusMapperExtension
    on ProjectRecoveryIncidentStatus {
  String toValue() {
    ProjectRecoveryIncidentStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectRecoveryIncidentStatus>(this)
        as String;
  }
}

/// @nodoc
class ProjectStateMapper extends ClassMapperBase<ProjectState> {
  ProjectStateMapper._();

  static ProjectStateMapper? _instance;
  static ProjectStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectStateMapper._());
      ProjectTaskMapper.ensureInitialized();
      ProjectArtifactMapper.ensureInitialized();
      ProjectRecoveryIncidentMapper.ensureInitialized();
      PendingProjectQuestionMapper.ensureInitialized();
      ProjectTaskRefMapper.ensureInitialized();
      ProjectStatusMapper.ensureInitialized();
      ProjectPhaseMapper.ensureInitialized();
      ProjectBlockerMapper.ensureInitialized();
      ProjectDecisionRecordMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectState';

  static int _$schemaVersion(ProjectState v) => v.schemaVersion;
  static const Field<ProjectState, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: ProjectState.currentSchemaVersion,
    hook: JsonIntHook(),
  );
  static String _$id(ProjectState v) => v.id;
  static const Field<ProjectState, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$title(ProjectState v) => v.title;
  static const Field<ProjectState, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled project'),
  );
  static String _$originalGoal(ProjectState v) => v.originalGoal;
  static const Field<ProjectState, String> _f$originalGoal = Field(
    'originalGoal',
    _$originalGoal,
    opt: true,
    hook: JsonStringHook(),
  );
  static String _$refinedGoal(ProjectState v) => v.refinedGoal;
  static const Field<ProjectState, String> _f$refinedGoal = Field(
    'refinedGoal',
    _$refinedGoal,
    opt: true,
    hook: JsonStringHook(),
  );
  static String _$originalPrompt(ProjectState v) => v.originalPrompt;
  static const Field<ProjectState, String> _f$originalPrompt = Field(
    'originalPrompt',
    _$originalPrompt,
    opt: true,
  );
  static String _$goal(ProjectState v) => v.goal;
  static const Field<ProjectState, String> _f$goal = Field(
    'goal',
    _$goal,
    opt: true,
  );
  static List<String> _$successCriteria(ProjectState v) => v.successCriteria;
  static const Field<ProjectState, List<String>> _f$successCriteria = Field(
    'successCriteria',
    _$successCriteria,
    hook: JsonStringListHook(),
  );
  static List<String> _$constraints(ProjectState v) => v.constraints;
  static const Field<ProjectState, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    hook: JsonStringListHook(),
  );
  static List<ProjectTask> _$backlog(ProjectState v) => v.backlog;
  static const Field<ProjectState, List<ProjectTask>> _f$backlog = Field(
    'backlog',
    _$backlog,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static ProjectTask? _$currentTask(ProjectState v) => v.currentTask;
  static const Field<ProjectState, ProjectTask> _f$currentTask = Field(
    'currentTask',
    _$currentTask,
    opt: true,
  );
  static List<ProjectTask> _$completedTasks(ProjectState v) => v.completedTasks;
  static const Field<ProjectState, List<ProjectTask>> _f$completedTasks = Field(
    'completedTasks',
    _$completedTasks,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectTask> _$failedTasks(ProjectState v) => v.failedTasks;
  static const Field<ProjectState, List<ProjectTask>> _f$failedTasks = Field(
    'failedTasks',
    _$failedTasks,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectArtifact> _$artifacts(ProjectState v) => v.artifacts;
  static const Field<ProjectState, List<ProjectArtifact>> _f$artifacts = Field(
    'artifacts',
    _$artifacts,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectRecoveryIncident> _$recoveryIncidents(ProjectState v) =>
      v.recoveryIncidents;
  static const Field<ProjectState, List<ProjectRecoveryIncident>>
  _f$recoveryIncidents = Field(
    'recoveryIncidents',
    _$recoveryIncidents,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<String> _$knownFacts(ProjectState v) => v.knownFacts;
  static const Field<ProjectState, List<String>> _f$knownFacts = Field(
    'knownFacts',
    _$knownFacts,
    opt: true,
    hook: JsonStringListHook(),
  );
  static List<PendingProjectQuestion> _$openQuestions(ProjectState v) =>
      v.openQuestions;
  static const Field<ProjectState, List<PendingProjectQuestion>>
  _f$openQuestions = Field(
    'openQuestions',
    _$openQuestions,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static String _$memorySummary(ProjectState v) => v.memorySummary;
  static const Field<ProjectState, String> _f$memorySummary = Field(
    'memorySummary',
    _$memorySummary,
    opt: true,
  );
  static List<ProjectTaskRef> _$tasks(ProjectState v) => v.tasks;
  static const Field<ProjectState, List<ProjectTaskRef>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
  );
  static PendingProjectQuestion? _$pendingQuestion(ProjectState v) =>
      v.pendingQuestion;
  static const Field<ProjectState, PendingProjectQuestion> _f$pendingQuestion =
      Field('pendingQuestion', _$pendingQuestion, opt: true);
  static ProjectStatus _$status(ProjectState v) => v.status;
  static const Field<ProjectState, ProjectStatus> _f$status = Field(
    'status',
    _$status,
    hook: EnumAliasHook({
      'running': 'running_task',
      'runningtask': 'running_task',
      'reviewingtask': 'reviewing_task',
      'waitingforuser': 'waiting_for_user',
    }),
  );
  static ProjectPhase _$phase(ProjectState v) => v.phase;
  static const Field<ProjectState, ProjectPhase> _f$phase = Field(
    'phase',
    _$phase,
    opt: true,
    hook: EnumAliasHook({}),
  );
  static int _$iterationCount(ProjectState v) => v.iterationCount;
  static const Field<ProjectState, int> _f$iterationCount = Field(
    'iterationCount',
    _$iterationCount,
    opt: true,
    hook: JsonIntHook(),
  );
  static int _$maxIterations(ProjectState v) => v.maxIterations;
  static const Field<ProjectState, int> _f$maxIterations = Field(
    'maxIterations',
    _$maxIterations,
    opt: true,
    def: ProjectState.defaultMaxIterations,
    hook: JsonIntHook(fallback: ProjectState.defaultMaxIterations, min: 0),
  );
  static int _$maxFailedTasks(ProjectState v) => v.maxFailedTasks;
  static const Field<ProjectState, int> _f$maxFailedTasks = Field(
    'maxFailedTasks',
    _$maxFailedTasks,
    opt: true,
    def: ProjectState.defaultMaxFailedTasks,
    hook: JsonIntHook(
      fallback: ProjectState.defaultMaxFailedTasks,
      min: 1,
      max: 100,
    ),
  );
  static String? _$activeTaskId(ProjectState v) => v.activeTaskId;
  static const Field<ProjectState, String> _f$activeTaskId = Field(
    'activeTaskId',
    _$activeTaskId,
    hook: JsonNullableStringHook(),
  );
  static String? _$chatSessionId(ProjectState v) => v.chatSessionId;
  static const Field<ProjectState, String> _f$chatSessionId = Field(
    'chatSessionId',
    _$chatSessionId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$completionSummary(ProjectState v) => v.completionSummary;
  static const Field<ProjectState, String> _f$completionSummary = Field(
    'completionSummary',
    _$completionSummary,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static ProjectBlocker? _$blocker(ProjectState v) => v.blocker;
  static const Field<ProjectState, ProjectBlocker> _f$blocker = Field(
    'blocker',
    _$blocker,
    opt: true,
  );
  static List<ProjectDecisionRecord> _$decisions(ProjectState v) => v.decisions;
  static const Field<ProjectState, List<ProjectDecisionRecord>> _f$decisions =
      Field(
        'decisions',
        _$decisions,
        opt: true,
        def: const [],
        hook: JsonObjectListHook(),
      );
  static DateTime _$createdAt(ProjectState v) => v.createdAt;
  static const Field<ProjectState, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectState v) => v.updatedAt;
  static const Field<ProjectState, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$completedAt(ProjectState v) => v.completedAt;
  static const Field<ProjectState, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<ProjectState> fields = const {
    #schemaVersion: _f$schemaVersion,
    #id: _f$id,
    #title: _f$title,
    #originalGoal: _f$originalGoal,
    #refinedGoal: _f$refinedGoal,
    #originalPrompt: _f$originalPrompt,
    #goal: _f$goal,
    #successCriteria: _f$successCriteria,
    #constraints: _f$constraints,
    #backlog: _f$backlog,
    #currentTask: _f$currentTask,
    #completedTasks: _f$completedTasks,
    #failedTasks: _f$failedTasks,
    #artifacts: _f$artifacts,
    #recoveryIncidents: _f$recoveryIncidents,
    #knownFacts: _f$knownFacts,
    #openQuestions: _f$openQuestions,
    #memorySummary: _f$memorySummary,
    #tasks: _f$tasks,
    #pendingQuestion: _f$pendingQuestion,
    #status: _f$status,
    #phase: _f$phase,
    #iterationCount: _f$iterationCount,
    #maxIterations: _f$maxIterations,
    #maxFailedTasks: _f$maxFailedTasks,
    #activeTaskId: _f$activeTaskId,
    #chatSessionId: _f$chatSessionId,
    #completionSummary: _f$completionSummary,
    #blocker: _f$blocker,
    #decisions: _f$decisions,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const ProjectStateJsonHook();
  static ProjectState _instantiate(DecodingData data) {
    return ProjectState(
      schemaVersion: data.dec(_f$schemaVersion),
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      originalGoal: data.dec(_f$originalGoal),
      refinedGoal: data.dec(_f$refinedGoal),
      originalPrompt: data.dec(_f$originalPrompt),
      goal: data.dec(_f$goal),
      successCriteria: data.dec(_f$successCriteria),
      constraints: data.dec(_f$constraints),
      backlog: data.dec(_f$backlog),
      currentTask: data.dec(_f$currentTask),
      completedTasks: data.dec(_f$completedTasks),
      failedTasks: data.dec(_f$failedTasks),
      artifacts: data.dec(_f$artifacts),
      recoveryIncidents: data.dec(_f$recoveryIncidents),
      knownFacts: data.dec(_f$knownFacts),
      openQuestions: data.dec(_f$openQuestions),
      memorySummary: data.dec(_f$memorySummary),
      tasks: data.dec(_f$tasks),
      pendingQuestion: data.dec(_f$pendingQuestion),
      status: data.dec(_f$status),
      phase: data.dec(_f$phase),
      iterationCount: data.dec(_f$iterationCount),
      maxIterations: data.dec(_f$maxIterations),
      maxFailedTasks: data.dec(_f$maxFailedTasks),
      activeTaskId: data.dec(_f$activeTaskId),
      chatSessionId: data.dec(_f$chatSessionId),
      completionSummary: data.dec(_f$completionSummary),
      blocker: data.dec(_f$blocker),
      decisions: data.dec(_f$decisions),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectState>(map);
  }

  static ProjectState fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectState>(json);
  }
}

/// @nodoc
mixin ProjectStateMappable {
  String toJson() {
    return ProjectStateMapper.ensureInitialized().encodeJson<ProjectState>(
      this as ProjectState,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectStateMapper.ensureInitialized().encodeMap<ProjectState>(
      this as ProjectState,
    );
  }
}

/// @nodoc
class ProjectTaskMapper extends ClassMapperBase<ProjectTask> {
  ProjectTaskMapper._();

  static ProjectTaskMapper? _instance;
  static ProjectTaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskMapper._());
      ProjectArtifactMapper.ensureInitialized();
      ProjectTaskStatusMapper.ensureInitialized();
      ProjectTaskFailureMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTask';

  static String _$id(ProjectTask v) => v.id;
  static const Field<ProjectTask, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(fallback: 'project_task'),
  );
  static String _$title(ProjectTask v) => v.title;
  static const Field<ProjectTask, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static String _$objective(ProjectTask v) => v.objective;
  static const Field<ProjectTask, String> _f$objective = Field(
    'objective',
    _$objective,
    hook: JsonStringHook(),
  );
  static List<String> _$relevantSuccessCriteria(ProjectTask v) =>
      v.relevantSuccessCriteria;
  static const Field<ProjectTask, List<String>> _f$relevantSuccessCriteria =
      Field(
        'relevantSuccessCriteria',
        _$relevantSuccessCriteria,
        hook: JsonStringListHook(),
      );
  static List<String> _$doneCriteria(ProjectTask v) => v.doneCriteria;
  static const Field<ProjectTask, List<String>> _f$doneCriteria = Field(
    'doneCriteria',
    _$doneCriteria,
    hook: JsonStringListHook(),
  );
  static List<String> _$outOfScope(ProjectTask v) => v.outOfScope;
  static const Field<ProjectTask, List<String>> _f$outOfScope = Field(
    'outOfScope',
    _$outOfScope,
    hook: JsonStringListHook(),
  );
  static List<String> _$context(ProjectTask v) => v.context;
  static const Field<ProjectTask, List<String>> _f$context = Field(
    'context',
    _$context,
    hook: JsonStringListHook(),
  );
  static List<ProjectArtifact> _$expectedArtifacts(ProjectTask v) =>
      v.expectedArtifacts;
  static const Field<ProjectTask, List<ProjectArtifact>> _f$expectedArtifacts =
      Field(
        'expectedArtifacts',
        _$expectedArtifacts,
        hook: JsonObjectListHook(),
      );
  static ProjectTaskStatus _$status(ProjectTask v) => v.status;
  static const Field<ProjectTask, ProjectTaskStatus> _f$status = Field(
    'status',
    _$status,
    hook: EnumAliasHook({}),
  );
  static String? _$taskDocumentId(ProjectTask v) => v.taskDocumentId;
  static const Field<ProjectTask, String> _f$taskDocumentId = Field(
    'taskDocumentId',
    _$taskDocumentId,
    hook: JsonNullableStringHook(),
  );
  static String? _$recoveryIncidentId(ProjectTask v) => v.recoveryIncidentId;
  static const Field<ProjectTask, String> _f$recoveryIncidentId = Field(
    'recoveryIncidentId',
    _$recoveryIncidentId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$fingerprint(ProjectTask v) => v.fingerprint;
  static const Field<ProjectTask, String> _f$fingerprint = Field(
    'fingerprint',
    _$fingerprint,
    hook: JsonStringHook(),
  );
  static String? _$rejectionReason(ProjectTask v) => v.rejectionReason;
  static const Field<ProjectTask, String> _f$rejectionReason = Field(
    'rejectionReason',
    _$rejectionReason,
    hook: JsonNullableStringHook(),
  );
  static ProjectTaskFailure? _$failure(ProjectTask v) => v.failure;
  static const Field<ProjectTask, ProjectTaskFailure> _f$failure = Field(
    'failure',
    _$failure,
    opt: true,
  );
  static DateTime _$createdAt(ProjectTask v) => v.createdAt;
  static const Field<ProjectTask, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectTask v) => v.updatedAt;
  static const Field<ProjectTask, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<ProjectTask> fields = const {
    #id: _f$id,
    #title: _f$title,
    #objective: _f$objective,
    #relevantSuccessCriteria: _f$relevantSuccessCriteria,
    #doneCriteria: _f$doneCriteria,
    #outOfScope: _f$outOfScope,
    #context: _f$context,
    #expectedArtifacts: _f$expectedArtifacts,
    #status: _f$status,
    #taskDocumentId: _f$taskDocumentId,
    #recoveryIncidentId: _f$recoveryIncidentId,
    #fingerprint: _f$fingerprint,
    #rejectionReason: _f$rejectionReason,
    #failure: _f$failure,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const ProjectTaskJsonHook();
  static ProjectTask _instantiate(DecodingData data) {
    return ProjectTask(
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      objective: data.dec(_f$objective),
      relevantSuccessCriteria: data.dec(_f$relevantSuccessCriteria),
      doneCriteria: data.dec(_f$doneCriteria),
      outOfScope: data.dec(_f$outOfScope),
      context: data.dec(_f$context),
      expectedArtifacts: data.dec(_f$expectedArtifacts),
      status: data.dec(_f$status),
      taskDocumentId: data.dec(_f$taskDocumentId),
      recoveryIncidentId: data.dec(_f$recoveryIncidentId),
      fingerprint: data.dec(_f$fingerprint),
      rejectionReason: data.dec(_f$rejectionReason),
      failure: data.dec(_f$failure),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTask fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTask>(map);
  }

  static ProjectTask fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTask>(json);
  }
}

/// @nodoc
mixin ProjectTaskMappable {
  String toJson() {
    return ProjectTaskMapper.ensureInitialized().encodeJson<ProjectTask>(
      this as ProjectTask,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskMapper.ensureInitialized().encodeMap<ProjectTask>(
      this as ProjectTask,
    );
  }
}

/// @nodoc
class ProjectArtifactMapper extends ClassMapperBase<ProjectArtifact> {
  ProjectArtifactMapper._();

  static ProjectArtifactMapper? _instance;
  static ProjectArtifactMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectArtifactMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectArtifact';

  static String _$id(ProjectArtifact v) => v.id;
  static const Field<ProjectArtifact, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String? _$projectTaskId(ProjectArtifact v) => v.projectTaskId;
  static const Field<ProjectArtifact, String> _f$projectTaskId = Field(
    'projectTaskId',
    _$projectTaskId,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskDocumentId(ProjectArtifact v) => v.taskDocumentId;
  static const Field<ProjectArtifact, String> _f$taskDocumentId = Field(
    'taskDocumentId',
    _$taskDocumentId,
    hook: JsonNullableStringHook(),
  );
  static String _$path(ProjectArtifact v) => v.path;
  static const Field<ProjectArtifact, String> _f$path = Field(
    'path',
    _$path,
    hook: JsonStringHook(),
  );
  static String _$description(ProjectArtifact v) => v.description;
  static const Field<ProjectArtifact, String> _f$description = Field(
    'description',
    _$description,
    hook: JsonStringHook(),
  );
  static String _$kind(ProjectArtifact v) => v.kind;
  static const Field<ProjectArtifact, String> _f$kind = Field(
    'kind',
    _$kind,
    hook: JsonStringHook(fallback: 'file'),
  );
  static DateTime _$createdAt(ProjectArtifact v) => v.createdAt;
  static const Field<ProjectArtifact, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<ProjectArtifact> fields = const {
    #id: _f$id,
    #projectTaskId: _f$projectTaskId,
    #taskDocumentId: _f$taskDocumentId,
    #path: _f$path,
    #description: _f$description,
    #kind: _f$kind,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const ProjectArtifactJsonHook();
  static ProjectArtifact _instantiate(DecodingData data) {
    return ProjectArtifact(
      id: data.dec(_f$id),
      projectTaskId: data.dec(_f$projectTaskId),
      taskDocumentId: data.dec(_f$taskDocumentId),
      path: data.dec(_f$path),
      description: data.dec(_f$description),
      kind: data.dec(_f$kind),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectArtifact fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectArtifact>(map);
  }

  static ProjectArtifact fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectArtifact>(json);
  }
}

/// @nodoc
mixin ProjectArtifactMappable {
  String toJson() {
    return ProjectArtifactMapper.ensureInitialized()
        .encodeJson<ProjectArtifact>(this as ProjectArtifact);
  }

  Map<String, dynamic> toMap() {
    return ProjectArtifactMapper.ensureInitialized().encodeMap<ProjectArtifact>(
      this as ProjectArtifact,
    );
  }
}

/// @nodoc
class ProjectTaskFailureMapper extends ClassMapperBase<ProjectTaskFailure> {
  ProjectTaskFailureMapper._();

  static ProjectTaskFailureMapper? _instance;
  static ProjectTaskFailureMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskFailureMapper._());
      TaskGateFailureDispositionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTaskFailure';

  static String? _$gateId(ProjectTaskFailure v) => v.gateId;
  static const Field<ProjectTaskFailure, String> _f$gateId = Field(
    'gateId',
    _$gateId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskGateFailureDisposition _$disposition(ProjectTaskFailure v) =>
      v.disposition;
  static const Field<ProjectTaskFailure, TaskGateFailureDisposition>
  _f$disposition = Field('disposition', _$disposition, hook: EnumAliasHook({}));
  static String _$failureKey(ProjectTaskFailure v) => v.failureKey;
  static const Field<ProjectTaskFailure, String> _f$failureKey = Field(
    'failureKey',
    _$failureKey,
    hook: JsonStringHook(),
  );
  static String _$summary(ProjectTaskFailure v) => v.summary;
  static const Field<ProjectTaskFailure, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static List<String> _$errorCodes(ProjectTaskFailure v) => v.errorCodes;
  static const Field<ProjectTaskFailure, List<String>> _f$errorCodes = Field(
    'errorCodes',
    _$errorCodes,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$toolCallIds(ProjectTaskFailure v) => v.toolCallIds;
  static const Field<ProjectTaskFailure, List<String>> _f$toolCallIds = Field(
    'toolCallIds',
    _$toolCallIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static int _$advisoryErrorCount(ProjectTaskFailure v) => v.advisoryErrorCount;
  static const Field<ProjectTaskFailure, int> _f$advisoryErrorCount = Field(
    'advisoryErrorCount',
    _$advisoryErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$resolvedErrorCount(ProjectTaskFailure v) => v.resolvedErrorCount;
  static const Field<ProjectTaskFailure, int> _f$resolvedErrorCount = Field(
    'resolvedErrorCount',
    _$resolvedErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$unresolvedErrorCount(ProjectTaskFailure v) =>
      v.unresolvedErrorCount;
  static const Field<ProjectTaskFailure, int> _f$unresolvedErrorCount = Field(
    'unresolvedErrorCount',
    _$unresolvedErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );

  @override
  final MappableFields<ProjectTaskFailure> fields = const {
    #gateId: _f$gateId,
    #disposition: _f$disposition,
    #failureKey: _f$failureKey,
    #summary: _f$summary,
    #errorCodes: _f$errorCodes,
    #toolCallIds: _f$toolCallIds,
    #advisoryErrorCount: _f$advisoryErrorCount,
    #resolvedErrorCount: _f$resolvedErrorCount,
    #unresolvedErrorCount: _f$unresolvedErrorCount,
  };
  @override
  final bool ignoreNull = true;

  static ProjectTaskFailure _instantiate(DecodingData data) {
    return ProjectTaskFailure(
      gateId: data.dec(_f$gateId),
      disposition: data.dec(_f$disposition),
      failureKey: data.dec(_f$failureKey),
      summary: data.dec(_f$summary),
      errorCodes: data.dec(_f$errorCodes),
      toolCallIds: data.dec(_f$toolCallIds),
      advisoryErrorCount: data.dec(_f$advisoryErrorCount),
      resolvedErrorCount: data.dec(_f$resolvedErrorCount),
      unresolvedErrorCount: data.dec(_f$unresolvedErrorCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTaskFailure fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTaskFailure>(map);
  }

  static ProjectTaskFailure fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTaskFailure>(json);
  }
}

/// @nodoc
mixin ProjectTaskFailureMappable {
  String toJson() {
    return ProjectTaskFailureMapper.ensureInitialized()
        .encodeJson<ProjectTaskFailure>(this as ProjectTaskFailure);
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskFailureMapper.ensureInitialized()
        .encodeMap<ProjectTaskFailure>(this as ProjectTaskFailure);
  }
}

/// @nodoc
class ProjectRecoveryIncidentMapper
    extends ClassMapperBase<ProjectRecoveryIncident> {
  ProjectRecoveryIncidentMapper._();

  static ProjectRecoveryIncidentMapper? _instance;
  static ProjectRecoveryIncidentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectRecoveryIncidentMapper._(),
      );
      ProjectRecoveryIncidentStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectRecoveryIncident';

  static String _$id(ProjectRecoveryIncident v) => v.id;
  static const Field<ProjectRecoveryIncident, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(fallback: 'recovery_incident'),
  );
  static ProjectRecoveryIncidentStatus _$status(ProjectRecoveryIncident v) =>
      v.status;
  static const Field<ProjectRecoveryIncident, ProjectRecoveryIncidentStatus>
  _f$status = Field('status', _$status, hook: EnumAliasHook({}));
  static List<String> _$sourceTaskIds(ProjectRecoveryIncident v) =>
      v.sourceTaskIds;
  static const Field<ProjectRecoveryIncident, List<String>> _f$sourceTaskIds =
      Field('sourceTaskIds', _$sourceTaskIds, hook: JsonStringListHook());
  static List<String> _$sourceTaskTitles(ProjectRecoveryIncident v) =>
      v.sourceTaskTitles;
  static const Field<ProjectRecoveryIncident, List<String>>
  _f$sourceTaskTitles = Field(
    'sourceTaskTitles',
    _$sourceTaskTitles,
    hook: JsonStringListHook(),
  );
  static String _$failedGateId(ProjectRecoveryIncident v) => v.failedGateId;
  static const Field<ProjectRecoveryIncident, String> _f$failedGateId = Field(
    'failedGateId',
    _$failedGateId,
    hook: JsonStringHook(),
  );
  static String? _$command(ProjectRecoveryIncident v) => v.command;
  static const Field<ProjectRecoveryIncident, String> _f$command = Field(
    'command',
    _$command,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$workingDirectory(ProjectRecoveryIncident v) =>
      v.workingDirectory;
  static const Field<ProjectRecoveryIncident, String> _f$workingDirectory =
      Field(
        'workingDirectory',
        _$workingDirectory,
        opt: true,
        hook: JsonNullableStringHook(),
      );
  static String _$failureSummary(ProjectRecoveryIncident v) => v.failureSummary;
  static const Field<ProjectRecoveryIncident, String> _f$failureSummary = Field(
    'failureSummary',
    _$failureSummary,
    hook: JsonStringHook(),
  );
  static int _$attemptCount(ProjectRecoveryIncident v) => v.attemptCount;
  static const Field<ProjectRecoveryIncident, int> _f$attemptCount = Field(
    'attemptCount',
    _$attemptCount,
    hook: JsonIntHook(),
  );
  static int _$maxAttempts(ProjectRecoveryIncident v) => v.maxAttempts;
  static const Field<ProjectRecoveryIncident, int> _f$maxAttempts = Field(
    'maxAttempts',
    _$maxAttempts,
    opt: true,
    def: ProjectRecoveryIncident.defaultMaxAttempts,
    hook: JsonIntHook(
      fallback: ProjectRecoveryIncident.defaultMaxAttempts,
      min: 1,
      max: 100,
    ),
  );
  static List<String> _$recoveryTaskIds(ProjectRecoveryIncident v) =>
      v.recoveryTaskIds;
  static const Field<ProjectRecoveryIncident, List<String>> _f$recoveryTaskIds =
      Field('recoveryTaskIds', _$recoveryTaskIds, hook: JsonStringListHook());
  static DateTime _$createdAt(ProjectRecoveryIncident v) => v.createdAt;
  static const Field<ProjectRecoveryIncident, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectRecoveryIncident v) => v.updatedAt;
  static const Field<ProjectRecoveryIncident, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$resolvedAt(ProjectRecoveryIncident v) => v.resolvedAt;
  static const Field<ProjectRecoveryIncident, DateTime> _f$resolvedAt = Field(
    'resolvedAt',
    _$resolvedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<ProjectRecoveryIncident> fields = const {
    #id: _f$id,
    #status: _f$status,
    #sourceTaskIds: _f$sourceTaskIds,
    #sourceTaskTitles: _f$sourceTaskTitles,
    #failedGateId: _f$failedGateId,
    #command: _f$command,
    #workingDirectory: _f$workingDirectory,
    #failureSummary: _f$failureSummary,
    #attemptCount: _f$attemptCount,
    #maxAttempts: _f$maxAttempts,
    #recoveryTaskIds: _f$recoveryTaskIds,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #resolvedAt: _f$resolvedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectRecoveryIncident _instantiate(DecodingData data) {
    return ProjectRecoveryIncident(
      id: data.dec(_f$id),
      status: data.dec(_f$status),
      sourceTaskIds: data.dec(_f$sourceTaskIds),
      sourceTaskTitles: data.dec(_f$sourceTaskTitles),
      failedGateId: data.dec(_f$failedGateId),
      command: data.dec(_f$command),
      workingDirectory: data.dec(_f$workingDirectory),
      failureSummary: data.dec(_f$failureSummary),
      attemptCount: data.dec(_f$attemptCount),
      maxAttempts: data.dec(_f$maxAttempts),
      recoveryTaskIds: data.dec(_f$recoveryTaskIds),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      resolvedAt: data.dec(_f$resolvedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectRecoveryIncident fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectRecoveryIncident>(map);
  }

  static ProjectRecoveryIncident fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectRecoveryIncident>(json);
  }
}

/// @nodoc
mixin ProjectRecoveryIncidentMappable {
  String toJson() {
    return ProjectRecoveryIncidentMapper.ensureInitialized()
        .encodeJson<ProjectRecoveryIncident>(this as ProjectRecoveryIncident);
  }

  Map<String, dynamic> toMap() {
    return ProjectRecoveryIncidentMapper.ensureInitialized()
        .encodeMap<ProjectRecoveryIncident>(this as ProjectRecoveryIncident);
  }
}

/// @nodoc
class PendingProjectQuestionMapper
    extends ClassMapperBase<PendingProjectQuestion> {
  PendingProjectQuestionMapper._();

  static PendingProjectQuestionMapper? _instance;
  static PendingProjectQuestionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PendingProjectQuestionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PendingProjectQuestion';

  static String _$id(PendingProjectQuestion v) => v.id;
  static const Field<PendingProjectQuestion, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$question(PendingProjectQuestion v) => v.question;
  static const Field<PendingProjectQuestion, String> _f$question = Field(
    'question',
    _$question,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(PendingProjectQuestion v) => v.createdAt;
  static const Field<PendingProjectQuestion, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<PendingProjectQuestion> fields = const {
    #id: _f$id,
    #question: _f$question,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  static PendingProjectQuestion _instantiate(DecodingData data) {
    return PendingProjectQuestion(
      id: data.dec(_f$id),
      question: data.dec(_f$question),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PendingProjectQuestion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PendingProjectQuestion>(map);
  }

  static PendingProjectQuestion fromJson(String json) {
    return ensureInitialized().decodeJson<PendingProjectQuestion>(json);
  }
}

/// @nodoc
mixin PendingProjectQuestionMappable {
  String toJson() {
    return PendingProjectQuestionMapper.ensureInitialized()
        .encodeJson<PendingProjectQuestion>(this as PendingProjectQuestion);
  }

  Map<String, dynamic> toMap() {
    return PendingProjectQuestionMapper.ensureInitialized()
        .encodeMap<PendingProjectQuestion>(this as PendingProjectQuestion);
  }
}

/// @nodoc
class ProjectTaskRefMapper extends ClassMapperBase<ProjectTaskRef> {
  ProjectTaskRefMapper._();

  static ProjectTaskRefMapper? _instance;
  static ProjectTaskRefMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskRefMapper._());
      TaskStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTaskRef';

  static String _$taskId(ProjectTaskRef v) => v.taskId;
  static const Field<ProjectTaskRef, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    hook: JsonStringHook(),
  );
  static String _$title(ProjectTaskRef v) => v.title;
  static const Field<ProjectTaskRef, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static TaskStatus _$status(ProjectTaskRef v) => v.status;
  static const Field<ProjectTaskRef, TaskStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String _$summary(ProjectTaskRef v) => v.summary;
  static const Field<ProjectTaskRef, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(ProjectTaskRef v) => v.createdAt;
  static const Field<ProjectTaskRef, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectTaskRef v) => v.updatedAt;
  static const Field<ProjectTaskRef, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$completedAt(ProjectTaskRef v) => v.completedAt;
  static const Field<ProjectTaskRef, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<ProjectTaskRef> fields = const {
    #taskId: _f$taskId,
    #title: _f$title,
    #status: _f$status,
    #summary: _f$summary,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectTaskRef _instantiate(DecodingData data) {
    return ProjectTaskRef(
      taskId: data.dec(_f$taskId),
      title: data.dec(_f$title),
      status: data.dec(_f$status),
      summary: data.dec(_f$summary),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTaskRef fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTaskRef>(map);
  }

  static ProjectTaskRef fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTaskRef>(json);
  }
}

/// @nodoc
mixin ProjectTaskRefMappable {
  String toJson() {
    return ProjectTaskRefMapper.ensureInitialized().encodeJson<ProjectTaskRef>(
      this as ProjectTaskRef,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskRefMapper.ensureInitialized().encodeMap<ProjectTaskRef>(
      this as ProjectTaskRef,
    );
  }
}

/// @nodoc
class ProjectBlockerMapper extends ClassMapperBase<ProjectBlocker> {
  ProjectBlockerMapper._();

  static ProjectBlockerMapper? _instance;
  static ProjectBlockerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectBlockerMapper._());
      ProjectBlockerTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectBlocker';

  static ProjectBlockerType _$type(ProjectBlocker v) => v.type;
  static const Field<ProjectBlocker, ProjectBlockerType> _f$type = Field(
    'type',
    _$type,
    hook: EnumAliasHook({
      'taskapproval': 'task_approval',
      'taskblocked': 'task_blocked',
      'taskfailed': 'task_failed',
      'recoveryfailed': 'recovery_failed',
      'duplicatetask': 'duplicate_task',
      'oversizedtask': 'oversized_task',
      'maxfailures': 'max_failures',
    }),
  );
  static String _$message(ProjectBlocker v) => v.message;
  static const Field<ProjectBlocker, String> _f$message = Field(
    'message',
    _$message,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(ProjectBlocker v) => v.createdAt;
  static const Field<ProjectBlocker, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static String? _$taskId(ProjectBlocker v) => v.taskId;
  static const Field<ProjectBlocker, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<ProjectBlocker> fields = const {
    #type: _f$type,
    #message: _f$message,
    #createdAt: _f$createdAt,
    #taskId: _f$taskId,
  };
  @override
  final bool ignoreNull = true;

  static ProjectBlocker _instantiate(DecodingData data) {
    return ProjectBlocker(
      type: data.dec(_f$type),
      message: data.dec(_f$message),
      createdAt: data.dec(_f$createdAt),
      taskId: data.dec(_f$taskId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectBlocker fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectBlocker>(map);
  }

  static ProjectBlocker fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectBlocker>(json);
  }
}

/// @nodoc
mixin ProjectBlockerMappable {
  String toJson() {
    return ProjectBlockerMapper.ensureInitialized().encodeJson<ProjectBlocker>(
      this as ProjectBlocker,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectBlockerMapper.ensureInitialized().encodeMap<ProjectBlocker>(
      this as ProjectBlocker,
    );
  }
}

/// @nodoc
class ProjectDecisionRecordMapper
    extends ClassMapperBase<ProjectDecisionRecord> {
  ProjectDecisionRecordMapper._();

  static ProjectDecisionRecordMapper? _instance;
  static ProjectDecisionRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectDecisionRecordMapper._());
      ProjectDecisionTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectDecisionRecord';

  static String _$id(ProjectDecisionRecord v) => v.id;
  static const Field<ProjectDecisionRecord, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static ProjectDecisionType _$decision(ProjectDecisionRecord v) => v.decision;
  static const Field<ProjectDecisionRecord, ProjectDecisionType> _f$decision =
      Field(
        'decision',
        _$decision,
        hook: EnumAliasHook({
          'createtask': 'create_task',
          'createrecoverytask': 'create_recovery_task',
          'rejecttask': 'reject_task',
          'splittask': 'split_task',
          'evaluatetask': 'evaluate_task',
          'refreshbacklog': 'refresh_backlog',
          'retryrecovery': 'retry_recovery',
        }),
      );
  static String _$summary(ProjectDecisionRecord v) => v.summary;
  static const Field<ProjectDecisionRecord, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static String _$memoryUpdate(ProjectDecisionRecord v) => v.memoryUpdate;
  static const Field<ProjectDecisionRecord, String> _f$memoryUpdate = Field(
    'memoryUpdate',
    _$memoryUpdate,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(ProjectDecisionRecord v) => v.createdAt;
  static const Field<ProjectDecisionRecord, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static String? _$taskId(ProjectDecisionRecord v) => v.taskId;
  static const Field<ProjectDecisionRecord, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskTitle(ProjectDecisionRecord v) => v.taskTitle;
  static const Field<ProjectDecisionRecord, String> _f$taskTitle = Field(
    'taskTitle',
    _$taskTitle,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskPrompt(ProjectDecisionRecord v) => v.taskPrompt;
  static const Field<ProjectDecisionRecord, String> _f$taskPrompt = Field(
    'taskPrompt',
    _$taskPrompt,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$error(ProjectDecisionRecord v) => v.error;
  static const Field<ProjectDecisionRecord, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<ProjectDecisionRecord> fields = const {
    #id: _f$id,
    #decision: _f$decision,
    #summary: _f$summary,
    #memoryUpdate: _f$memoryUpdate,
    #createdAt: _f$createdAt,
    #taskId: _f$taskId,
    #taskTitle: _f$taskTitle,
    #taskPrompt: _f$taskPrompt,
    #error: _f$error,
  };
  @override
  final bool ignoreNull = true;

  static ProjectDecisionRecord _instantiate(DecodingData data) {
    return ProjectDecisionRecord(
      id: data.dec(_f$id),
      decision: data.dec(_f$decision),
      summary: data.dec(_f$summary),
      memoryUpdate: data.dec(_f$memoryUpdate),
      createdAt: data.dec(_f$createdAt),
      taskId: data.dec(_f$taskId),
      taskTitle: data.dec(_f$taskTitle),
      taskPrompt: data.dec(_f$taskPrompt),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectDecisionRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectDecisionRecord>(map);
  }

  static ProjectDecisionRecord fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectDecisionRecord>(json);
  }
}

/// @nodoc
mixin ProjectDecisionRecordMappable {
  String toJson() {
    return ProjectDecisionRecordMapper.ensureInitialized()
        .encodeJson<ProjectDecisionRecord>(this as ProjectDecisionRecord);
  }

  Map<String, dynamic> toMap() {
    return ProjectDecisionRecordMapper.ensureInitialized()
        .encodeMap<ProjectDecisionRecord>(this as ProjectDecisionRecord);
  }
}

