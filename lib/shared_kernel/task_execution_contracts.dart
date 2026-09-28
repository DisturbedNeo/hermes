import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/serialization/json_hooks.dart';
import 'package:hermes/shared_kernel/task_planning_types.dart';

part 'task_execution_contracts.mapper.dart';

/// Boundary-safe gate definition shared by planning and execution adapters.
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

/// Evidence expectation exchanged at the planning/execution boundary.
@MappableClass(ignoreNull: true)
class TaskEvidenceExpectation with TaskEvidenceExpectationMappable {
  @MappableField(hook: JsonStringHook())
  final String id;
  final ProjectEvidenceType type;
  @MappableField(hook: JsonStringListHook())
  final List<String> criterionIds;
  @MappableField(hook: JsonStringHook())
  final String description;
  @MappableField(hook: JsonBoolHook(fallback: true))
  final bool required;
  @MappableField(hook: JsonNullableStringHook())
  final String? sourceRef;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> details;

  const TaskEvidenceExpectation({
    required this.id,
    this.type = ProjectEvidenceType.taskClaim,
    this.criterionIds = const [],
    required this.description,
    this.required = true,
    this.sourceRef,
    this.details = const {},
  });
}

/// Artifact reference that can safely cross the planning/execution boundary.
@MappableClass(ignoreNull: true, hook: TaskArtifactJsonHook())
class TaskArtifact with TaskArtifactMappable {
  @MappableField(hook: JsonStringHook())
  final String path;
  @MappableField(hook: JsonStringHook())
  final String id;
  @MappableField(hook: JsonNullableStringHook())
  final String? description;
  @MappableField(hook: JsonNullableStringHook())
  final String? stepId;
  @MappableField(hook: JsonNullableStringHook())
  final String? taskId;
  @MappableField(hook: JsonNullableStringHook())
  final String? runId;
  @MappableField(hook: JsonStringHook(fallback: 'file'))
  final String kind;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? createdAt;

  const TaskArtifact({
    required this.path,
    this.id = '',
    this.description,
    this.stepId,
    this.taskId,
    this.runId,
    this.kind = 'file',
    this.createdAt,
  });

  TaskArtifact copyWith({
    String? path,
    String? id,
    Object? description = kSentinel,
    Object? stepId = kSentinel,
    Object? taskId = kSentinel,
    Object? runId = kSentinel,
    String? kind,
    Object? createdAt = kSentinel,
  }) => TaskArtifact(
    path: path ?? this.path,
    id: id ?? this.id,
    description: resolve(description, this.description),
    stepId: resolve(stepId, this.stepId),
    taskId: resolve(taskId, this.taskId),
    runId: resolve(runId, this.runId),
    kind: kind ?? this.kind,
    createdAt: resolve(createdAt, this.createdAt),
  );
}

class TaskArtifactJsonHook extends JsonModelHook {
  const TaskArtifactJsonHook();

  @override
  Object? afterEncode(Object? value) {
    if (value is! Map) return value;
    final encoded = Map<String, dynamic>.from(value);
    if (encoded['id'] == '') encoded.remove('id');
    if (encoded['kind'] == 'file') encoded.remove('kind');
    return encoded;
  }
}

@MappableEnum(defaultValue: TaskGateStatus.pending)
enum TaskGateStatus { passed, failed, pending, advisory }

@MappableEnum(defaultValue: TaskGateFailureDisposition.repairable)
enum TaskGateFailureDisposition { repairable, blocking }

@MappableEnum(defaultValue: TaskEvidenceClaimType.taskClaim)
enum TaskEvidenceClaimType {
  gate,
  artifact,
  command,
  @MappableValue('task_claim')
  taskClaim,
  @MappableValue('user_approval')
  userApproval,
}

@MappableEnum(defaultValue: TaskEvidenceClaimStrength.advisory)
enum TaskEvidenceClaimStrength { advisory, supporting, conclusive }

extension TaskGateStatusWire on TaskGateStatus {
  String get wire => name;
}

extension TaskGateFailureDispositionWire on TaskGateFailureDisposition {
  String get wire => name;
}

@MappableClass(ignoreNull: true, hook: JsonModelHook(omitEmpty: {'details'}))
class TaskGateResult with TaskGateResultMappable {
  @MappableField(hook: JsonStringHook())
  final String gateId;
  final TaskGateStatus status;
  @MappableField(hook: JsonStringHook())
  final String summary;
  @MappableField(hook: JsonMapValueHook())
  final Map<String, dynamic> details;
  final TaskGateFailureDisposition? failureDisposition;
  @MappableField(hook: JsonDateHook())
  final DateTime evaluatedAt;

  const TaskGateResult({
    required this.gateId,
    required this.status,
    required this.summary,
    this.details = const {},
    this.failureDisposition,
    required this.evaluatedAt,
  });
}

@MappableClass(ignoreNull: true)
class TaskFailure with TaskFailureMappable {
  @MappableField(hook: JsonNullableStringHook())
  final String? gateId;
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

  const TaskFailure({
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

@MappableClass(ignoreNull: true)
class TaskEvidenceClaim with TaskEvidenceClaimMappable {
  @MappableField(hook: JsonStringHook())
  final String criterionId;
  @MappableField(hook: JsonStringHook())
  final String claim;
  final TaskEvidenceClaimType evidenceType;
  @MappableField(hook: JsonStringHook())
  final String sourceRef;
  final TaskEvidenceClaimStrength suggestedStrength;
  @MappableField(hook: JsonNullableStringHook())
  final String? expectationId;
  @MappableField(hook: JsonNullableStringHook())
  final String? runId;

  const TaskEvidenceClaim({
    required this.criterionId,
    required this.claim,
    this.evidenceType = TaskEvidenceClaimType.taskClaim,
    required this.sourceRef,
    this.suggestedStrength = TaskEvidenceClaimStrength.advisory,
    this.expectationId,
    this.runId,
  });
}
