import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';

/// Explicit task-boundary adapter for planning-only project nodes.
class TaskPlanMaterializer implements TaskMaterializerPort {
  const TaskPlanMaterializer();

  Task _createTask(ProjectTaskNode node) => Task(
    id: node.id,
    title: node.title,
    originalPrompt: node.objective,
    objective: node.objective,
    status: node.status,
    gates: node.gates,
    constraints: node.constraints,
    successCriteria: node.successCriteria,
    criterionIds: node.criterionIds,
    milestoneId: node.milestoneId,
    dependsOnTaskIds: node.dependsOnTaskIds,
    priority: node.priority,
    risk: node.risk,
    riskReduction: node.riskReduction,
    effort: node.effort,
    selectionRationale: node.selectionRationale,
    revisionIntroduced: node.revisionIntroduced,
    revisionUpdated: node.revisionUpdated,
    expectedEvidence: node.expectedEvidence,
    readPaths: node.readPaths,
    writePaths: node.writePaths,
    doneCriteria: node.doneCriteria,
    outOfScope: node.outOfScope,
    context: node.context,
    expectedArtifacts: node.expectedArtifacts,
    recoveryIncidentId: node.recoveryIncidentId,
    fingerprint: node.fingerprint.isEmpty
        ? [node.objective.trim().toLowerCase(), ...node.criterionIds].join('|')
        : node.fingerprint,
    rejectionReason: node.rejectionReason,
    createdAt: node.createdAt,
    updatedAt: node.updatedAt,
    planningError: node.planningError,
  );

  @override
  Task create(
    ProjectTaskNode node, {
    required String projectId,
    String? chatSessionId,
  }) => _createTask(
    node,
  ).copyWith(projectId: projectId, chatSessionId: chatSessionId);

  @override
  Task apply(
    ProjectTaskNode node,
    Task existing, {
    required String projectId,
    String? chatSessionId,
  }) => existing.copyWith(
    title: node.title,
    originalPrompt: node.objective,
    objective: node.objective,
    constraints: node.constraints,
    successCriteria: node.successCriteria,
    gates: node.gates,
    criterionIds: node.criterionIds,
    milestoneId: node.milestoneId,
    dependsOnTaskIds: node.dependsOnTaskIds,
    priority: node.priority,
    risk: node.risk,
    riskReduction: node.riskReduction,
    effort: node.effort,
    selectionRationale: node.selectionRationale,
    revisionIntroduced: node.revisionIntroduced,
    revisionUpdated: node.revisionUpdated,
    expectedEvidence: node.expectedEvidence,
    readPaths: node.readPaths,
    writePaths: node.writePaths,
    doneCriteria: node.doneCriteria,
    outOfScope: node.outOfScope,
    context: node.context,
    expectedArtifacts: node.expectedArtifacts,
    status: node.status,
    recoveryIncidentId: node.recoveryIncidentId,
    fingerprint: node.fingerprint,
    rejectionReason: node.rejectionReason,
    projectId: projectId,
    chatSessionId: chatSessionId,
    planningError: node.planningError,
  );

  @override
  bool matches(ProjectTaskNode node, Task task) =>
      node.title == task.title &&
      node.objective == task.objective &&
      node.constraints.equals(task.constraints) &&
      node.successCriteria.equals(task.successCriteria) &&
      node.gates.equals(task.gates) &&
      node.criterionIds.equals(task.criterionIds) &&
      node.milestoneId == task.milestoneId &&
      node.dependsOnTaskIds.equals(task.dependsOnTaskIds) &&
      node.priority == task.priority &&
      node.risk == task.risk &&
      node.riskReduction == task.riskReduction &&
      node.effort == task.effort &&
      node.selectionRationale == task.selectionRationale &&
      node.revisionIntroduced == task.revisionIntroduced &&
      node.revisionUpdated == task.revisionUpdated &&
      node.expectedEvidence.equals(task.expectedEvidence) &&
      node.readPaths.equals(task.readPaths) &&
      node.writePaths.equals(task.writePaths) &&
      node.doneCriteria.equals(task.doneCriteria) &&
      node.outOfScope.equals(task.outOfScope) &&
      node.context.equals(task.context) &&
      node.expectedArtifacts.equals(task.expectedArtifacts) &&
      node.status == task.status &&
      node.recoveryIncidentId == task.recoveryIncidentId &&
      node.fingerprint == task.fingerprint &&
      node.rejectionReason == task.rejectionReason &&
      node.planningError == task.planningError;
}

extension on Object? {
  bool equals(Object? other) {
    if (this is! Iterable || other is! Iterable) return this == other;
    final left = (this as Iterable).toList();
    final right = other.toList();
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
