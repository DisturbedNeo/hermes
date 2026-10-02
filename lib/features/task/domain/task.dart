/// Domain-owned task aggregate.
///
/// Task execution and persistence representations are supplied by application
/// contracts and infrastructure adapters; this file owns the durable business
/// aggregate used by task policies.
library;

import 'package:hermes/core/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';
import 'package:hermes/features/task/application/contracts/task_state_models.dart'
    hide TaskSnapshotAggregate;

export 'package:hermes/features/task/application/contracts/task_state_models.dart'
    hide TaskSnapshotAggregate;

class TaskAggregate implements TaskProjectNodeSource, TaskExecutionSource {
  /// Revision of the canonical task snapshot. This is runtime metadata and
  /// is omitted from the document nested in the persistence envelope.
  final int persistenceRevision;
  final String id;
  final String title;
  final String originalPrompt;
  final String objective;
  final List<String> constraints;
  final List<String> successCriteria;
  final List<TaskGate> gates;
  final List<TaskStep> steps;
  final TaskStatus status;
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
  final TaskFailure? failure;
  final String? currentStepId;
  final String memorySummary;
  final List<TaskRun> runs;
  final PendingTaskApproval? pendingApproval;
  final PendingTaskQuestion? pendingQuestion;
  final String? chatSessionId;
  final String? projectId;
  final PlanningMetrics planningMetrics;

  /// Non-null when a safe fallback was used because task planning did not
  /// produce a committed executable plan.
  final String? planningError;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  @override
  Object? get latestRun => runs.isEmpty ? null : runs.last;

  const TaskAggregate({
    this.persistenceRevision = 0,
    required this.id,
    required this.title,
    String? originalPrompt,
    String? objective,
    this.constraints = const [],
    this.successCriteria = const [],
    this.gates = const [],
    this.steps = const [],
    this.status = TaskStatus.paused,
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
    this.failure,
    this.currentStepId,
    this.memorySummary = '',
    this.runs = const [],
    required this.createdAt,
    required this.updatedAt,
    this.pendingApproval,
    this.pendingQuestion,
    this.chatSessionId,
    this.projectId,
    this.planningMetrics = const PlanningMetrics(),
    this.planningError,
    this.completedAt,
  }) : originalPrompt = originalPrompt ?? objective ?? '',
       objective = objective ?? originalPrompt ?? '';

  TaskAggregate copyWith({
    int? persistenceRevision,
    String? id,
    String? title,
    String? originalPrompt,
    String? objective,
    List<String>? constraints,
    List<String>? successCriteria,
    List<TaskGate>? gates,
    List<TaskStep>? steps,
    TaskStatus? status,
    List<String>? criterionIds,
    Object? milestoneId = kSentinel,
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
    Object? recoveryIncidentId = kSentinel,
    String? fingerprint,
    Object? rejectionReason = kSentinel,
    Object? failure = kSentinel,
    Object? currentStepId = kSentinel,
    String? memorySummary,
    List<TaskRun>? runs,
    Object? pendingApproval = kSentinel,
    Object? pendingQuestion = kSentinel,
    Object? chatSessionId = kSentinel,
    Object? projectId = kSentinel,
    PlanningMetrics? planningMetrics,
    Object? planningError = kSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = kSentinel,
  }) {
    return TaskAggregate(
      persistenceRevision: persistenceRevision ?? this.persistenceRevision,
      id: id ?? this.id,
      title: title ?? this.title,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      objective: objective ?? this.objective,
      constraints: constraints ?? this.constraints,
      successCriteria: successCriteria ?? this.successCriteria,
      gates: gates ?? this.gates,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      criterionIds: criterionIds ?? this.criterionIds,
      milestoneId: resolve(milestoneId, this.milestoneId),
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
      recoveryIncidentId: resolve(recoveryIncidentId, this.recoveryIncidentId),
      fingerprint: fingerprint ?? this.fingerprint,
      rejectionReason: resolve(rejectionReason, this.rejectionReason),
      failure: resolve(failure, this.failure),
      currentStepId: resolve(currentStepId, this.currentStepId),
      memorySummary: memorySummary ?? this.memorySummary,
      runs: runs ?? this.runs,
      pendingApproval: resolve(pendingApproval, this.pendingApproval),
      pendingQuestion: resolve(pendingQuestion, this.pendingQuestion),
      chatSessionId: resolve(chatSessionId, this.chatSessionId),
      projectId: resolve(projectId, this.projectId),
      planningMetrics: planningMetrics ?? this.planningMetrics,
      planningError: resolve(planningError, this.planningError),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: resolve(completedAt, this.completedAt),
    );
  }

  TaskStep? get currentStep =>
      currentStepId == null ? null : stepById(currentStepId!);

  TaskStep? get nextRunnableStep => steps
      .where(
        (step) =>
            step.status == TaskStepStatus.pending ||
            step.status == TaskStepStatus.approved ||
            step.status == TaskStepStatus.blocked ||
            step.status == TaskStepStatus.failed,
      )
      .firstOrNull;

  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.rejected ||
      status == TaskStatus.split ||
      status == TaskStatus.cancelled ||
      status == TaskStatus.failed;

  TaskStep? stepById(String id) {
    for (final step in steps) {
      if (step.id == id) return step;
    }
    return null;
  }
}

typedef Task = TaskAggregate;
