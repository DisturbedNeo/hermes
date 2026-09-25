import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/models/task.dart';

part 'project_task_models.mapper.dart';

/// Planner-owned description of a task.
///
/// This deliberately contains no execution IDs, step state, run history, or
/// persistence metadata. The project planner can exchange this shape without
/// accidentally treating an executable task document as authoritative plan
/// input.
class ProjectTaskSpec {
  final String ref;
  final String title;
  final String objective;
  final List<String> criterionRefs;
  final List<String> dependencyRefs;
  final String? milestoneRef;
  final TaskPriority priority;
  final TaskRisk risk;
  final ProjectRiskReduction riskReduction;
  final TaskEffort effort;
  final String selectionRationale;
  final List<String> constraints;
  final List<String> readPaths;
  final List<String> writePaths;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> context;
  final List<TaskArtifact> expectedArtifacts;

  const ProjectTaskSpec({
    this.ref = '',
    this.title = '',
    this.objective = '',
    this.criterionRefs = const [],
    this.dependencyRefs = const [],
    this.milestoneRef,
    this.priority = TaskPriority.normal,
    this.risk = TaskRisk.unknown,
    this.riskReduction = ProjectRiskReduction.none,
    this.effort = TaskEffort.small,
    this.selectionRationale = '',
    this.constraints = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.context = const [],
    this.expectedArtifacts = const [],
  });
}

/// The project-owned identity of a task document.
///
/// Task content and execution history remain in the task system. Projects
/// persist IDs and use refs when planning or scheduling work.
class ProjectTaskRef {
  final String id;
  final int planRevision;

  const ProjectTaskRef({required this.id, required this.planRevision});
}

/// Planning-only task node used by project state and scheduling policy.
///
/// It is deliberately constructed from the canonical Task at the read/write
/// boundary, but it does not expose steps, runs, or tool history.  This is the
/// authoritative project-side task representation; the full [Task] document
/// remains owned by the task system.
@MappableClass(ignoreNull: true)
class ProjectTaskNode with ProjectTaskNodeMappable {
  const ProjectTaskNode({
    required this.id,
    required this.title,
    required this.objective,
    required this.status,
    this.gates = const [],
    this.constraints = const [],
    this.successCriteria = const [],
    this.criterionIds = const [],
    this.milestoneId,
    this.dependsOnTaskIds = const [],
    this.priority = TaskPriority.normal,
    this.risk = TaskRisk.unknown,
    this.riskReduction = ProjectRiskReduction.none,
    this.effort = TaskEffort.small,
    this.selectionRationale = '',
    this.revisionIntroduced = 1,
    this.revisionUpdated = 1,
    this.expectedEvidence = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.context = const [],
    this.expectedArtifacts = const [],
    this.recoveryIncidentId,
    this.fingerprint = '',
    this.rejectionReason,
    this.failureKey,
    this.failureGateId,
    this.failureErrorCodes = const [],
    this.unresolvedErrorCount = 0,
    this.planningError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String objective;
  final TaskStatus status;
  final List<TaskGate> gates;
  final List<String> constraints;
  final List<String> successCriteria;
  final List<String> criterionIds;
  final String? milestoneId;
  final List<String> dependsOnTaskIds;
  final TaskPriority priority;
  final TaskRisk risk;
  final ProjectRiskReduction riskReduction;
  final TaskEffort effort;
  final String selectionRationale;
  final int revisionIntroduced;
  final int revisionUpdated;
  final List<TaskEvidenceExpectation> expectedEvidence;
  final List<String> readPaths;
  final List<String> writePaths;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> context;
  final List<TaskArtifact> expectedArtifacts;
  final String? recoveryIncidentId;
  final String fingerprint;
  final String? rejectionReason;
  final String? failureKey;
  final String? failureGateId;
  final List<String> failureErrorCodes;
  final int unresolvedErrorCount;
  final String? planningError;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProjectTaskNode.fromTask(Task task) => ProjectTaskNode(
    id: task.id,
    title: task.title,
    objective: task.objective,
    status: task.status,
    gates: List.unmodifiable(task.gates),
    constraints: List.unmodifiable(task.constraints),
    successCriteria: List.unmodifiable(task.successCriteria),
    criterionIds: List.unmodifiable(task.criterionIds),
    milestoneId: task.milestoneId,
    dependsOnTaskIds: List.unmodifiable(task.dependsOnTaskIds),
    priority: task.priority,
    risk: task.risk,
    riskReduction: task.riskReduction,
    effort: task.effort,
    selectionRationale: task.selectionRationale,
    revisionIntroduced: task.revisionIntroduced,
    revisionUpdated: task.revisionUpdated,
    expectedEvidence: List.unmodifiable(task.expectedEvidence),
    readPaths: List.unmodifiable(task.readPaths),
    writePaths: List.unmodifiable(task.writePaths),
    doneCriteria: List.unmodifiable(task.doneCriteria),
    outOfScope: List.unmodifiable(task.outOfScope),
    context: List.unmodifiable(task.context),
    expectedArtifacts: List.unmodifiable(task.expectedArtifacts),
    recoveryIncidentId: task.recoveryIncidentId,
    fingerprint: task.fingerprint,
    rejectionReason: task.rejectionReason,
    failureKey: task.failure?.failureKey,
    failureGateId: task.failure?.gateId,
    failureErrorCodes: List.unmodifiable(task.failure?.errorCodes ?? const []),
    unresolvedErrorCount: task.failure?.unresolvedErrorCount ?? 0,
    planningError: task.planningError,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
  );

  ProjectTaskNode copyWith({
    String? id,
    String? title,
    String? objective,
    TaskStatus? status,
    List<TaskGate>? gates,
    List<String>? constraints,
    List<String>? successCriteria,
    List<String>? criterionIds,
    Object? milestoneId = _unset,
    List<String>? dependsOnTaskIds,
    TaskPriority? priority,
    TaskRisk? risk,
    ProjectRiskReduction? riskReduction,
    TaskEffort? effort,
    String? selectionRationale,
    int? revisionIntroduced,
    int? revisionUpdated,
    List<TaskEvidenceExpectation>? expectedEvidence,
    List<String>? readPaths,
    List<String>? writePaths,
    List<String>? doneCriteria,
    List<String>? outOfScope,
    List<String>? context,
    List<TaskArtifact>? expectedArtifacts,
    Object? recoveryIncidentId = _unset,
    String? fingerprint,
    Object? rejectionReason = _unset,
    Object? failureKey = _unset,
    Object? failureGateId = _unset,
    List<String>? failureErrorCodes,
    int? unresolvedErrorCount,
    Object? planningError = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProjectTaskNode(
    id: id ?? this.id,
    title: title ?? this.title,
    objective: objective ?? this.objective,
    status: status ?? this.status,
    gates: gates ?? this.gates,
    constraints: constraints ?? this.constraints,
    successCriteria: successCriteria ?? this.successCriteria,
    criterionIds: criterionIds ?? this.criterionIds,
    milestoneId: identical(milestoneId, _unset)
        ? this.milestoneId
        : milestoneId as String?,
    dependsOnTaskIds: dependsOnTaskIds ?? this.dependsOnTaskIds,
    priority: priority ?? this.priority,
    risk: risk ?? this.risk,
    riskReduction: riskReduction ?? this.riskReduction,
    effort: effort ?? this.effort,
    selectionRationale: selectionRationale ?? this.selectionRationale,
    revisionIntroduced: revisionIntroduced ?? this.revisionIntroduced,
    revisionUpdated: revisionUpdated ?? this.revisionUpdated,
    expectedEvidence: expectedEvidence ?? this.expectedEvidence,
    readPaths: readPaths ?? this.readPaths,
    writePaths: writePaths ?? this.writePaths,
    doneCriteria: doneCriteria ?? this.doneCriteria,
    outOfScope: outOfScope ?? this.outOfScope,
    context: context ?? this.context,
    expectedArtifacts: expectedArtifacts ?? this.expectedArtifacts,
    recoveryIncidentId: identical(recoveryIncidentId, _unset)
        ? this.recoveryIncidentId
        : recoveryIncidentId as String?,
    fingerprint: fingerprint ?? this.fingerprint,
    rejectionReason: identical(rejectionReason, _unset)
        ? this.rejectionReason
        : rejectionReason as String?,
    failureKey: identical(failureKey, _unset)
        ? this.failureKey
        : failureKey as String?,
    failureGateId: identical(failureGateId, _unset)
        ? this.failureGateId
        : failureGateId as String?,
    failureErrorCodes: failureErrorCodes ?? this.failureErrorCodes,
    unresolvedErrorCount: unresolvedErrorCount ?? this.unresolvedErrorCount,
    planningError: identical(planningError, _unset)
        ? this.planningError
        : planningError as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Materializes a planning node at the task-system boundary. The returned
  /// document is a definition only; it deliberately contains no steps, runs,
  /// or execution history.
  Task toTaskDefinition() => Task(
    id: id,
    title: title,
    originalPrompt: objective,
    objective: objective,
    status: status,
    gates: gates,
    constraints: constraints,
    successCriteria: successCriteria,
    criterionIds: criterionIds,
    milestoneId: milestoneId,
    dependsOnTaskIds: dependsOnTaskIds,
    priority: priority,
    risk: risk,
    riskReduction: riskReduction,
    effort: effort,
    selectionRationale: selectionRationale,
    revisionIntroduced: revisionIntroduced,
    revisionUpdated: revisionUpdated,
    expectedEvidence: expectedEvidence,
    readPaths: readPaths,
    writePaths: writePaths,
    doneCriteria: doneCriteria,
    outOfScope: outOfScope,
    context: context,
    expectedArtifacts: expectedArtifacts,
    recoveryIncidentId: recoveryIncidentId,
    fingerprint: fingerprint.isEmpty
        ? _fingerprint(objective, criterionIds)
        : fingerprint,
    rejectionReason: rejectionReason,
    createdAt: createdAt,
    updatedAt: updatedAt,
    planningError: planningError,
  );

  bool get isTerminal => switch (status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled ||
    TaskStatus.deferred ||
    TaskStatus.obsolete => true,
    _ => false,
  };
}

const Object _unset = Object();

String _fingerprint(String objective, List<String> criteria) =>
    [objective.trim().toLowerCase(), ...criteria].join('|');

/// Execution-owned observation of a canonical task document.
///
/// It is intentionally an adapter rather than a second persisted task model;
/// it lets project orchestration consume execution state without making the
/// planning representation own task steps or run history.
class TaskExecution {
  final String taskId;
  final TaskStatus status;
  final String? currentStepId;
  final int persistenceRevision;
  final TaskRun? latestRun;
  final DateTime observedAt;

  const TaskExecution({
    required this.taskId,
    required this.status,
    required this.persistenceRevision,
    required this.observedAt,
    this.currentStepId,
    this.latestRun,
  });

  factory TaskExecution.fromTask(Task task, {DateTime? observedAt}) =>
      TaskExecution(
        taskId: task.id,
        status: task.status,
        currentStepId: task.currentStepId,
        persistenceRevision: task.persistenceRevision,
        latestRun: task.runs.isEmpty ? null : task.runs.last,
        observedAt: observedAt ?? DateTime.now(),
      );
}
