// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'task_state_models.dart';

/// @nodoc

class TaskStepStatusMapper extends EnumMapper<TaskStepStatus> {
  TaskStepStatusMapper._();

  static TaskStepStatusMapper? _instance;
  static TaskStepStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskStepStatusMapper._());
    }
    return _instance!;
  }

  static TaskStepStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskStepStatus decode(dynamic value) {
    switch (value) {
      case r'pending':
        return TaskStepStatus.pending;
      case r'approved':
        return TaskStepStatus.approved;
      case r'running':
        return TaskStepStatus.running;
      case r'completed':
        return TaskStepStatus.completed;
      case r'blocked':
        return TaskStepStatus.blocked;
      case r'failed':
        return TaskStepStatus.failed;
      case r'skipped':
        return TaskStepStatus.skipped;
      default:
        return TaskStepStatus.values[0];
    }
  }

  @override
  dynamic encode(TaskStepStatus self) {
    switch (self) {
      case TaskStepStatus.pending:
        return r'pending';
      case TaskStepStatus.approved:
        return r'approved';
      case TaskStepStatus.running:
        return r'running';
      case TaskStepStatus.completed:
        return r'completed';
      case TaskStepStatus.blocked:
        return r'blocked';
      case TaskStepStatus.failed:
        return r'failed';
      case TaskStepStatus.skipped:
        return r'skipped';
    }
  }
}

/// @nodoc

extension TaskStepStatusMapperExtension on TaskStepStatus {
  String toValue() {
    TaskStepStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskStepStatus>(this) as String;
  }
}

/// @nodoc

class TaskRunStatusMapper extends EnumMapper<TaskRunStatus> {
  TaskRunStatusMapper._();

  static TaskRunStatusMapper? _instance;
  static TaskRunStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskRunStatusMapper._());
    }
    return _instance!;
  }

  static TaskRunStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskRunStatus decode(dynamic value) {
    switch (value) {
      case r'running':
        return TaskRunStatus.running;
      case r'completed':
        return TaskRunStatus.completed;
      case r'blocked':
        return TaskRunStatus.blocked;
      case r'failed':
        return TaskRunStatus.failed;
      case r'cancelled':
        return TaskRunStatus.cancelled;
      case r'skipped':
        return TaskRunStatus.skipped;
      case 'needs_replan':
        return TaskRunStatus.needsReplan;
      case r'replanned':
        return TaskRunStatus.replanned;
      default:
        return TaskRunStatus.values[1];
    }
  }

  @override
  dynamic encode(TaskRunStatus self) {
    switch (self) {
      case TaskRunStatus.running:
        return r'running';
      case TaskRunStatus.completed:
        return r'completed';
      case TaskRunStatus.blocked:
        return r'blocked';
      case TaskRunStatus.failed:
        return r'failed';
      case TaskRunStatus.cancelled:
        return r'cancelled';
      case TaskRunStatus.skipped:
        return r'skipped';
      case TaskRunStatus.needsReplan:
        return 'needs_replan';
      case TaskRunStatus.replanned:
        return r'replanned';
    }
  }
}

/// @nodoc

extension TaskRunStatusMapperExtension on TaskRunStatus {
  dynamic toValue() {
    TaskRunStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskRunStatus>(this);
  }
}

/// @nodoc

class TaskToolCallOutcomeMapper extends EnumMapper<TaskToolCallOutcome> {
  TaskToolCallOutcomeMapper._();

  static TaskToolCallOutcomeMapper? _instance;
  static TaskToolCallOutcomeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskToolCallOutcomeMapper._());
    }
    return _instance!;
  }

  static TaskToolCallOutcome fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskToolCallOutcome decode(dynamic value) {
    switch (value) {
      case r'succeeded':
        return TaskToolCallOutcome.succeeded;
      case r'denied':
        return TaskToolCallOutcome.denied;
      case r'failed':
        return TaskToolCallOutcome.failed;
      case r'skipped':
        return TaskToolCallOutcome.skipped;
      default:
        return TaskToolCallOutcome.values[0];
    }
  }

  @override
  dynamic encode(TaskToolCallOutcome self) {
    switch (self) {
      case TaskToolCallOutcome.succeeded:
        return r'succeeded';
      case TaskToolCallOutcome.denied:
        return r'denied';
      case TaskToolCallOutcome.failed:
        return r'failed';
      case TaskToolCallOutcome.skipped:
        return r'skipped';
    }
  }
}

/// @nodoc

extension TaskToolCallOutcomeMapperExtension on TaskToolCallOutcome {
  String toValue() {
    TaskToolCallOutcomeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskToolCallOutcome>(this) as String;
  }
}

/// @nodoc
class TaskProjectCriterionMapper extends ClassMapperBase<TaskProjectCriterion> {
  TaskProjectCriterionMapper._();

  static TaskProjectCriterionMapper? _instance;
  static TaskProjectCriterionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskProjectCriterionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskProjectCriterion';

  static String _$id(TaskProjectCriterion v) => v.id;
  static const Field<TaskProjectCriterion, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$statement(TaskProjectCriterion v) => v.statement;
  static const Field<TaskProjectCriterion, String> _f$statement = Field(
    'statement',
    _$statement,
    hook: JsonStringHook(),
  );
  static bool _$required(TaskProjectCriterion v) => v.required;
  static const Field<TaskProjectCriterion, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
    hook: JsonBoolHook(fallback: true),
  );
  static String _$verificationMode(TaskProjectCriterion v) =>
      v.verificationMode;
  static const Field<TaskProjectCriterion, String> _f$verificationMode = Field(
    'verificationMode',
    _$verificationMode,
    opt: true,
    def: 'mixed',
    hook: JsonStringHook(fallback: 'mixed'),
  );

  @override
  final MappableFields<TaskProjectCriterion> fields = const {
    #id: _f$id,
    #statement: _f$statement,
    #required: _f$required,
    #verificationMode: _f$verificationMode,
  };
  @override
  final bool ignoreNull = true;

  static TaskProjectCriterion _instantiate(DecodingData data) {
    return TaskProjectCriterion(
      id: data.dec(_f$id),
      statement: data.dec(_f$statement),
      required: data.dec(_f$required),
      verificationMode: data.dec(_f$verificationMode),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskProjectCriterion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskProjectCriterion>(map);
  }

  static TaskProjectCriterion fromJson(String json) {
    return ensureInitialized().decodeJson<TaskProjectCriterion>(json);
  }
}

/// @nodoc
mixin TaskProjectCriterionMappable {
  String toJson() {
    return TaskProjectCriterionMapper.ensureInitialized()
        .encodeJson<TaskProjectCriterion>(this as TaskProjectCriterion);
  }

  Map<String, dynamic> toMap() {
    return TaskProjectCriterionMapper.ensureInitialized()
        .encodeMap<TaskProjectCriterion>(this as TaskProjectCriterion);
  }
}

/// @nodoc
class TaskProjectEvidenceExpectationMapper
    extends ClassMapperBase<TaskProjectEvidenceExpectation> {
  TaskProjectEvidenceExpectationMapper._();

  static TaskProjectEvidenceExpectationMapper? _instance;
  static TaskProjectEvidenceExpectationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = TaskProjectEvidenceExpectationMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'TaskProjectEvidenceExpectation';

  static String _$id(TaskProjectEvidenceExpectation v) => v.id;
  static const Field<TaskProjectEvidenceExpectation, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$type(TaskProjectEvidenceExpectation v) => v.type;
  static const Field<TaskProjectEvidenceExpectation, String> _f$type = Field(
    'type',
    _$type,
    opt: true,
    def: 'task_claim',
    hook: JsonStringHook(fallback: 'task_claim'),
  );
  static List<String> _$criterionIds(TaskProjectEvidenceExpectation v) =>
      v.criterionIds;
  static const Field<TaskProjectEvidenceExpectation, List<String>>
  _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static String _$description(TaskProjectEvidenceExpectation v) =>
      v.description;
  static const Field<TaskProjectEvidenceExpectation, String> _f$description =
      Field('description', _$description, hook: JsonStringHook());
  static bool _$required(TaskProjectEvidenceExpectation v) => v.required;
  static const Field<TaskProjectEvidenceExpectation, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
    hook: JsonBoolHook(fallback: true),
  );
  static String? _$sourceRef(TaskProjectEvidenceExpectation v) => v.sourceRef;
  static const Field<TaskProjectEvidenceExpectation, String> _f$sourceRef =
      Field(
        'sourceRef',
        _$sourceRef,
        opt: true,
        hook: JsonNullableStringHook(),
      );
  static Map<String, dynamic> _$details(TaskProjectEvidenceExpectation v) =>
      v.details;
  static const Field<TaskProjectEvidenceExpectation, Map<String, dynamic>>
  _f$details = Field(
    'details',
    _$details,
    opt: true,
    def: const {},
    hook: JsonMapValueHook(),
  );

  @override
  final MappableFields<TaskProjectEvidenceExpectation> fields = const {
    #id: _f$id,
    #type: _f$type,
    #criterionIds: _f$criterionIds,
    #description: _f$description,
    #required: _f$required,
    #sourceRef: _f$sourceRef,
    #details: _f$details,
  };
  @override
  final bool ignoreNull = true;

  static TaskProjectEvidenceExpectation _instantiate(DecodingData data) {
    return TaskProjectEvidenceExpectation(
      id: data.dec(_f$id),
      type: data.dec(_f$type),
      criterionIds: data.dec(_f$criterionIds),
      description: data.dec(_f$description),
      required: data.dec(_f$required),
      sourceRef: data.dec(_f$sourceRef),
      details: data.dec(_f$details),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskProjectEvidenceExpectation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskProjectEvidenceExpectation>(map);
  }

  static TaskProjectEvidenceExpectation fromJson(String json) {
    return ensureInitialized().decodeJson<TaskProjectEvidenceExpectation>(json);
  }
}

/// @nodoc
mixin TaskProjectEvidenceExpectationMappable {
  String toJson() {
    return TaskProjectEvidenceExpectationMapper.ensureInitialized()
        .encodeJson<TaskProjectEvidenceExpectation>(
          this as TaskProjectEvidenceExpectation,
        );
  }

  Map<String, dynamic> toMap() {
    return TaskProjectEvidenceExpectationMapper.ensureInitialized()
        .encodeMap<TaskProjectEvidenceExpectation>(
          this as TaskProjectEvidenceExpectation,
        );
  }
}

/// @nodoc
class RefinedTaskBriefMapper extends ClassMapperBase<RefinedTaskBrief> {
  RefinedTaskBriefMapper._();

  static RefinedTaskBriefMapper? _instance;
  static RefinedTaskBriefMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RefinedTaskBriefMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RefinedTaskBrief';

  static String _$title(RefinedTaskBrief v) => v.title;
  static const Field<RefinedTaskBrief, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static String _$goal(RefinedTaskBrief v) => v.goal;
  static const Field<RefinedTaskBrief, String> _f$goal = Field(
    'goal',
    _$goal,
    hook: JsonStringHook(),
  );
  static List<String> _$constraints(RefinedTaskBrief v) => v.constraints;
  static const Field<RefinedTaskBrief, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$successCriteria(RefinedTaskBrief v) =>
      v.successCriteria;
  static const Field<RefinedTaskBrief, List<String>> _f$successCriteria = Field(
    'successCriteria',
    _$successCriteria,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$assumptions(RefinedTaskBrief v) => v.assumptions;
  static const Field<RefinedTaskBrief, List<String>> _f$assumptions = Field(
    'assumptions',
    _$assumptions,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$questions(RefinedTaskBrief v) => v.questions;
  static const Field<RefinedTaskBrief, List<String>> _f$questions = Field(
    'questions',
    _$questions,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );

  @override
  final MappableFields<RefinedTaskBrief> fields = const {
    #title: _f$title,
    #goal: _f$goal,
    #constraints: _f$constraints,
    #successCriteria: _f$successCriteria,
    #assumptions: _f$assumptions,
    #questions: _f$questions,
  };

  @override
  final MappingHook hook = const JsonModelHook();
  static RefinedTaskBrief _instantiate(DecodingData data) {
    return RefinedTaskBrief(
      title: data.dec(_f$title),
      goal: data.dec(_f$goal),
      constraints: data.dec(_f$constraints),
      successCriteria: data.dec(_f$successCriteria),
      assumptions: data.dec(_f$assumptions),
      questions: data.dec(_f$questions),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RefinedTaskBrief fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RefinedTaskBrief>(map);
  }

  static RefinedTaskBrief fromJson(String json) {
    return ensureInitialized().decodeJson<RefinedTaskBrief>(json);
  }
}

/// @nodoc
mixin RefinedTaskBriefMappable {
  String toJson() {
    return RefinedTaskBriefMapper.ensureInitialized()
        .encodeJson<RefinedTaskBrief>(this as RefinedTaskBrief);
  }

  Map<String, dynamic> toMap() {
    return RefinedTaskBriefMapper.ensureInitialized()
        .encodeMap<RefinedTaskBrief>(this as RefinedTaskBrief);
  }
}

/// @nodoc
class TaskSnapshotAggregateMapper
    extends ClassMapperBase<TaskSnapshotAggregate> {
  TaskSnapshotAggregateMapper._();

  static TaskSnapshotAggregateMapper? _instance;
  static TaskSnapshotAggregateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskSnapshotAggregateMapper._());
      TaskGateMapper.ensureInitialized();
      TaskStepMapper.ensureInitialized();
      TaskStatusMapper.ensureInitialized();
      TaskPriorityMapper.ensureInitialized();
      TaskRiskMapper.ensureInitialized();
      ProjectRiskReductionMapper.ensureInitialized();
      TaskEffortMapper.ensureInitialized();
      TaskEvidenceExpectationMapper.ensureInitialized();
      TaskArtifactMapper.ensureInitialized();
      TaskFailureMapper.ensureInitialized();
      TaskRunMapper.ensureInitialized();
      PendingTaskApprovalMapper.ensureInitialized();
      PendingTaskQuestionMapper.ensureInitialized();
      PlanningMetricsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskSnapshotAggregate';

  static int _$persistenceRevision(TaskSnapshotAggregate v) =>
      v.persistenceRevision;
  static const Field<TaskSnapshotAggregate, int> _f$persistenceRevision = Field(
    'persistenceRevision',
    _$persistenceRevision,
    opt: true,
    def: 0,
    hook: JsonIntHook(min: 0),
  );
  static String _$id(TaskSnapshotAggregate v) => v.id;
  static const Field<TaskSnapshotAggregate, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$title(TaskSnapshotAggregate v) => v.title;
  static const Field<TaskSnapshotAggregate, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static String _$originalPrompt(TaskSnapshotAggregate v) => v.originalPrompt;
  static const Field<TaskSnapshotAggregate, String> _f$originalPrompt = Field(
    'originalPrompt',
    _$originalPrompt,
    opt: true,
    hook: JsonStringHook(),
  );
  static String _$objective(TaskSnapshotAggregate v) => v.objective;
  static const Field<TaskSnapshotAggregate, String> _f$objective = Field(
    'objective',
    _$objective,
    opt: true,
    hook: JsonStringHook(),
  );
  static List<String> _$constraints(TaskSnapshotAggregate v) => v.constraints;
  static const Field<TaskSnapshotAggregate, List<String>> _f$constraints =
      Field(
        'constraints',
        _$constraints,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static List<String> _$successCriteria(TaskSnapshotAggregate v) =>
      v.successCriteria;
  static const Field<TaskSnapshotAggregate, List<String>> _f$successCriteria =
      Field(
        'successCriteria',
        _$successCriteria,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static List<TaskGate> _$gates(TaskSnapshotAggregate v) => v.gates;
  static const Field<TaskSnapshotAggregate, List<TaskGate>> _f$gates = Field(
    'gates',
    _$gates,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static List<TaskStep> _$steps(TaskSnapshotAggregate v) => v.steps;
  static const Field<TaskSnapshotAggregate, List<TaskStep>> _f$steps = Field(
    'steps',
    _$steps,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static TaskStatus _$status(TaskSnapshotAggregate v) => v.status;
  static const Field<TaskSnapshotAggregate, TaskStatus> _f$status = Field(
    'status',
    _$status,
    opt: true,
    def: TaskStatus.paused,
  );
  static List<String> _$criterionIds(TaskSnapshotAggregate v) => v.criterionIds;
  static const Field<TaskSnapshotAggregate, List<String>> _f$criterionIds =
      Field(
        'criterionIds',
        _$criterionIds,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static String? _$milestoneId(TaskSnapshotAggregate v) => v.milestoneId;
  static const Field<TaskSnapshotAggregate, String> _f$milestoneId = Field(
    'milestoneId',
    _$milestoneId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static List<String> _$dependsOnTaskIds(TaskSnapshotAggregate v) =>
      v.dependsOnTaskIds;
  static const Field<TaskSnapshotAggregate, List<String>> _f$dependsOnTaskIds =
      Field(
        'dependsOnTaskIds',
        _$dependsOnTaskIds,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static TaskPriority _$priority(TaskSnapshotAggregate v) => v.priority;
  static const Field<TaskSnapshotAggregate, TaskPriority> _f$priority = Field(
    'priority',
    _$priority,
    opt: true,
    def: TaskPriority.normal,
  );
  static TaskRisk _$risk(TaskSnapshotAggregate v) => v.risk;
  static const Field<TaskSnapshotAggregate, TaskRisk> _f$risk = Field(
    'risk',
    _$risk,
    opt: true,
    def: TaskRisk.unknown,
  );
  static ProjectRiskReduction _$riskReduction(TaskSnapshotAggregate v) =>
      v.riskReduction;
  static const Field<TaskSnapshotAggregate, ProjectRiskReduction>
  _f$riskReduction = Field(
    'riskReduction',
    _$riskReduction,
    opt: true,
    def: ProjectRiskReduction.none,
  );
  static TaskEffort _$effort(TaskSnapshotAggregate v) => v.effort;
  static const Field<TaskSnapshotAggregate, TaskEffort> _f$effort = Field(
    'effort',
    _$effort,
    opt: true,
    def: TaskEffort.small,
  );
  static String _$selectionRationale(TaskSnapshotAggregate v) =>
      v.selectionRationale;
  static const Field<TaskSnapshotAggregate, String> _f$selectionRationale =
      Field(
        'selectionRationale',
        _$selectionRationale,
        opt: true,
        def: '',
        hook: JsonStringHook(),
      );
  static int _$revisionIntroduced(TaskSnapshotAggregate v) =>
      v.revisionIntroduced;
  static const Field<TaskSnapshotAggregate, int> _f$revisionIntroduced = Field(
    'revisionIntroduced',
    _$revisionIntroduced,
    opt: true,
    def: 1,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static int _$revisionUpdated(TaskSnapshotAggregate v) => v.revisionUpdated;
  static const Field<TaskSnapshotAggregate, int> _f$revisionUpdated = Field(
    'revisionUpdated',
    _$revisionUpdated,
    opt: true,
    def: 1,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static List<TaskEvidenceExpectation> _$expectedEvidence(
    TaskSnapshotAggregate v,
  ) => v.expectedEvidence;
  static const Field<TaskSnapshotAggregate, List<TaskEvidenceExpectation>>
  _f$expectedEvidence = Field(
    'expectedEvidence',
    _$expectedEvidence,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static List<String> _$readPaths(TaskSnapshotAggregate v) => v.readPaths;
  static const Field<TaskSnapshotAggregate, List<String>> _f$readPaths = Field(
    'readPaths',
    _$readPaths,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$writePaths(TaskSnapshotAggregate v) => v.writePaths;
  static const Field<TaskSnapshotAggregate, List<String>> _f$writePaths = Field(
    'writePaths',
    _$writePaths,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$doneCriteria(TaskSnapshotAggregate v) => v.doneCriteria;
  static const Field<TaskSnapshotAggregate, List<String>> _f$doneCriteria =
      Field(
        'doneCriteria',
        _$doneCriteria,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static List<String> _$outOfScope(TaskSnapshotAggregate v) => v.outOfScope;
  static const Field<TaskSnapshotAggregate, List<String>> _f$outOfScope = Field(
    'outOfScope',
    _$outOfScope,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$context(TaskSnapshotAggregate v) => v.context;
  static const Field<TaskSnapshotAggregate, List<String>> _f$context = Field(
    'context',
    _$context,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<TaskArtifact> _$expectedArtifacts(TaskSnapshotAggregate v) =>
      v.expectedArtifacts;
  static const Field<TaskSnapshotAggregate, List<TaskArtifact>>
  _f$expectedArtifacts = Field(
    'expectedArtifacts',
    _$expectedArtifacts,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static String? _$recoveryIncidentId(TaskSnapshotAggregate v) =>
      v.recoveryIncidentId;
  static const Field<TaskSnapshotAggregate, String> _f$recoveryIncidentId =
      Field(
        'recoveryIncidentId',
        _$recoveryIncidentId,
        opt: true,
        hook: JsonNullableStringHook(),
      );
  static String _$fingerprint(TaskSnapshotAggregate v) => v.fingerprint;
  static const Field<TaskSnapshotAggregate, String> _f$fingerprint = Field(
    'fingerprint',
    _$fingerprint,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static String? _$rejectionReason(TaskSnapshotAggregate v) =>
      v.rejectionReason;
  static const Field<TaskSnapshotAggregate, String> _f$rejectionReason = Field(
    'rejectionReason',
    _$rejectionReason,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskFailure? _$failure(TaskSnapshotAggregate v) => v.failure;
  static const Field<TaskSnapshotAggregate, TaskFailure> _f$failure = Field(
    'failure',
    _$failure,
    opt: true,
  );
  static String? _$currentStepId(TaskSnapshotAggregate v) => v.currentStepId;
  static const Field<TaskSnapshotAggregate, String> _f$currentStepId = Field(
    'currentStepId',
    _$currentStepId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$memorySummary(TaskSnapshotAggregate v) => v.memorySummary;
  static const Field<TaskSnapshotAggregate, String> _f$memorySummary = Field(
    'memorySummary',
    _$memorySummary,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static List<TaskRun> _$runs(TaskSnapshotAggregate v) => v.runs;
  static const Field<TaskSnapshotAggregate, List<TaskRun>> _f$runs = Field(
    'runs',
    _$runs,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static DateTime _$createdAt(TaskSnapshotAggregate v) => v.createdAt;
  static const Field<TaskSnapshotAggregate, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(TaskSnapshotAggregate v) => v.updatedAt;
  static const Field<TaskSnapshotAggregate, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static PendingTaskApproval? _$pendingApproval(TaskSnapshotAggregate v) =>
      v.pendingApproval;
  static const Field<TaskSnapshotAggregate, PendingTaskApproval>
  _f$pendingApproval = Field('pendingApproval', _$pendingApproval, opt: true);
  static PendingTaskQuestion? _$pendingQuestion(TaskSnapshotAggregate v) =>
      v.pendingQuestion;
  static const Field<TaskSnapshotAggregate, PendingTaskQuestion>
  _f$pendingQuestion = Field('pendingQuestion', _$pendingQuestion, opt: true);
  static String? _$chatSessionId(TaskSnapshotAggregate v) => v.chatSessionId;
  static const Field<TaskSnapshotAggregate, String> _f$chatSessionId = Field(
    'chatSessionId',
    _$chatSessionId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$projectId(TaskSnapshotAggregate v) => v.projectId;
  static const Field<TaskSnapshotAggregate, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static PlanningMetrics _$planningMetrics(TaskSnapshotAggregate v) =>
      v.planningMetrics;
  static const Field<TaskSnapshotAggregate, PlanningMetrics>
  _f$planningMetrics = Field(
    'planningMetrics',
    _$planningMetrics,
    opt: true,
    def: const PlanningMetrics(),
  );
  static String? _$planningError(TaskSnapshotAggregate v) => v.planningError;
  static const Field<TaskSnapshotAggregate, String> _f$planningError = Field(
    'planningError',
    _$planningError,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static DateTime? _$completedAt(TaskSnapshotAggregate v) => v.completedAt;
  static const Field<TaskSnapshotAggregate, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<TaskSnapshotAggregate> fields = const {
    #persistenceRevision: _f$persistenceRevision,
    #id: _f$id,
    #title: _f$title,
    #originalPrompt: _f$originalPrompt,
    #objective: _f$objective,
    #constraints: _f$constraints,
    #successCriteria: _f$successCriteria,
    #gates: _f$gates,
    #steps: _f$steps,
    #status: _f$status,
    #criterionIds: _f$criterionIds,
    #milestoneId: _f$milestoneId,
    #dependsOnTaskIds: _f$dependsOnTaskIds,
    #priority: _f$priority,
    #risk: _f$risk,
    #riskReduction: _f$riskReduction,
    #effort: _f$effort,
    #selectionRationale: _f$selectionRationale,
    #revisionIntroduced: _f$revisionIntroduced,
    #revisionUpdated: _f$revisionUpdated,
    #expectedEvidence: _f$expectedEvidence,
    #readPaths: _f$readPaths,
    #writePaths: _f$writePaths,
    #doneCriteria: _f$doneCriteria,
    #outOfScope: _f$outOfScope,
    #context: _f$context,
    #expectedArtifacts: _f$expectedArtifacts,
    #recoveryIncidentId: _f$recoveryIncidentId,
    #fingerprint: _f$fingerprint,
    #rejectionReason: _f$rejectionReason,
    #failure: _f$failure,
    #currentStepId: _f$currentStepId,
    #memorySummary: _f$memorySummary,
    #runs: _f$runs,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #pendingApproval: _f$pendingApproval,
    #pendingQuestion: _f$pendingQuestion,
    #chatSessionId: _f$chatSessionId,
    #projectId: _f$projectId,
    #planningMetrics: _f$planningMetrics,
    #planningError: _f$planningError,
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const TaskJsonHook();
  static TaskSnapshotAggregate _instantiate(DecodingData data) {
    return TaskSnapshotAggregate(
      persistenceRevision: data.dec(_f$persistenceRevision),
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      originalPrompt: data.dec(_f$originalPrompt),
      objective: data.dec(_f$objective),
      constraints: data.dec(_f$constraints),
      successCriteria: data.dec(_f$successCriteria),
      gates: data.dec(_f$gates),
      steps: data.dec(_f$steps),
      status: data.dec(_f$status),
      criterionIds: data.dec(_f$criterionIds),
      milestoneId: data.dec(_f$milestoneId),
      dependsOnTaskIds: data.dec(_f$dependsOnTaskIds),
      priority: data.dec(_f$priority),
      risk: data.dec(_f$risk),
      riskReduction: data.dec(_f$riskReduction),
      effort: data.dec(_f$effort),
      selectionRationale: data.dec(_f$selectionRationale),
      revisionIntroduced: data.dec(_f$revisionIntroduced),
      revisionUpdated: data.dec(_f$revisionUpdated),
      expectedEvidence: data.dec(_f$expectedEvidence),
      readPaths: data.dec(_f$readPaths),
      writePaths: data.dec(_f$writePaths),
      doneCriteria: data.dec(_f$doneCriteria),
      outOfScope: data.dec(_f$outOfScope),
      context: data.dec(_f$context),
      expectedArtifacts: data.dec(_f$expectedArtifacts),
      recoveryIncidentId: data.dec(_f$recoveryIncidentId),
      fingerprint: data.dec(_f$fingerprint),
      rejectionReason: data.dec(_f$rejectionReason),
      failure: data.dec(_f$failure),
      currentStepId: data.dec(_f$currentStepId),
      memorySummary: data.dec(_f$memorySummary),
      runs: data.dec(_f$runs),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      pendingApproval: data.dec(_f$pendingApproval),
      pendingQuestion: data.dec(_f$pendingQuestion),
      chatSessionId: data.dec(_f$chatSessionId),
      projectId: data.dec(_f$projectId),
      planningMetrics: data.dec(_f$planningMetrics),
      planningError: data.dec(_f$planningError),
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskSnapshotAggregate fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskSnapshotAggregate>(map);
  }

  static TaskSnapshotAggregate fromJson(String json) {
    return ensureInitialized().decodeJson<TaskSnapshotAggregate>(json);
  }
}

/// @nodoc
mixin TaskSnapshotAggregateMappable {
  String toJson() {
    return TaskSnapshotAggregateMapper.ensureInitialized()
        .encodeJson<TaskSnapshotAggregate>(this as TaskSnapshotAggregate);
  }

  Map<String, dynamic> toMap() {
    return TaskSnapshotAggregateMapper.ensureInitialized()
        .encodeMap<TaskSnapshotAggregate>(this as TaskSnapshotAggregate);
  }
}

/// @nodoc
class TaskStepMapper extends ClassMapperBase<TaskStep> {
  TaskStepMapper._();

  static TaskStepMapper? _instance;
  static TaskStepMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskStepMapper._());
      TaskArtifactMapper.ensureInitialized();
      TaskGateMapper.ensureInitialized();
      TaskStepStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskStep';

  static String _$id(TaskStep v) => v.id;
  static const Field<TaskStep, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$title(TaskStep v) => v.title;
  static const Field<TaskStep, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled step'),
  );
  static String _$objective(TaskStep v) => v.objective;
  static const Field<TaskStep, String> _f$objective = Field(
    'objective',
    _$objective,
    hook: JsonStringHook(),
  );
  static List<String> _$instructions(TaskStep v) => v.instructions;
  static const Field<TaskStep, List<String>> _f$instructions = Field(
    'instructions',
    _$instructions,
    hook: JsonStringListHook(),
  );
  static bool _$mayEditFiles(TaskStep v) => v.mayEditFiles;
  static const Field<TaskStep, bool> _f$mayEditFiles = Field(
    'mayEditFiles',
    _$mayEditFiles,
    hook: JsonBoolHook(),
  );
  static List<TaskArtifact> _$artifacts(TaskStep v) => v.artifacts;
  static const Field<TaskStep, List<TaskArtifact>> _f$artifacts = Field(
    'artifacts',
    _$artifacts,
    hook: JsonObjectListHook(),
  );
  static List<TaskGate> _$gates(TaskStep v) => v.gates;
  static const Field<TaskStep, List<TaskGate>> _f$gates = Field(
    'gates',
    _$gates,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static TaskStepStatus _$status(TaskStep v) => v.status;
  static const Field<TaskStep, TaskStepStatus> _f$status = Field(
    'status',
    _$status,
  );

  @override
  final MappableFields<TaskStep> fields = const {
    #id: _f$id,
    #title: _f$title,
    #objective: _f$objective,
    #instructions: _f$instructions,
    #mayEditFiles: _f$mayEditFiles,
    #artifacts: _f$artifacts,
    #gates: _f$gates,
    #status: _f$status,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const JsonModelHook(omitEmpty: {'gates'});
  static TaskStep _instantiate(DecodingData data) {
    return TaskStep(
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      objective: data.dec(_f$objective),
      instructions: data.dec(_f$instructions),
      mayEditFiles: data.dec(_f$mayEditFiles),
      artifacts: data.dec(_f$artifacts),
      gates: data.dec(_f$gates),
      status: data.dec(_f$status),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskStep fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskStep>(map);
  }

  static TaskStep fromJson(String json) {
    return ensureInitialized().decodeJson<TaskStep>(json);
  }
}

/// @nodoc
mixin TaskStepMappable {
  String toJson() {
    return TaskStepMapper.ensureInitialized().encodeJson<TaskStep>(
      this as TaskStep,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskStepMapper.ensureInitialized().encodeMap<TaskStep>(
      this as TaskStep,
    );
  }
}

/// @nodoc
class TaskRunMapper extends ClassMapperBase<TaskRun> {
  TaskRunMapper._();

  static TaskRunMapper? _instance;
  static TaskRunMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskRunMapper._());
      TaskRunStatusMapper.ensureInitialized();
      TaskToolCallRecordMapper.ensureInitialized();
      TaskArtifactMapper.ensureInitialized();
      TaskGateResultMapper.ensureInitialized();
      TaskEvidenceClaimMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskRun';

  static String _$runId(TaskRun v) => v.runId;
  static const Field<TaskRun, String> _f$runId = Field(
    'runId',
    _$runId,
    hook: JsonStringHook(),
  );
  static String _$stepId(TaskRun v) => v.stepId;
  static const Field<TaskRun, String> _f$stepId = Field(
    'stepId',
    _$stepId,
    hook: JsonStringHook(),
  );
  static TaskRunStatus _$status(TaskRun v) => v.status;
  static const Field<TaskRun, TaskRunStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String _$summary(TaskRun v) => v.summary;
  static const Field<TaskRun, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static String _$memoryUpdate(TaskRun v) => v.memoryUpdate;
  static const Field<TaskRun, String> _f$memoryUpdate = Field(
    'memoryUpdate',
    _$memoryUpdate,
    hook: JsonStringHook(),
  );
  static List<TaskToolCallRecord> _$toolCalls(TaskRun v) => v.toolCalls;
  static const Field<TaskRun, List<TaskToolCallRecord>> _f$toolCalls = Field(
    'toolCalls',
    _$toolCalls,
    hook: JsonObjectListHook(),
  );
  static List<TaskArtifact> _$artifacts(TaskRun v) => v.artifacts;
  static const Field<TaskRun, List<TaskArtifact>> _f$artifacts = Field(
    'artifacts',
    _$artifacts,
    hook: JsonObjectListHook(),
  );
  static List<TaskGateResult> _$gateResults(TaskRun v) => v.gateResults;
  static const Field<TaskRun, List<TaskGateResult>> _f$gateResults = Field(
    'gateResults',
    _$gateResults,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static List<TaskEvidenceClaim> _$evidenceClaims(TaskRun v) =>
      v.evidenceClaims;
  static const Field<TaskRun, List<TaskEvidenceClaim>> _f$evidenceClaims =
      Field(
        'evidenceClaims',
        _$evidenceClaims,
        opt: true,
        def: const [],
        hook: JsonObjectListHook(),
      );
  static DateTime _$startedAt(TaskRun v) => v.startedAt;
  static const Field<TaskRun, DateTime> _f$startedAt = Field(
    'startedAt',
    _$startedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$completedAt(TaskRun v) => v.completedAt;
  static const Field<TaskRun, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );
  static String? _$replanReason(TaskRun v) => v.replanReason;
  static const Field<TaskRun, String> _f$replanReason = Field(
    'replanReason',
    _$replanReason,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$error(TaskRun v) => v.error;
  static const Field<TaskRun, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<TaskRun> fields = const {
    #runId: _f$runId,
    #stepId: _f$stepId,
    #status: _f$status,
    #summary: _f$summary,
    #memoryUpdate: _f$memoryUpdate,
    #toolCalls: _f$toolCalls,
    #artifacts: _f$artifacts,
    #gateResults: _f$gateResults,
    #evidenceClaims: _f$evidenceClaims,
    #startedAt: _f$startedAt,
    #completedAt: _f$completedAt,
    #replanReason: _f$replanReason,
    #error: _f$error,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const JsonModelHook(
    omitEmpty: {'gateResults', 'evidenceClaims'},
  );
  static TaskRun _instantiate(DecodingData data) {
    return TaskRun(
      runId: data.dec(_f$runId),
      stepId: data.dec(_f$stepId),
      status: data.dec(_f$status),
      summary: data.dec(_f$summary),
      memoryUpdate: data.dec(_f$memoryUpdate),
      toolCalls: data.dec(_f$toolCalls),
      artifacts: data.dec(_f$artifacts),
      gateResults: data.dec(_f$gateResults),
      evidenceClaims: data.dec(_f$evidenceClaims),
      startedAt: data.dec(_f$startedAt),
      completedAt: data.dec(_f$completedAt),
      replanReason: data.dec(_f$replanReason),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskRun fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskRun>(map);
  }

  static TaskRun fromJson(String json) {
    return ensureInitialized().decodeJson<TaskRun>(json);
  }
}

/// @nodoc
mixin TaskRunMappable {
  String toJson() {
    return TaskRunMapper.ensureInitialized().encodeJson<TaskRun>(
      this as TaskRun,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskRunMapper.ensureInitialized().encodeMap<TaskRun>(
      this as TaskRun,
    );
  }
}

/// @nodoc
class TaskToolCallRecordMapper extends ClassMapperBase<TaskToolCallRecord> {
  TaskToolCallRecordMapper._();

  static TaskToolCallRecordMapper? _instance;
  static TaskToolCallRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskToolCallRecordMapper._());
      TaskToolCallOutcomeMapper.ensureInitialized();
      TaskToolErrorMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskToolCallRecord';

  static String _$id(TaskToolCallRecord v) => v.id;
  static const Field<TaskToolCallRecord, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$stepId(TaskToolCallRecord v) => v.stepId;
  static const Field<TaskToolCallRecord, String> _f$stepId = Field(
    'stepId',
    _$stepId,
    hook: JsonStringHook(),
  );
  static String _$runId(TaskToolCallRecord v) => v.runId;
  static const Field<TaskToolCallRecord, String> _f$runId = Field(
    'runId',
    _$runId,
    hook: JsonStringHook(),
  );
  static String _$toolName(TaskToolCallRecord v) => v.toolName;
  static const Field<TaskToolCallRecord, String> _f$toolName = Field(
    'toolName',
    _$toolName,
    hook: JsonStringHook(),
  );
  static DateTime _$timestamp(TaskToolCallRecord v) => v.timestamp;
  static const Field<TaskToolCallRecord, DateTime> _f$timestamp = Field(
    'timestamp',
    _$timestamp,
    hook: JsonDateHook(),
  );
  static Object? _$arguments(TaskToolCallRecord v) => v.arguments;
  static const Field<TaskToolCallRecord, Object> _f$arguments = Field(
    'arguments',
    _$arguments,
    opt: true,
  );
  static Object? _$result(TaskToolCallRecord v) => v.result;
  static const Field<TaskToolCallRecord, Object> _f$result = Field(
    'result',
    _$result,
    opt: true,
  );
  static String? _$resultSummary(TaskToolCallRecord v) => v.resultSummary;
  static const Field<TaskToolCallRecord, String> _f$resultSummary = Field(
    'resultSummary',
    _$resultSummary,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskToolCallOutcome _$outcome(TaskToolCallRecord v) => v.outcome;
  static const Field<TaskToolCallRecord, TaskToolCallOutcome> _f$outcome =
      Field(
        'outcome',
        _$outcome,
        opt: true,
        def: TaskToolCallOutcome.succeeded,
      );
  static String? _$operationKey(TaskToolCallRecord v) => v.operationKey;
  static const Field<TaskToolCallRecord, String> _f$operationKey = Field(
    'operationKey',
    _$operationKey,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskToolError? _$toolError(TaskToolCallRecord v) => v.toolError;
  static const Field<TaskToolCallRecord, TaskToolError> _f$toolError = Field(
    'toolError',
    _$toolError,
    opt: true,
  );

  @override
  final MappableFields<TaskToolCallRecord> fields = const {
    #id: _f$id,
    #stepId: _f$stepId,
    #runId: _f$runId,
    #toolName: _f$toolName,
    #timestamp: _f$timestamp,
    #arguments: _f$arguments,
    #result: _f$result,
    #resultSummary: _f$resultSummary,
    #outcome: _f$outcome,
    #operationKey: _f$operationKey,
    #toolError: _f$toolError,
  };
  @override
  final bool ignoreNull = true;

  static TaskToolCallRecord _instantiate(DecodingData data) {
    return TaskToolCallRecord(
      id: data.dec(_f$id),
      stepId: data.dec(_f$stepId),
      runId: data.dec(_f$runId),
      toolName: data.dec(_f$toolName),
      timestamp: data.dec(_f$timestamp),
      arguments: data.dec(_f$arguments),
      result: data.dec(_f$result),
      resultSummary: data.dec(_f$resultSummary),
      outcome: data.dec(_f$outcome),
      operationKey: data.dec(_f$operationKey),
      toolError: data.dec(_f$toolError),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskToolCallRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskToolCallRecord>(map);
  }

  static TaskToolCallRecord fromJson(String json) {
    return ensureInitialized().decodeJson<TaskToolCallRecord>(json);
  }
}

/// @nodoc
mixin TaskToolCallRecordMappable {
  String toJson() {
    return TaskToolCallRecordMapper.ensureInitialized()
        .encodeJson<TaskToolCallRecord>(this as TaskToolCallRecord);
  }

  Map<String, dynamic> toMap() {
    return TaskToolCallRecordMapper.ensureInitialized()
        .encodeMap<TaskToolCallRecord>(this as TaskToolCallRecord);
  }
}

/// @nodoc
class PendingTaskApprovalMapper extends ClassMapperBase<PendingTaskApproval> {
  PendingTaskApprovalMapper._();

  static PendingTaskApprovalMapper? _instance;
  static PendingTaskApprovalMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PendingTaskApprovalMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PendingTaskApproval';

  static String _$stepId(PendingTaskApproval v) => v.stepId;
  static const Field<PendingTaskApproval, String> _f$stepId = Field(
    'stepId',
    _$stepId,
    hook: JsonStringHook(),
  );
  static String _$reason(PendingTaskApproval v) => v.reason;
  static const Field<PendingTaskApproval, String> _f$reason = Field(
    'reason',
    _$reason,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(PendingTaskApproval v) => v.createdAt;
  static const Field<PendingTaskApproval, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<PendingTaskApproval> fields = const {
    #stepId: _f$stepId,
    #reason: _f$reason,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  static PendingTaskApproval _instantiate(DecodingData data) {
    return PendingTaskApproval(
      stepId: data.dec(_f$stepId),
      reason: data.dec(_f$reason),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PendingTaskApproval fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PendingTaskApproval>(map);
  }

  static PendingTaskApproval fromJson(String json) {
    return ensureInitialized().decodeJson<PendingTaskApproval>(json);
  }
}

/// @nodoc
mixin PendingTaskApprovalMappable {
  String toJson() {
    return PendingTaskApprovalMapper.ensureInitialized()
        .encodeJson<PendingTaskApproval>(this as PendingTaskApproval);
  }

  Map<String, dynamic> toMap() {
    return PendingTaskApprovalMapper.ensureInitialized()
        .encodeMap<PendingTaskApproval>(this as PendingTaskApproval);
  }
}

/// @nodoc
class PendingTaskQuestionMapper extends ClassMapperBase<PendingTaskQuestion> {
  PendingTaskQuestionMapper._();

  static PendingTaskQuestionMapper? _instance;
  static PendingTaskQuestionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PendingTaskQuestionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PendingTaskQuestion';

  static String _$id(PendingTaskQuestion v) => v.id;
  static const Field<PendingTaskQuestion, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$stepId(PendingTaskQuestion v) => v.stepId;
  static const Field<PendingTaskQuestion, String> _f$stepId = Field(
    'stepId',
    _$stepId,
    hook: JsonStringHook(),
  );
  static String _$question(PendingTaskQuestion v) => v.question;
  static const Field<PendingTaskQuestion, String> _f$question = Field(
    'question',
    _$question,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(PendingTaskQuestion v) => v.createdAt;
  static const Field<PendingTaskQuestion, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<PendingTaskQuestion> fields = const {
    #id: _f$id,
    #stepId: _f$stepId,
    #question: _f$question,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  static PendingTaskQuestion _instantiate(DecodingData data) {
    return PendingTaskQuestion(
      id: data.dec(_f$id),
      stepId: data.dec(_f$stepId),
      question: data.dec(_f$question),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PendingTaskQuestion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PendingTaskQuestion>(map);
  }

  static PendingTaskQuestion fromJson(String json) {
    return ensureInitialized().decodeJson<PendingTaskQuestion>(json);
  }
}

/// @nodoc
mixin PendingTaskQuestionMappable {
  String toJson() {
    return PendingTaskQuestionMapper.ensureInitialized()
        .encodeJson<PendingTaskQuestion>(this as PendingTaskQuestion);
  }

  Map<String, dynamic> toMap() {
    return PendingTaskQuestionMapper.ensureInitialized()
        .encodeMap<PendingTaskQuestion>(this as PendingTaskQuestion);
  }
}

