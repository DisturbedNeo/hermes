import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/project_system/project_memory_service.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_completion_service.dart';
import 'package:hermes/core/services/project_system/project_lifecycle_service.dart';
import 'package:hermes/core/services/project_system/project_progress_monitor.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:hermes/core/services/project_system/project_aggregate_repository.dart';
import 'package:hermes/core/services/project_system/project_state_store.dart';
import 'package:hermes/core/services/project_system/project_command_service.dart';
import 'package:hermes/core/services/project_system/project_recovery_service.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_lifecycle_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';
import 'package:hermes/core/services/project_system/project_workflow_service.dart';

int taskStepLimit(TaskEffort effort) => switch (effort) {
  TaskEffort.small => 1,
  TaskEffort.medium => 4,
  TaskEffort.large => 6,
};

/// Application-facing project command and lifecycle boundary.
/// Stable application façade retained for UI and command callers.
class ProjectOrchestrator {
  ProjectOrchestrator({
    required TaskService taskService,
    ProjectRepository? repository,
    ProjectPlanner? planner,
    ProjectCompletionEvaluator? completionEvaluator,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
    WorkspacePersistenceCoordinator? persistenceCoordinator,
    ProjectAggregateRepository? aggregateRepository,
    ProjectStateStore? stateStore,
    ProjectCommandService? commandService,
    ProjectExecutionPort? executionPort,
    ProjectRecoveryPort? recoveryPort,
    PlanningToolCallRunner planningRunner = const PlanningToolCallRunner(),
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    ProjectLifecycleService lifecycle = const ProjectLifecycleService(),
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectRecoveryService? recoveryService,
  }) : _runtime = ProjectWorkflowService(
         taskService: taskService,
         repository: repository,
         planner: planner,
         completionEvaluator: completionEvaluator,
         scheduler: scheduler,
         memoryService: memoryService,
         progressMonitor: progressMonitor,
         persistenceCoordinator: persistenceCoordinator,
         aggregateRepository: aggregateRepository,
         stateStore: stateStore,
         commandService: commandService,
         executionPort: executionPort,
         recoveryPort: recoveryPort,
         planningRunner: planningRunner,
         structuredOutput: structuredOutput,
         lifecycle: lifecycle,
         taskLifecycle: taskLifecycle,
         completion: completion,
         recoveryService: recoveryService,
       );

  final ProjectWorkflowService _runtime;

  ProjectRepository get repository => _runtime.repository;

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _runtime.execute(request);

  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  }) => _runtime.executeUntilStop(request, boundedRun: boundedRun);

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request) =>
      _runtime.recover(request);

  Future<ProjectTransactionRecoveryResult> recoverPersistence(
    WorkspaceAttachment workspace,
  ) => _runtime.recoverPersistence(workspace);

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _runtime.listProjects(workspace, chatSessionId: chatSessionId);

  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _runtime.loadLatestProject(workspace, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadLatestProjectResult(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) =>
      _runtime.loadLatestProjectResult(workspace, chatSessionId: chatSessionId);

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) =>
      _runtime.loadProject(workspace, projectId, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadProjectResult(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) => _runtime.loadProjectResult(
    workspace,
    projectId,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _runtime.deleteProjectsForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _runtime.deleteOrphanedChatProjects(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<ProjectDocument> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String chatSessionId,
  }) => _runtime.updateProjectChatSessionId(
    workspace: workspace,
    snapshot: snapshot,
    chatSessionId: chatSessionId,
  );

  String encodeProject(ProjectDocument project) =>
      _runtime.encodeProject(project);

  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ChatClient? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) => _runtime.createProject(
    workspace: workspace,
    userPrompt: userPrompt,
    chatSessionId: chatSessionId,
    client: client,
    baseSystemPrompt: baseSystemPrompt,
    maxIterations: maxIterations,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
    questionAutonomy: questionAutonomy,
  );

  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  }) => _runtime.updateProject(
    workspace: workspace,
    snapshot: snapshot,
    rawJson: rawJson,
  );

  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  }) => _runtime.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  Future<ProjectDocument> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String text,
  }) => _runtime.addUserContext(
    workspace: workspace,
    snapshot: snapshot,
    text: text,
  );

  Future<ProjectDocument> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String context,
  }) => _runtime.requestScopeChange(
    workspace: workspace,
    snapshot: snapshot,
    context: context,
  );

  Future<ProjectDocument> compactMemory({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required List<String> coveredEntryIds,
    required String summary,
  }) => _runtime.compactMemory(
    workspace: workspace,
    snapshot: snapshot,
    coveredEntryIds: coveredEntryIds,
    summary: summary,
  );

  Future<ProjectDocument> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.pauseProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.clearTaskBlocker(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.approvePlanRevision(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.rejectPlanRevision(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.cancelProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.stopProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String incidentId,
  }) => _runtime.retryRecoveryIncident(
    workspace: workspace,
    snapshot: snapshot,
    incidentId: incidentId,
  );
}
