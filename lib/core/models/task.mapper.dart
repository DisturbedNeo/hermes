// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'task.dart';

/// @nodoc

class TaskStatusMapper extends EnumMapper<TaskStatus> {
  TaskStatusMapper._();

  static TaskStatusMapper? _instance;
  static TaskStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskStatusMapper._());
    }
    return _instance!;
  }

  static TaskStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskStatus decode(dynamic value) {
    switch (value) {
      case r'draft':
        return TaskStatus.draft;
      case r'queued':
        return TaskStatus.queued;
      case r'planned':
        return TaskStatus.planned;
      case r'running':
        return TaskStatus.running;
      case r'paused':
        return TaskStatus.paused;
      case r'blocked':
        return TaskStatus.blocked;
      case r'completed':
        return TaskStatus.completed;
      case r'failed':
        return TaskStatus.failed;
      case r'rejected':
        return TaskStatus.rejected;
      case r'split':
        return TaskStatus.split;
      case r'deferred':
        return TaskStatus.deferred;
      case r'obsolete':
        return TaskStatus.obsolete;
      case r'cancelled':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.values[4];
    }
  }

  @override
  dynamic encode(TaskStatus self) {
    switch (self) {
      case TaskStatus.draft:
        return r'draft';
      case TaskStatus.queued:
        return r'queued';
      case TaskStatus.planned:
        return r'planned';
      case TaskStatus.running:
        return r'running';
      case TaskStatus.paused:
        return r'paused';
      case TaskStatus.blocked:
        return r'blocked';
      case TaskStatus.completed:
        return r'completed';
      case TaskStatus.failed:
        return r'failed';
      case TaskStatus.rejected:
        return r'rejected';
      case TaskStatus.split:
        return r'split';
      case TaskStatus.deferred:
        return r'deferred';
      case TaskStatus.obsolete:
        return r'obsolete';
      case TaskStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension TaskStatusMapperExtension on TaskStatus {
  String toValue() {
    TaskStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskStatus>(this) as String;
  }
}

/// @nodoc

class TaskPriorityMapper extends EnumMapper<TaskPriority> {
  TaskPriorityMapper._();

  static TaskPriorityMapper? _instance;
  static TaskPriorityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskPriorityMapper._());
    }
    return _instance!;
  }

  static TaskPriority fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskPriority decode(dynamic value) {
    switch (value) {
      case r'critical':
        return TaskPriority.critical;
      case r'high':
        return TaskPriority.high;
      case r'normal':
        return TaskPriority.normal;
      case r'low':
        return TaskPriority.low;
      default:
        return TaskPriority.values[2];
    }
  }

  @override
  dynamic encode(TaskPriority self) {
    switch (self) {
      case TaskPriority.critical:
        return r'critical';
      case TaskPriority.high:
        return r'high';
      case TaskPriority.normal:
        return r'normal';
      case TaskPriority.low:
        return r'low';
    }
  }
}

/// @nodoc

extension TaskPriorityMapperExtension on TaskPriority {
  String toValue() {
    TaskPriorityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskPriority>(this) as String;
  }
}

/// @nodoc

class TaskRiskMapper extends EnumMapper<TaskRisk> {
  TaskRiskMapper._();

  static TaskRiskMapper? _instance;
  static TaskRiskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskRiskMapper._());
    }
    return _instance!;
  }

  static TaskRisk fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskRisk decode(dynamic value) {
    switch (value) {
      case r'high':
        return TaskRisk.high;
      case r'medium':
        return TaskRisk.medium;
      case r'low':
        return TaskRisk.low;
      case r'unknown':
        return TaskRisk.unknown;
      default:
        return TaskRisk.values[3];
    }
  }

  @override
  dynamic encode(TaskRisk self) {
    switch (self) {
      case TaskRisk.high:
        return r'high';
      case TaskRisk.medium:
        return r'medium';
      case TaskRisk.low:
        return r'low';
      case TaskRisk.unknown:
        return r'unknown';
    }
  }
}

/// @nodoc

extension TaskRiskMapperExtension on TaskRisk {
  String toValue() {
    TaskRiskMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskRisk>(this) as String;
  }
}

/// @nodoc

class ProjectRiskReductionMapper extends EnumMapper<ProjectRiskReduction> {
  ProjectRiskReductionMapper._();

  static ProjectRiskReductionMapper? _instance;
  static ProjectRiskReductionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectRiskReductionMapper._());
    }
    return _instance!;
  }

  static ProjectRiskReduction fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectRiskReduction decode(dynamic value) {
    switch (value) {
      case r'high':
        return ProjectRiskReduction.high;
      case r'medium':
        return ProjectRiskReduction.medium;
      case r'low':
        return ProjectRiskReduction.low;
      case r'none':
        return ProjectRiskReduction.none;
      default:
        return ProjectRiskReduction.values[3];
    }
  }

  @override
  dynamic encode(ProjectRiskReduction self) {
    switch (self) {
      case ProjectRiskReduction.high:
        return r'high';
      case ProjectRiskReduction.medium:
        return r'medium';
      case ProjectRiskReduction.low:
        return r'low';
      case ProjectRiskReduction.none:
        return r'none';
    }
  }
}

/// @nodoc

extension ProjectRiskReductionMapperExtension on ProjectRiskReduction {
  String toValue() {
    ProjectRiskReductionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectRiskReduction>(this)
        as String;
  }
}

/// @nodoc

class TaskEffortMapper extends EnumMapper<TaskEffort> {
  TaskEffortMapper._();

  static TaskEffortMapper? _instance;
  static TaskEffortMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskEffortMapper._());
    }
    return _instance!;
  }

  static TaskEffort fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskEffort decode(dynamic value) {
    switch (value) {
      case r'small':
        return TaskEffort.small;
      case r'medium':
        return TaskEffort.medium;
      case r'large':
        return TaskEffort.large;
      default:
        return TaskEffort.values[0];
    }
  }

  @override
  dynamic encode(TaskEffort self) {
    switch (self) {
      case TaskEffort.small:
        return r'small';
      case TaskEffort.medium:
        return r'medium';
      case TaskEffort.large:
        return r'large';
    }
  }
}

/// @nodoc

extension TaskEffortMapperExtension on TaskEffort {
  String toValue() {
    TaskEffortMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskEffort>(this) as String;
  }
}

/// @nodoc

class ProjectEvidenceTypeMapper extends EnumMapper<ProjectEvidenceType> {
  ProjectEvidenceTypeMapper._();

  static ProjectEvidenceTypeMapper? _instance;
  static ProjectEvidenceTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectEvidenceTypeMapper._());
    }
    return _instance!;
  }

  static ProjectEvidenceType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectEvidenceType decode(dynamic value) {
    switch (value) {
      case r'gate':
        return ProjectEvidenceType.gate;
      case r'artifact':
        return ProjectEvidenceType.artifact;
      case r'command':
        return ProjectEvidenceType.command;
      case 'task_claim':
        return ProjectEvidenceType.taskClaim;
      case 'user_approval':
        return ProjectEvidenceType.userApproval;
      default:
        return ProjectEvidenceType.values[3];
    }
  }

  @override
  dynamic encode(ProjectEvidenceType self) {
    switch (self) {
      case ProjectEvidenceType.gate:
        return r'gate';
      case ProjectEvidenceType.artifact:
        return r'artifact';
      case ProjectEvidenceType.command:
        return r'command';
      case ProjectEvidenceType.taskClaim:
        return 'task_claim';
      case ProjectEvidenceType.userApproval:
        return 'user_approval';
    }
  }
}

/// @nodoc

extension ProjectEvidenceTypeMapperExtension on ProjectEvidenceType {
  dynamic toValue() {
    ProjectEvidenceTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectEvidenceType>(this);
  }
}

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

class TaskGateStatusMapper extends EnumMapper<TaskGateStatus> {
  TaskGateStatusMapper._();

  static TaskGateStatusMapper? _instance;
  static TaskGateStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskGateStatusMapper._());
    }
    return _instance!;
  }

  static TaskGateStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskGateStatus decode(dynamic value) {
    switch (value) {
      case r'passed':
        return TaskGateStatus.passed;
      case r'failed':
        return TaskGateStatus.failed;
      case r'pending':
        return TaskGateStatus.pending;
      case r'advisory':
        return TaskGateStatus.advisory;
      default:
        return TaskGateStatus.values[2];
    }
  }

  @override
  dynamic encode(TaskGateStatus self) {
    switch (self) {
      case TaskGateStatus.passed:
        return r'passed';
      case TaskGateStatus.failed:
        return r'failed';
      case TaskGateStatus.pending:
        return r'pending';
      case TaskGateStatus.advisory:
        return r'advisory';
    }
  }
}

/// @nodoc

extension TaskGateStatusMapperExtension on TaskGateStatus {
  String toValue() {
    TaskGateStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskGateStatus>(this) as String;
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

class TaskToolErrorDispositionMapper
    extends EnumMapper<TaskToolErrorDisposition> {
  TaskToolErrorDispositionMapper._();

  static TaskToolErrorDispositionMapper? _instance;
  static TaskToolErrorDispositionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = TaskToolErrorDispositionMapper._(),
      );
    }
    return _instance!;
  }

  static TaskToolErrorDisposition fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskToolErrorDisposition decode(dynamic value) {
    switch (value) {
      case r'advisory':
        return TaskToolErrorDisposition.advisory;
      case r'retryable':
        return TaskToolErrorDisposition.retryable;
      case r'fatal':
        return TaskToolErrorDisposition.fatal;
      default:
        return TaskToolErrorDisposition.values[2];
    }
  }

  @override
  dynamic encode(TaskToolErrorDisposition self) {
    switch (self) {
      case TaskToolErrorDisposition.advisory:
        return r'advisory';
      case TaskToolErrorDisposition.retryable:
        return r'retryable';
      case TaskToolErrorDisposition.fatal:
        return r'fatal';
    }
  }
}

/// @nodoc

extension TaskToolErrorDispositionMapperExtension on TaskToolErrorDisposition {
  String toValue() {
    TaskToolErrorDispositionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskToolErrorDisposition>(this)
        as String;
  }
}

/// @nodoc

class TaskGateFailureDispositionMapper
    extends EnumMapper<TaskGateFailureDisposition> {
  TaskGateFailureDispositionMapper._();

  static TaskGateFailureDispositionMapper? _instance;
  static TaskGateFailureDispositionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = TaskGateFailureDispositionMapper._(),
      );
    }
    return _instance!;
  }

  static TaskGateFailureDisposition fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskGateFailureDisposition decode(dynamic value) {
    switch (value) {
      case r'repairable':
        return TaskGateFailureDisposition.repairable;
      case r'blocking':
        return TaskGateFailureDisposition.blocking;
      default:
        return TaskGateFailureDisposition.values[0];
    }
  }

  @override
  dynamic encode(TaskGateFailureDisposition self) {
    switch (self) {
      case TaskGateFailureDisposition.repairable:
        return r'repairable';
      case TaskGateFailureDisposition.blocking:
        return r'blocking';
    }
  }
}

/// @nodoc

extension TaskGateFailureDispositionMapperExtension
    on TaskGateFailureDisposition {
  String toValue() {
    TaskGateFailureDispositionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskGateFailureDisposition>(this)
        as String;
  }
}

/// @nodoc

class TaskEvidenceClaimTypeMapper extends EnumMapper<TaskEvidenceClaimType> {
  TaskEvidenceClaimTypeMapper._();

  static TaskEvidenceClaimTypeMapper? _instance;
  static TaskEvidenceClaimTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskEvidenceClaimTypeMapper._());
    }
    return _instance!;
  }

  static TaskEvidenceClaimType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskEvidenceClaimType decode(dynamic value) {
    switch (value) {
      case r'gate':
        return TaskEvidenceClaimType.gate;
      case r'artifact':
        return TaskEvidenceClaimType.artifact;
      case r'command':
        return TaskEvidenceClaimType.command;
      case 'task_claim':
        return TaskEvidenceClaimType.taskClaim;
      case 'user_approval':
        return TaskEvidenceClaimType.userApproval;
      default:
        return TaskEvidenceClaimType.values[3];
    }
  }

  @override
  dynamic encode(TaskEvidenceClaimType self) {
    switch (self) {
      case TaskEvidenceClaimType.gate:
        return r'gate';
      case TaskEvidenceClaimType.artifact:
        return r'artifact';
      case TaskEvidenceClaimType.command:
        return r'command';
      case TaskEvidenceClaimType.taskClaim:
        return 'task_claim';
      case TaskEvidenceClaimType.userApproval:
        return 'user_approval';
    }
  }
}

/// @nodoc

extension TaskEvidenceClaimTypeMapperExtension on TaskEvidenceClaimType {
  dynamic toValue() {
    TaskEvidenceClaimTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskEvidenceClaimType>(this);
  }
}

/// @nodoc

class TaskEvidenceClaimStrengthMapper
    extends EnumMapper<TaskEvidenceClaimStrength> {
  TaskEvidenceClaimStrengthMapper._();

  static TaskEvidenceClaimStrengthMapper? _instance;
  static TaskEvidenceClaimStrengthMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = TaskEvidenceClaimStrengthMapper._(),
      );
    }
    return _instance!;
  }

  static TaskEvidenceClaimStrength fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskEvidenceClaimStrength decode(dynamic value) {
    switch (value) {
      case r'advisory':
        return TaskEvidenceClaimStrength.advisory;
      case r'supporting':
        return TaskEvidenceClaimStrength.supporting;
      case r'conclusive':
        return TaskEvidenceClaimStrength.conclusive;
      default:
        return TaskEvidenceClaimStrength.values[0];
    }
  }

  @override
  dynamic encode(TaskEvidenceClaimStrength self) {
    switch (self) {
      case TaskEvidenceClaimStrength.advisory:
        return r'advisory';
      case TaskEvidenceClaimStrength.supporting:
        return r'supporting';
      case TaskEvidenceClaimStrength.conclusive:
        return r'conclusive';
    }
  }
}

/// @nodoc

extension TaskEvidenceClaimStrengthMapperExtension
    on TaskEvidenceClaimStrength {
  String toValue() {
    TaskEvidenceClaimStrengthMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskEvidenceClaimStrength>(this)
        as String;
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
class TaskEvidenceExpectationMapper
    extends ClassMapperBase<TaskEvidenceExpectation> {
  TaskEvidenceExpectationMapper._();

  static TaskEvidenceExpectationMapper? _instance;
  static TaskEvidenceExpectationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = TaskEvidenceExpectationMapper._(),
      );
      ProjectEvidenceTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskEvidenceExpectation';

  static String _$id(TaskEvidenceExpectation v) => v.id;
  static const Field<TaskEvidenceExpectation, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static ProjectEvidenceType _$type(TaskEvidenceExpectation v) => v.type;
  static const Field<TaskEvidenceExpectation, ProjectEvidenceType> _f$type =
      Field('type', _$type, opt: true, def: ProjectEvidenceType.taskClaim);
  static List<String> _$criterionIds(TaskEvidenceExpectation v) =>
      v.criterionIds;
  static const Field<TaskEvidenceExpectation, List<String>> _f$criterionIds =
      Field(
        'criterionIds',
        _$criterionIds,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static String _$description(TaskEvidenceExpectation v) => v.description;
  static const Field<TaskEvidenceExpectation, String> _f$description = Field(
    'description',
    _$description,
    hook: JsonStringHook(),
  );
  static bool _$required(TaskEvidenceExpectation v) => v.required;
  static const Field<TaskEvidenceExpectation, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
    hook: JsonBoolHook(fallback: true),
  );
  static String? _$sourceRef(TaskEvidenceExpectation v) => v.sourceRef;
  static const Field<TaskEvidenceExpectation, String> _f$sourceRef = Field(
    'sourceRef',
    _$sourceRef,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static Map<String, dynamic> _$details(TaskEvidenceExpectation v) => v.details;
  static const Field<TaskEvidenceExpectation, Map<String, dynamic>> _f$details =
      Field(
        'details',
        _$details,
        opt: true,
        def: const {},
        hook: JsonMapValueHook(),
      );

  @override
  final MappableFields<TaskEvidenceExpectation> fields = const {
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

  static TaskEvidenceExpectation _instantiate(DecodingData data) {
    return TaskEvidenceExpectation(
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

  static TaskEvidenceExpectation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskEvidenceExpectation>(map);
  }

  static TaskEvidenceExpectation fromJson(String json) {
    return ensureInitialized().decodeJson<TaskEvidenceExpectation>(json);
  }
}

/// @nodoc
mixin TaskEvidenceExpectationMappable {
  String toJson() {
    return TaskEvidenceExpectationMapper.ensureInitialized()
        .encodeJson<TaskEvidenceExpectation>(this as TaskEvidenceExpectation);
  }

  Map<String, dynamic> toMap() {
    return TaskEvidenceExpectationMapper.ensureInitialized()
        .encodeMap<TaskEvidenceExpectation>(this as TaskEvidenceExpectation);
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
class TaskMapper extends ClassMapperBase<Task> {
  TaskMapper._();

  static TaskMapper? _instance;
  static TaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskMapper._());
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
  final String id = 'Task';

  static String _$id(Task v) => v.id;
  static const Field<Task, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$title(Task v) => v.title;
  static const Field<Task, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static String _$originalPrompt(Task v) => v.originalPrompt;
  static const Field<Task, String> _f$originalPrompt = Field(
    'originalPrompt',
    _$originalPrompt,
    opt: true,
    hook: JsonStringHook(),
  );
  static String _$objective(Task v) => v.objective;
  static const Field<Task, String> _f$objective = Field(
    'objective',
    _$objective,
    opt: true,
    hook: JsonStringHook(),
  );
  static List<String> _$constraints(Task v) => v.constraints;
  static const Field<Task, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$successCriteria(Task v) => v.successCriteria;
  static const Field<Task, List<String>> _f$successCriteria = Field(
    'successCriteria',
    _$successCriteria,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<TaskGate> _$gates(Task v) => v.gates;
  static const Field<Task, List<TaskGate>> _f$gates = Field(
    'gates',
    _$gates,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static List<TaskStep> _$steps(Task v) => v.steps;
  static const Field<Task, List<TaskStep>> _f$steps = Field(
    'steps',
    _$steps,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static TaskStatus _$status(Task v) => v.status;
  static const Field<Task, TaskStatus> _f$status = Field(
    'status',
    _$status,
    opt: true,
    def: TaskStatus.paused,
  );
  static List<String> _$criterionIds(Task v) => v.criterionIds;
  static const Field<Task, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static String? _$milestoneId(Task v) => v.milestoneId;
  static const Field<Task, String> _f$milestoneId = Field(
    'milestoneId',
    _$milestoneId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static List<String> _$dependsOnTaskIds(Task v) => v.dependsOnTaskIds;
  static const Field<Task, List<String>> _f$dependsOnTaskIds = Field(
    'dependsOnTaskIds',
    _$dependsOnTaskIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static TaskPriority _$priority(Task v) => v.priority;
  static const Field<Task, TaskPriority> _f$priority = Field(
    'priority',
    _$priority,
    opt: true,
    def: TaskPriority.normal,
  );
  static TaskRisk _$risk(Task v) => v.risk;
  static const Field<Task, TaskRisk> _f$risk = Field(
    'risk',
    _$risk,
    opt: true,
    def: TaskRisk.unknown,
  );
  static ProjectRiskReduction _$riskReduction(Task v) => v.riskReduction;
  static const Field<Task, ProjectRiskReduction> _f$riskReduction = Field(
    'riskReduction',
    _$riskReduction,
    opt: true,
    def: ProjectRiskReduction.none,
  );
  static TaskEffort _$effort(Task v) => v.effort;
  static const Field<Task, TaskEffort> _f$effort = Field(
    'effort',
    _$effort,
    opt: true,
    def: TaskEffort.small,
  );
  static String _$selectionRationale(Task v) => v.selectionRationale;
  static const Field<Task, String> _f$selectionRationale = Field(
    'selectionRationale',
    _$selectionRationale,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static int _$revisionIntroduced(Task v) => v.revisionIntroduced;
  static const Field<Task, int> _f$revisionIntroduced = Field(
    'revisionIntroduced',
    _$revisionIntroduced,
    opt: true,
    def: 1,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static int _$revisionUpdated(Task v) => v.revisionUpdated;
  static const Field<Task, int> _f$revisionUpdated = Field(
    'revisionUpdated',
    _$revisionUpdated,
    opt: true,
    def: 1,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static List<TaskEvidenceExpectation> _$expectedEvidence(Task v) =>
      v.expectedEvidence;
  static const Field<Task, List<TaskEvidenceExpectation>> _f$expectedEvidence =
      Field(
        'expectedEvidence',
        _$expectedEvidence,
        opt: true,
        def: const [],
        hook: JsonObjectListHook(),
      );
  static List<String> _$readPaths(Task v) => v.readPaths;
  static const Field<Task, List<String>> _f$readPaths = Field(
    'readPaths',
    _$readPaths,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$writePaths(Task v) => v.writePaths;
  static const Field<Task, List<String>> _f$writePaths = Field(
    'writePaths',
    _$writePaths,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$doneCriteria(Task v) => v.doneCriteria;
  static const Field<Task, List<String>> _f$doneCriteria = Field(
    'doneCriteria',
    _$doneCriteria,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$outOfScope(Task v) => v.outOfScope;
  static const Field<Task, List<String>> _f$outOfScope = Field(
    'outOfScope',
    _$outOfScope,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$context(Task v) => v.context;
  static const Field<Task, List<String>> _f$context = Field(
    'context',
    _$context,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<TaskArtifact> _$expectedArtifacts(Task v) => v.expectedArtifacts;
  static const Field<Task, List<TaskArtifact>> _f$expectedArtifacts = Field(
    'expectedArtifacts',
    _$expectedArtifacts,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static String? _$recoveryIncidentId(Task v) => v.recoveryIncidentId;
  static const Field<Task, String> _f$recoveryIncidentId = Field(
    'recoveryIncidentId',
    _$recoveryIncidentId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$fingerprint(Task v) => v.fingerprint;
  static const Field<Task, String> _f$fingerprint = Field(
    'fingerprint',
    _$fingerprint,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static String? _$rejectionReason(Task v) => v.rejectionReason;
  static const Field<Task, String> _f$rejectionReason = Field(
    'rejectionReason',
    _$rejectionReason,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskFailure? _$failure(Task v) => v.failure;
  static const Field<Task, TaskFailure> _f$failure = Field(
    'failure',
    _$failure,
    opt: true,
  );
  static String? _$currentStepId(Task v) => v.currentStepId;
  static const Field<Task, String> _f$currentStepId = Field(
    'currentStepId',
    _$currentStepId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$memorySummary(Task v) => v.memorySummary;
  static const Field<Task, String> _f$memorySummary = Field(
    'memorySummary',
    _$memorySummary,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static List<TaskRun> _$runs(Task v) => v.runs;
  static const Field<Task, List<TaskRun>> _f$runs = Field(
    'runs',
    _$runs,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static DateTime _$createdAt(Task v) => v.createdAt;
  static const Field<Task, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(Task v) => v.updatedAt;
  static const Field<Task, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static PendingTaskApproval? _$pendingApproval(Task v) => v.pendingApproval;
  static const Field<Task, PendingTaskApproval> _f$pendingApproval = Field(
    'pendingApproval',
    _$pendingApproval,
    opt: true,
  );
  static PendingTaskQuestion? _$pendingQuestion(Task v) => v.pendingQuestion;
  static const Field<Task, PendingTaskQuestion> _f$pendingQuestion = Field(
    'pendingQuestion',
    _$pendingQuestion,
    opt: true,
  );
  static String? _$chatSessionId(Task v) => v.chatSessionId;
  static const Field<Task, String> _f$chatSessionId = Field(
    'chatSessionId',
    _$chatSessionId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$projectId(Task v) => v.projectId;
  static const Field<Task, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static PlanningMetrics _$planningMetrics(Task v) => v.planningMetrics;
  static const Field<Task, PlanningMetrics> _f$planningMetrics = Field(
    'planningMetrics',
    _$planningMetrics,
    opt: true,
    def: const PlanningMetrics(),
    hook: OmitEmptyPlanningMetricsHook(),
  );
  static DateTime? _$completedAt(Task v) => v.completedAt;
  static const Field<Task, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<Task> fields = const {
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
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const TaskJsonHook();
  static Task _instantiate(DecodingData data) {
    return Task(
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
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Task fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Task>(map);
  }

  static Task fromJson(String json) {
    return ensureInitialized().decodeJson<Task>(json);
  }
}

/// @nodoc
mixin TaskMappable {
  String toJson() {
    return TaskMapper.ensureInitialized().encodeJson<Task>(this as Task);
  }

  Map<String, dynamic> toMap() {
    return TaskMapper.ensureInitialized().encodeMap<Task>(this as Task);
  }
}

/// @nodoc
class TaskGateMapper extends ClassMapperBase<TaskGate> {
  TaskGateMapper._();

  static TaskGateMapper? _instance;
  static TaskGateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskGateMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskGate';

  static String _$id(TaskGate v) => v.id;
  static const Field<TaskGate, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static bool _$required(TaskGate v) => v.required;
  static const Field<TaskGate, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
    hook: JsonBoolHook(fallback: true),
  );
  static String _$scope(TaskGate v) => v.scope;
  static const Field<TaskGate, String> _f$scope = Field(
    'scope',
    _$scope,
    opt: true,
    def: 'step',
    hook: JsonStringHook(fallback: 'step'),
  );
  static Map<String, dynamic> _$params(TaskGate v) => v.params;
  static const Field<TaskGate, Map<String, dynamic>> _f$params = Field(
    'params',
    _$params,
    opt: true,
    def: const {},
    hook: JsonMapValueHook(),
  );
  static String? _$description(TaskGate v) => v.description;
  static const Field<TaskGate, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<TaskGate> fields = const {
    #id: _f$id,
    #required: _f$required,
    #scope: _f$scope,
    #params: _f$params,
    #description: _f$description,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const JsonModelHook(omitEmpty: {'params'});
  static TaskGate _instantiate(DecodingData data) {
    return TaskGate(
      id: data.dec(_f$id),
      required: data.dec(_f$required),
      scope: data.dec(_f$scope),
      params: data.dec(_f$params),
      description: data.dec(_f$description),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskGate fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskGate>(map);
  }

  static TaskGate fromJson(String json) {
    return ensureInitialized().decodeJson<TaskGate>(json);
  }
}

/// @nodoc
mixin TaskGateMappable {
  String toJson() {
    return TaskGateMapper.ensureInitialized().encodeJson<TaskGate>(
      this as TaskGate,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskGateMapper.ensureInitialized().encodeMap<TaskGate>(
      this as TaskGate,
    );
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
class TaskArtifactMapper extends ClassMapperBase<TaskArtifact> {
  TaskArtifactMapper._();

  static TaskArtifactMapper? _instance;
  static TaskArtifactMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskArtifactMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskArtifact';

  static String _$path(TaskArtifact v) => v.path;
  static const Field<TaskArtifact, String> _f$path = Field(
    'path',
    _$path,
    hook: JsonStringHook(),
  );
  static String _$id(TaskArtifact v) => v.id;
  static const Field<TaskArtifact, String> _f$id = Field(
    'id',
    _$id,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static String? _$description(TaskArtifact v) => v.description;
  static const Field<TaskArtifact, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$stepId(TaskArtifact v) => v.stepId;
  static const Field<TaskArtifact, String> _f$stepId = Field(
    'stepId',
    _$stepId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskId(TaskArtifact v) => v.taskId;
  static const Field<TaskArtifact, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$runId(TaskArtifact v) => v.runId;
  static const Field<TaskArtifact, String> _f$runId = Field(
    'runId',
    _$runId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$kind(TaskArtifact v) => v.kind;
  static const Field<TaskArtifact, String> _f$kind = Field(
    'kind',
    _$kind,
    opt: true,
    def: 'file',
    hook: JsonNullableStringHook(),
  );
  static DateTime? _$createdAt(TaskArtifact v) => v.createdAt;
  static const Field<TaskArtifact, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<TaskArtifact> fields = const {
    #path: _f$path,
    #id: _f$id,
    #description: _f$description,
    #stepId: _f$stepId,
    #taskId: _f$taskId,
    #runId: _f$runId,
    #kind: _f$kind,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const TaskArtifactJsonHook();
  static TaskArtifact _instantiate(DecodingData data) {
    return TaskArtifact(
      path: data.dec(_f$path),
      id: data.dec(_f$id),
      description: data.dec(_f$description),
      stepId: data.dec(_f$stepId),
      taskId: data.dec(_f$taskId),
      runId: data.dec(_f$runId),
      kind: data.dec(_f$kind),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskArtifact fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskArtifact>(map);
  }

  static TaskArtifact fromJson(String json) {
    return ensureInitialized().decodeJson<TaskArtifact>(json);
  }
}

/// @nodoc
mixin TaskArtifactMappable {
  String toJson() {
    return TaskArtifactMapper.ensureInitialized().encodeJson<TaskArtifact>(
      this as TaskArtifact,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskArtifactMapper.ensureInitialized().encodeMap<TaskArtifact>(
      this as TaskArtifact,
    );
  }
}

/// @nodoc
class TaskFailureMapper extends ClassMapperBase<TaskFailure> {
  TaskFailureMapper._();

  static TaskFailureMapper? _instance;
  static TaskFailureMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskFailureMapper._());
      TaskGateFailureDispositionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskFailure';

  static String? _$gateId(TaskFailure v) => v.gateId;
  static const Field<TaskFailure, String> _f$gateId = Field(
    'gateId',
    _$gateId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskGateFailureDisposition _$disposition(TaskFailure v) =>
      v.disposition;
  static const Field<TaskFailure, TaskGateFailureDisposition> _f$disposition =
      Field('disposition', _$disposition);
  static String _$failureKey(TaskFailure v) => v.failureKey;
  static const Field<TaskFailure, String> _f$failureKey = Field(
    'failureKey',
    _$failureKey,
    hook: JsonStringHook(),
  );
  static String _$summary(TaskFailure v) => v.summary;
  static const Field<TaskFailure, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static List<String> _$errorCodes(TaskFailure v) => v.errorCodes;
  static const Field<TaskFailure, List<String>> _f$errorCodes = Field(
    'errorCodes',
    _$errorCodes,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$toolCallIds(TaskFailure v) => v.toolCallIds;
  static const Field<TaskFailure, List<String>> _f$toolCallIds = Field(
    'toolCallIds',
    _$toolCallIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static int _$advisoryErrorCount(TaskFailure v) => v.advisoryErrorCount;
  static const Field<TaskFailure, int> _f$advisoryErrorCount = Field(
    'advisoryErrorCount',
    _$advisoryErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$resolvedErrorCount(TaskFailure v) => v.resolvedErrorCount;
  static const Field<TaskFailure, int> _f$resolvedErrorCount = Field(
    'resolvedErrorCount',
    _$resolvedErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$unresolvedErrorCount(TaskFailure v) => v.unresolvedErrorCount;
  static const Field<TaskFailure, int> _f$unresolvedErrorCount = Field(
    'unresolvedErrorCount',
    _$unresolvedErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );

  @override
  final MappableFields<TaskFailure> fields = const {
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

  static TaskFailure _instantiate(DecodingData data) {
    return TaskFailure(
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

  static TaskFailure fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskFailure>(map);
  }

  static TaskFailure fromJson(String json) {
    return ensureInitialized().decodeJson<TaskFailure>(json);
  }
}

/// @nodoc
mixin TaskFailureMappable {
  String toJson() {
    return TaskFailureMapper.ensureInitialized().encodeJson<TaskFailure>(
      this as TaskFailure,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskFailureMapper.ensureInitialized().encodeMap<TaskFailure>(
      this as TaskFailure,
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
class TaskToolErrorMapper extends ClassMapperBase<TaskToolError> {
  TaskToolErrorMapper._();

  static TaskToolErrorMapper? _instance;
  static TaskToolErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskToolErrorMapper._());
      TaskToolErrorDispositionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskToolError';

  static String _$code(TaskToolError v) => v.code;
  static const Field<TaskToolError, String> _f$code = Field(
    'code',
    _$code,
    hook: JsonStringHook(fallback: 'unknown_tool_error'),
  );
  static String _$message(TaskToolError v) => v.message;
  static const Field<TaskToolError, String> _f$message = Field(
    'message',
    _$message,
    hook: JsonStringHook(),
  );
  static TaskToolErrorDisposition _$disposition(TaskToolError v) =>
      v.disposition;
  static const Field<TaskToolError, TaskToolErrorDisposition> _f$disposition =
      Field('disposition', _$disposition);

  @override
  final MappableFields<TaskToolError> fields = const {
    #code: _f$code,
    #message: _f$message,
    #disposition: _f$disposition,
  };
  @override
  final bool ignoreNull = true;

  static TaskToolError _instantiate(DecodingData data) {
    return TaskToolError(
      code: data.dec(_f$code),
      message: data.dec(_f$message),
      disposition: data.dec(_f$disposition),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskToolError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskToolError>(map);
  }

  static TaskToolError fromJson(String json) {
    return ensureInitialized().decodeJson<TaskToolError>(json);
  }
}

/// @nodoc
mixin TaskToolErrorMappable {
  String toJson() {
    return TaskToolErrorMapper.ensureInitialized().encodeJson<TaskToolError>(
      this as TaskToolError,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskToolErrorMapper.ensureInitialized().encodeMap<TaskToolError>(
      this as TaskToolError,
    );
  }
}

/// @nodoc
class TaskGateResultMapper extends ClassMapperBase<TaskGateResult> {
  TaskGateResultMapper._();

  static TaskGateResultMapper? _instance;
  static TaskGateResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskGateResultMapper._());
      TaskGateStatusMapper.ensureInitialized();
      TaskGateFailureDispositionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskGateResult';

  static String _$gateId(TaskGateResult v) => v.gateId;
  static const Field<TaskGateResult, String> _f$gateId = Field(
    'gateId',
    _$gateId,
    hook: JsonStringHook(),
  );
  static TaskGateStatus _$status(TaskGateResult v) => v.status;
  static const Field<TaskGateResult, TaskGateStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String _$summary(TaskGateResult v) => v.summary;
  static const Field<TaskGateResult, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static Map<String, dynamic> _$details(TaskGateResult v) => v.details;
  static const Field<TaskGateResult, Map<String, dynamic>> _f$details = Field(
    'details',
    _$details,
    opt: true,
    def: const {},
    hook: JsonMapValueHook(),
  );
  static TaskGateFailureDisposition? _$failureDisposition(TaskGateResult v) =>
      v.failureDisposition;
  static const Field<TaskGateResult, TaskGateFailureDisposition>
  _f$failureDisposition = Field(
    'failureDisposition',
    _$failureDisposition,
    opt: true,
  );
  static DateTime _$evaluatedAt(TaskGateResult v) => v.evaluatedAt;
  static const Field<TaskGateResult, DateTime> _f$evaluatedAt = Field(
    'evaluatedAt',
    _$evaluatedAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<TaskGateResult> fields = const {
    #gateId: _f$gateId,
    #status: _f$status,
    #summary: _f$summary,
    #details: _f$details,
    #failureDisposition: _f$failureDisposition,
    #evaluatedAt: _f$evaluatedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const JsonModelHook(omitEmpty: {'details'});
  static TaskGateResult _instantiate(DecodingData data) {
    return TaskGateResult(
      gateId: data.dec(_f$gateId),
      status: data.dec(_f$status),
      summary: data.dec(_f$summary),
      details: data.dec(_f$details),
      failureDisposition: data.dec(_f$failureDisposition),
      evaluatedAt: data.dec(_f$evaluatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskGateResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskGateResult>(map);
  }

  static TaskGateResult fromJson(String json) {
    return ensureInitialized().decodeJson<TaskGateResult>(json);
  }
}

/// @nodoc
mixin TaskGateResultMappable {
  String toJson() {
    return TaskGateResultMapper.ensureInitialized().encodeJson<TaskGateResult>(
      this as TaskGateResult,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskGateResultMapper.ensureInitialized().encodeMap<TaskGateResult>(
      this as TaskGateResult,
    );
  }
}

/// @nodoc
class TaskEvidenceClaimMapper extends ClassMapperBase<TaskEvidenceClaim> {
  TaskEvidenceClaimMapper._();

  static TaskEvidenceClaimMapper? _instance;
  static TaskEvidenceClaimMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskEvidenceClaimMapper._());
      TaskEvidenceClaimTypeMapper.ensureInitialized();
      TaskEvidenceClaimStrengthMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskEvidenceClaim';

  static String _$criterionId(TaskEvidenceClaim v) => v.criterionId;
  static const Field<TaskEvidenceClaim, String> _f$criterionId = Field(
    'criterionId',
    _$criterionId,
    hook: JsonStringHook(),
  );
  static String _$claim(TaskEvidenceClaim v) => v.claim;
  static const Field<TaskEvidenceClaim, String> _f$claim = Field(
    'claim',
    _$claim,
    hook: JsonStringHook(),
  );
  static TaskEvidenceClaimType _$evidenceType(TaskEvidenceClaim v) =>
      v.evidenceType;
  static const Field<TaskEvidenceClaim, TaskEvidenceClaimType> _f$evidenceType =
      Field(
        'evidenceType',
        _$evidenceType,
        opt: true,
        def: TaskEvidenceClaimType.taskClaim,
      );
  static String _$sourceRef(TaskEvidenceClaim v) => v.sourceRef;
  static const Field<TaskEvidenceClaim, String> _f$sourceRef = Field(
    'sourceRef',
    _$sourceRef,
    hook: JsonStringHook(),
  );
  static TaskEvidenceClaimStrength _$suggestedStrength(TaskEvidenceClaim v) =>
      v.suggestedStrength;
  static const Field<TaskEvidenceClaim, TaskEvidenceClaimStrength>
  _f$suggestedStrength = Field(
    'suggestedStrength',
    _$suggestedStrength,
    opt: true,
    def: TaskEvidenceClaimStrength.advisory,
  );
  static String? _$expectationId(TaskEvidenceClaim v) => v.expectationId;
  static const Field<TaskEvidenceClaim, String> _f$expectationId = Field(
    'expectationId',
    _$expectationId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$runId(TaskEvidenceClaim v) => v.runId;
  static const Field<TaskEvidenceClaim, String> _f$runId = Field(
    'runId',
    _$runId,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<TaskEvidenceClaim> fields = const {
    #criterionId: _f$criterionId,
    #claim: _f$claim,
    #evidenceType: _f$evidenceType,
    #sourceRef: _f$sourceRef,
    #suggestedStrength: _f$suggestedStrength,
    #expectationId: _f$expectationId,
    #runId: _f$runId,
  };
  @override
  final bool ignoreNull = true;

  static TaskEvidenceClaim _instantiate(DecodingData data) {
    return TaskEvidenceClaim(
      criterionId: data.dec(_f$criterionId),
      claim: data.dec(_f$claim),
      evidenceType: data.dec(_f$evidenceType),
      sourceRef: data.dec(_f$sourceRef),
      suggestedStrength: data.dec(_f$suggestedStrength),
      expectationId: data.dec(_f$expectationId),
      runId: data.dec(_f$runId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskEvidenceClaim fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskEvidenceClaim>(map);
  }

  static TaskEvidenceClaim fromJson(String json) {
    return ensureInitialized().decodeJson<TaskEvidenceClaim>(json);
  }
}

/// @nodoc
mixin TaskEvidenceClaimMappable {
  String toJson() {
    return TaskEvidenceClaimMapper.ensureInitialized()
        .encodeJson<TaskEvidenceClaim>(this as TaskEvidenceClaim);
  }

  Map<String, dynamic> toMap() {
    return TaskEvidenceClaimMapper.ensureInitialized()
        .encodeMap<TaskEvidenceClaim>(this as TaskEvidenceClaim);
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

