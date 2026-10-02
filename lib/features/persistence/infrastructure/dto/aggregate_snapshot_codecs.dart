import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/project/application/contracts/project_state_models.dart'
    as project_snapshot;
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/task_state_models.dart'
    as task_snapshot;
import 'package:hermes/features/task/domain/task.dart';

/// Registers the persistence-owned JSON codecs for the domain aggregates.
///
/// The state-contract mappers are deliberately used only as an implementation
/// detail here. They never cross back into the domain library, and the domain
/// aggregates do not carry mapper annotations or JSON methods.
void registerAggregateSnapshotCodecs() {
  ModelJson.register<ProjectAggregate>(
    encode: ProjectSnapshotCodec.encode,
    decode: ProjectSnapshotCodec.decode,
  );
  ModelJson.register<TaskAggregate>(
    encode: TaskSnapshotCodec.encode,
    decode: TaskSnapshotCodec.decode,
  );
}

abstract final class ProjectSnapshotCodec {
  static Map<String, dynamic> encode(ProjectAggregate project) {
    final snapshot = _toSnapshot(project.copyWith(persistenceRevision: 0));
    final document =
        ModelJson.encode<project_snapshot.ProjectSnapshotAggregate>(snapshot);
    document.remove('persistenceRevision');
    return document;
  }

  static ProjectAggregate decode(Map<String, dynamic> document) =>
      _fromSnapshot(
        ModelJson.decode<project_snapshot.ProjectSnapshotAggregate>(document),
      );

  static project_snapshot.ProjectSnapshotAggregate _toSnapshot(
    ProjectAggregate project,
  ) => project_snapshot.ProjectSnapshotAggregate(
    persistenceRevision: project.persistenceRevision,
    id: project.id,
    title: project.title,
    originalGoal: project.originalGoal,
    refinedGoal: project.refinedGoal,
    criteria: project.criteria,
    constraints: project.constraints,
    tasks: project.tasks,
    taskIds: project.taskIds,
    currentBatchTaskIds: project.currentBatchTaskIds,
    currentBatchIndex: project.currentBatchIndex,
    currentBatchPlanRevision: project.currentBatchPlanRevision,
    currentBatchProgressObserved: project.currentBatchProgressObserved,
    pendingReplanReason: project.pendingReplanReason,
    artifacts: project.artifacts,
    recoveryIncidents: project.recoveryIncidents,
    evidence: project.evidence,
    milestones: project.milestones,
    memory: project.memory,
    workspaceGraph: project.workspaceGraph,
    planHistory: project.planHistory,
    pendingPlanApproval: project.pendingPlanApproval,
    pendingReplanTriggers: project.pendingReplanTriggers,
    completionReviewCheckpoint: project.completionReviewCheckpoint,
    boundary: project.boundary,
    openQuestions: project.openQuestions,
    status: project.status,
    iterationCount: project.iterationCount,
    maxIterations: project.maxIterations,
    maxFailedTasks: project.maxFailedTasks,
    activeTaskId: project.activeTaskId,
    chatSessionId: project.chatSessionId,
    completionSummary: project.completionSummary,
    blocker: project.blocker,
    decisions: project.decisions,
    diagnostics: project.diagnostics,
    createdAt: project.createdAt,
    updatedAt: project.updatedAt,
    completedAt: project.completedAt,
  );

  static ProjectAggregate _fromSnapshot(
    project_snapshot.ProjectSnapshotAggregate project,
  ) => ProjectAggregate(
    persistenceRevision: project.persistenceRevision,
    id: project.id,
    title: project.title,
    originalGoal: project.originalGoal,
    refinedGoal: project.refinedGoal,
    criteria: project.criteria,
    constraints: project.constraints,
    tasks: project.tasks,
    taskIds: project.taskIds,
    currentBatchTaskIds: project.currentBatchTaskIds,
    currentBatchIndex: project.currentBatchIndex,
    currentBatchPlanRevision: project.currentBatchPlanRevision,
    currentBatchProgressObserved: project.currentBatchProgressObserved,
    pendingReplanReason: project.pendingReplanReason,
    artifacts: project.artifacts,
    recoveryIncidents: project.recoveryIncidents,
    evidence: project.evidence,
    milestones: project.milestones,
    memory: project.memory,
    workspaceGraph: project.workspaceGraph,
    planHistory: project.planHistory,
    pendingPlanApproval: project.pendingPlanApproval,
    pendingReplanTriggers: project.pendingReplanTriggers,
    completionReviewCheckpoint: project.completionReviewCheckpoint,
    boundary: project.boundary,
    openQuestions: project.openQuestions,
    status: project.status,
    iterationCount: project.iterationCount,
    maxIterations: project.maxIterations,
    maxFailedTasks: project.maxFailedTasks,
    activeTaskId: project.activeTaskId,
    chatSessionId: project.chatSessionId,
    completionSummary: project.completionSummary,
    blocker: project.blocker,
    decisions: project.decisions,
    diagnostics: project.diagnostics,
    createdAt: project.createdAt,
    updatedAt: project.updatedAt,
    completedAt: project.completedAt,
  );
}

abstract final class TaskSnapshotCodec {
  static Map<String, dynamic> encode(TaskAggregate task) {
    final snapshot = _toSnapshot(task.copyWith(persistenceRevision: 0));
    final document = ModelJson.encode<task_snapshot.TaskSnapshotAggregate>(
      snapshot,
    );
    document.remove('persistenceRevision');
    return document;
  }

  static TaskAggregate decode(Map<String, dynamic> document) => _fromSnapshot(
    ModelJson.decode<task_snapshot.TaskSnapshotAggregate>(document),
  );

  static task_snapshot.TaskSnapshotAggregate _toSnapshot(TaskAggregate task) =>
      task_snapshot.TaskSnapshotAggregate(
        persistenceRevision: task.persistenceRevision,
        id: task.id,
        title: task.title,
        originalPrompt: task.originalPrompt,
        objective: task.objective,
        constraints: task.constraints,
        successCriteria: task.successCriteria,
        gates: task.gates,
        steps: task.steps,
        status: task.status,
        criterionIds: task.criterionIds,
        milestoneId: task.milestoneId,
        dependsOnTaskIds: task.dependsOnTaskIds,
        priority: task.priority,
        risk: task.risk,
        riskReduction: task.riskReduction,
        effort: task.effort,
        selectionRationale: task.selectionRationale,
        revisionIntroduced: task.revisionIntroduced,
        revisionUpdated: task.revisionUpdated,
        expectedEvidence: task.expectedEvidence,
        readPaths: task.readPaths,
        writePaths: task.writePaths,
        doneCriteria: task.doneCriteria,
        outOfScope: task.outOfScope,
        context: task.context,
        expectedArtifacts: task.expectedArtifacts,
        recoveryIncidentId: task.recoveryIncidentId,
        fingerprint: task.fingerprint,
        rejectionReason: task.rejectionReason,
        failure: task.failure,
        currentStepId: task.currentStepId,
        memorySummary: task.memorySummary,
        runs: task.runs,
        pendingApproval: task.pendingApproval,
        pendingQuestion: task.pendingQuestion,
        chatSessionId: task.chatSessionId,
        projectId: task.projectId,
        planningMetrics: task.planningMetrics,
        planningError: task.planningError,
        createdAt: task.createdAt,
        updatedAt: task.updatedAt,
        completedAt: task.completedAt,
      );

  static TaskAggregate _fromSnapshot(
    task_snapshot.TaskSnapshotAggregate task,
  ) => TaskAggregate(
    persistenceRevision: task.persistenceRevision,
    id: task.id,
    title: task.title,
    originalPrompt: task.originalPrompt,
    objective: task.objective,
    constraints: task.constraints,
    successCriteria: task.successCriteria,
    gates: task.gates,
    steps: task.steps,
    status: task.status,
    criterionIds: task.criterionIds,
    milestoneId: task.milestoneId,
    dependsOnTaskIds: task.dependsOnTaskIds,
    priority: task.priority,
    risk: task.risk,
    riskReduction: task.riskReduction,
    effort: task.effort,
    selectionRationale: task.selectionRationale,
    revisionIntroduced: task.revisionIntroduced,
    revisionUpdated: task.revisionUpdated,
    expectedEvidence: task.expectedEvidence,
    readPaths: task.readPaths,
    writePaths: task.writePaths,
    doneCriteria: task.doneCriteria,
    outOfScope: task.outOfScope,
    context: task.context,
    expectedArtifacts: task.expectedArtifacts,
    recoveryIncidentId: task.recoveryIncidentId,
    fingerprint: task.fingerprint,
    rejectionReason: task.rejectionReason,
    failure: task.failure,
    currentStepId: task.currentStepId,
    memorySummary: task.memorySummary,
    runs: task.runs,
    pendingApproval: task.pendingApproval,
    pendingQuestion: task.pendingQuestion,
    chatSessionId: task.chatSessionId,
    projectId: task.projectId,
    planningMetrics: task.planningMetrics,
    planningError: task.planningError,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
    completedAt: task.completedAt,
  );
}
