import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Converts runtime aggregates into detached, presentation-owned read models.
///
/// Keeping this adapter outside the read-model types prevents chat state and
/// widgets from retaining domain aggregates while preserving the domain
/// scheduler and workspace selector as the single sources of derived values.
abstract final class ChatPanelProjection {
  static TaskPanelReadModel task(Task source) {
    final snapshot = _snapshotTask(source);
    return TaskPanelReadModel(
      id: snapshot.id,
      title: snapshot.title,
      objective: snapshot.objective,
      status: snapshot.status,
      steps: snapshot.steps,
      runs: snapshot.runs,
      pendingApproval: snapshot.pendingApproval,
      pendingQuestion: snapshot.pendingQuestion,
      planningMetrics: snapshot.planningMetrics,
      memorySummary: snapshot.memorySummary,
      doneCriteria: snapshot.doneCriteria,
      outOfScope: snapshot.outOfScope,
      currentStepId: snapshot.currentStepId,
      projectId: snapshot.projectId,
      chatSessionId: snapshot.chatSessionId,
      failure: snapshot.failure,
    );
  }

  static ProjectPanelReadModel project(ProjectAggregate source) {
    final snapshot = _snapshotProject(source);
    final schedule = const ProjectScheduler().refreshReadiness(snapshot);
    final workspace = const ProjectWorkspaceContextService().selectContext(
      project: snapshot,
    );
    return ProjectPanelReadModel(
      id: snapshot.id,
      title: snapshot.title,
      originalGoal: snapshot.originalGoal,
      refinedGoal: snapshot.refinedGoal,
      status: snapshot.status,
      activeTaskId: snapshot.activeTaskId,
      chatSessionId: snapshot.chatSessionId,
      iterationCount: snapshot.iterationCount,
      maxIterations: snapshot.maxIterations,
      completionSummary: snapshot.completionSummary,
      constraints: snapshot.constraints,
      tasks: snapshot.tasks,
      artifacts: snapshot.artifacts,
      criteria: snapshot.criteria,
      recoveryIncidents: snapshot.recoveryIncidents,
      evidence: snapshot.evidence,
      milestones: snapshot.milestones,
      memory: snapshot.memory,
      decisions: snapshot.decisions,
      planHistory: snapshot.planHistory,
      workspaceGraph: snapshot.workspaceGraph,
      pendingPlanApproval: snapshot.pendingPlanApproval,
      blocker: snapshot.blocker,
      openQuestions: snapshot.openQuestions,
      diagnostics: snapshot.diagnostics,
      schedule: ProjectScheduleReadModel(
        readiness: Map<String, TaskReadiness>.unmodifiable(schedule.readiness),
        readinessReasons: Map<String, List<String>>.unmodifiable({
          for (final entry in schedule.readinessReasons.entries)
            entry.key: List<String>.unmodifiable(entry.value),
        }),
      ),
      orderedReadyTasks: List.unmodifiable(
        const ProjectScheduler().orderedReadyTasks(snapshot),
      ),
      workspaceContext: ProjectWorkspaceContextReadModel(
        orientation: workspace.orientation,
        nodes: List.unmodifiable(workspace.nodes),
        edges: List.unmodifiable(workspace.edges),
        maxCharacters: workspace.maxCharacters,
        usedCharacters: workspace.usedCharacters,
        truncated: workspace.truncated,
      ),
    );
  }
}

Task _snapshotTask(Task source) => source.copyWith(
  constraints: List.unmodifiable(source.constraints),
  successCriteria: List.unmodifiable(source.successCriteria),
  gates: List.unmodifiable(source.gates.map(_snapshotGate)),
  steps: List.unmodifiable(source.steps.map(_snapshotStep)),
  criterionIds: List.unmodifiable(source.criterionIds),
  dependsOnTaskIds: List.unmodifiable(source.dependsOnTaskIds),
  expectedEvidence: List.unmodifiable(
    source.expectedEvidence.map(_snapshotEvidenceExpectation),
  ),
  readPaths: List.unmodifiable(source.readPaths),
  writePaths: List.unmodifiable(source.writePaths),
  doneCriteria: List.unmodifiable(source.doneCriteria),
  outOfScope: List.unmodifiable(source.outOfScope),
  context: List.unmodifiable(source.context),
  expectedArtifacts: List.unmodifiable(
    source.expectedArtifacts.map(_snapshotArtifact),
  ),
  runs: List.unmodifiable(source.runs.map(_snapshotRun)),
);

TaskGate _snapshotGate(TaskGate source) => TaskGate(
  id: source.id,
  required: source.required,
  scope: source.scope,
  params: _snapshotMap(source.params),
  description: source.description,
);

TaskEvidenceExpectation _snapshotEvidenceExpectation(
  TaskEvidenceExpectation source,
) => TaskEvidenceExpectation(
  id: source.id,
  type: source.type,
  criterionIds: List.unmodifiable(source.criterionIds),
  description: source.description,
  required: source.required,
  sourceRef: source.sourceRef,
  details: _snapshotMap(source.details),
);

TaskArtifact _snapshotArtifact(TaskArtifact source) => source.copyWith();

TaskStep _snapshotStep(TaskStep source) => source.copyWith(
  instructions: List.unmodifiable(source.instructions),
  artifacts: List.unmodifiable(source.artifacts.map(_snapshotArtifact)),
  gates: List.unmodifiable(source.gates.map(_snapshotGate)),
);

TaskRun _snapshotRun(TaskRun source) => source.copyWith(
  toolCalls: List.unmodifiable(source.toolCalls),
  artifacts: List.unmodifiable(source.artifacts.map(_snapshotArtifact)),
  gateResults: List.unmodifiable(source.gateResults),
  evidenceClaims: List.unmodifiable(source.evidenceClaims),
);

ProjectAggregate _snapshotProject(ProjectAggregate source) => source.copyWith(
  criteria: List.unmodifiable(source.criteria.map(_snapshotCriterion)),
  constraints: List.unmodifiable(source.constraints),
  taskIds: List.unmodifiable(source.taskIds),
  currentBatchTaskIds: List.unmodifiable(source.currentBatchTaskIds),
  tasks: List.unmodifiable(source.tasks.map(_snapshotProjectTask)),
  artifacts: List.unmodifiable(source.artifacts.map(_snapshotArtifact)),
  recoveryIncidents: List.unmodifiable(
    source.recoveryIncidents.map(_snapshotRecoveryIncident),
  ),
  evidence: List.unmodifiable(source.evidence.map(_snapshotEvidence)),
  milestones: List.unmodifiable(source.milestones.map(_snapshotMilestone)),
  memory: List.unmodifiable(source.memory.map(_snapshotMemory)),
  workspaceGraph: source.workspaceGraph.copyWith(
    nodes: List.unmodifiable(
      source.workspaceGraph.nodes.map(_snapshotWorkspaceNode),
    ),
    edges: List.unmodifiable(
      source.workspaceGraph.edges.map(_snapshotWorkspaceEdge),
    ),
  ),
  planHistory: List.unmodifiable(source.planHistory.map(_snapshotPlanRevision)),
  pendingReplanTriggers: List.unmodifiable(source.pendingReplanTriggers),
  openQuestions: List.unmodifiable(source.openQuestions),
  decisions: List.unmodifiable(source.decisions),
);

ProjectCriterion _snapshotCriterion(ProjectCriterion source) =>
    source.copyWith();

ProjectEvidence _snapshotEvidence(ProjectEvidence source) => source.copyWith(
  criterionIds: List.unmodifiable(source.criterionIds),
  expectationIds: List.unmodifiable(source.expectationIds),
  details: _snapshotMap(source.details),
);

ProjectMilestone _snapshotMilestone(ProjectMilestone source) =>
    ProjectMilestone(
      id: source.id,
      title: source.title,
      objective: source.objective,
      criterionIds: List.unmodifiable(source.criterionIds),
      status: source.status,
      exitConditions: List.unmodifiable(source.exitConditions),
      order: source.order,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      completedAt: source.completedAt,
    );

ProjectMemoryEntry _snapshotMemory(ProjectMemoryEntry source) =>
    source.copyWith(coveredEntryIds: List.unmodifiable(source.coveredEntryIds));

ProjectRecoveryIncident _snapshotRecoveryIncident(
  ProjectRecoveryIncident source,
) => source.copyWith(
  sourceTaskIds: List.unmodifiable(source.sourceTaskIds),
  sourceTaskTitles: List.unmodifiable(source.sourceTaskTitles),
  recoveryTaskIds: List.unmodifiable(source.recoveryTaskIds),
);

ProjectPlanRevision _snapshotPlanRevision(ProjectPlanRevision source) =>
    ProjectPlanRevision(
      revision: source.revision,
      trigger: source.trigger,
      summary: source.summary,
      rationale: source.rationale,
      addedTaskIds: List.unmodifiable(source.addedTaskIds),
      updatedTaskIds: List.unmodifiable(source.updatedTaskIds),
      removedTaskIds: List.unmodifiable(source.removedTaskIds),
      criterionChanges: List.unmodifiable(source.criterionChanges),
      milestoneChanges: List.unmodifiable(source.milestoneChanges),
      validationWarnings: List.unmodifiable(source.validationWarnings),
      createdAt: source.createdAt,
      approvedAt: source.approvedAt,
      approvedBy: source.approvedBy,
    );

ProjectWorkspaceNode _snapshotWorkspaceNode(ProjectWorkspaceNode source) =>
    source.copyWith(
      aliases: List.unmodifiable(source.aliases),
      tags: List.unmodifiable(source.tags),
      references: List.unmodifiable(source.references),
    );

ProjectWorkspaceEdge _snapshotWorkspaceEdge(ProjectWorkspaceEdge source) =>
    source.copyWith();

ProjectTaskNode _snapshotProjectTask(ProjectTaskNode source) => source.copyWith(
  gates: List.unmodifiable(source.gates.map(_snapshotGate)),
  constraints: List.unmodifiable(source.constraints),
  successCriteria: List.unmodifiable(source.successCriteria),
  criterionIds: List.unmodifiable(source.criterionIds),
  dependsOnTaskIds: List.unmodifiable(source.dependsOnTaskIds),
  expectedEvidence: List.unmodifiable(
    source.expectedEvidence.map(_snapshotEvidenceExpectation),
  ),
  readPaths: List.unmodifiable(source.readPaths),
  writePaths: List.unmodifiable(source.writePaths),
  doneCriteria: List.unmodifiable(source.doneCriteria),
  outOfScope: List.unmodifiable(source.outOfScope),
  context: List.unmodifiable(source.context),
  expectedArtifacts: List.unmodifiable(
    source.expectedArtifacts.map(_snapshotArtifact),
  ),
  failureErrorCodes: List.unmodifiable(source.failureErrorCodes),
);

Map<String, dynamic> _snapshotMap(Map<String, dynamic> source) =>
    Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: _snapshotValue(entry.value),
    });

Object? _snapshotValue(Object? value) {
  if (value is Map<String, dynamic>) return _snapshotMap(value);
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _snapshotValue(entry.value),
    });
  }
  if (value is Iterable) {
    return List.unmodifiable(value.map(_snapshotValue));
  }
  return value;
}
