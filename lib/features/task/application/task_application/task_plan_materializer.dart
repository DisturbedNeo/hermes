import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';

/// Explicit task-boundary adapter for planning-only project nodes.
class TaskPlanMaterializer implements TaskMaterializerPort {
  const TaskPlanMaterializer();

  TaskAggregate _createTask(ProjectTaskNode node) => TaskAggregate(
    id: node.id,
    title: node.title,
    originalPrompt: node.objective,
    objective: node.objective,
    status: node.status,
    constraints: node.constraints,
    acceptance: node.acceptance,
    milestoneId: node.milestoneId,
    dependsOnTaskIds: node.dependsOnTaskIds,
    priority: node.priority,
    risk: node.risk,
    riskReduction: node.riskReduction,
    effort: node.effort,
    selectionRationale: node.selectionRationale,
    revisionIntroduced: node.revisionIntroduced,
    revisionUpdated: node.revisionUpdated,
    readPaths: node.readPaths,
    writePaths: node.writePaths,
    outOfScope: node.outOfScope,
    context: node.context,
    recoveryIncidentId: node.recoveryIncidentId,
    fingerprint: node.fingerprint.isEmpty
        ? [
            node.objective.trim().toLowerCase(),
            for (final item in node.acceptance) item.ref,
          ].join('|')
        : node.fingerprint,
    rejectionReason: node.rejectionReason,
    createdAt: node.createdAt,
    updatedAt: node.updatedAt,
    planningError: node.planningError,
  );

  @override
  TaskAggregate create(
    ProjectTaskNode node, {
    required String projectId,
    String? chatSessionId,
  }) => _createTask(
    node,
  ).copyWith(projectId: projectId, chatSessionId: chatSessionId);

  @override
  TaskAggregate apply(
    ProjectTaskNode node,
    TaskAggregate existing, {
    required String projectId,
    String? chatSessionId,
  }) => existing.copyWith(
    title: node.title,
    originalPrompt: node.objective,
    objective: node.objective,
    constraints: node.constraints,
    acceptance: node.acceptance,
    milestoneId: node.milestoneId,
    dependsOnTaskIds: node.dependsOnTaskIds,
    priority: node.priority,
    risk: node.risk,
    riskReduction: node.riskReduction,
    effort: node.effort,
    selectionRationale: node.selectionRationale,
    revisionIntroduced: node.revisionIntroduced,
    revisionUpdated: node.revisionUpdated,
    readPaths: node.readPaths,
    writePaths: node.writePaths,
    outOfScope: node.outOfScope,
    context: node.context,
    status: node.status,
    recoveryIncidentId: node.recoveryIncidentId,
    fingerprint: node.fingerprint,
    rejectionReason: node.rejectionReason,
    projectId: projectId,
    chatSessionId: chatSessionId,
    planningError: node.planningError,
  );

  @override
  bool matches(ProjectTaskNode node, TaskAggregate task) =>
      node.title == task.title &&
      node.objective == task.objective &&
      node.constraints.equals(task.constraints) &&
      node.acceptance.equals(task.acceptance) &&
      node.milestoneId == task.milestoneId &&
      node.dependsOnTaskIds.equals(task.dependsOnTaskIds) &&
      node.priority == task.priority &&
      node.risk == task.risk &&
      node.riskReduction == task.riskReduction &&
      node.effort == task.effort &&
      node.selectionRationale == task.selectionRationale &&
      node.revisionIntroduced == task.revisionIntroduced &&
      node.revisionUpdated == task.revisionUpdated &&
      node.readPaths.equals(task.readPaths) &&
      node.writePaths.equals(task.writePaths) &&
      node.outOfScope.equals(task.outOfScope) &&
      node.context.equals(task.context) &&
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
