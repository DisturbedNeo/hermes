// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'task_execution_contracts.dart';

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
    hook: JsonStringHook(fallback: 'file'),
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

