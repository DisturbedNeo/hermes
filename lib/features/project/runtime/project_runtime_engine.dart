import 'dart:async';

import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/model_completion_port.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/features/project/runtime/project_model_calls.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_state_store.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/shared_kernel/planning_runtime.dart';
import 'package:hermes/shared_kernel/planning_structured_output.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';

import 'package:hermes/features/project/runtime/project_runtime_collaborators.dart';

class ProjectRuntimeApplication implements ProjectChatPort {
  ProjectRuntimeApplication({
    required TaskProjectPort taskController,
    required TaskPersistencePort taskPersistence,
    required ToolRegistryPort toolService,
    required WorkspaceSandboxPort sandbox,
    required TaskMaterializerPort materializer,
    required ProjectRepositoryPort repository,
    required ProjectAggregateRepositoryPort aggregateRepository,
    ProjectPlanner? planner,
    ProjectCompletionEvaluator? completionEvaluator,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
    PersistencePort? persistenceCoordinator,
    ProjectStateStore? stateStore,
    ProjectCommandService? commandService,
    ProjectCommandExecutionPort? executionPort,
    ProjectRecoveryPort? recoveryPort,
    PlanningToolCallRunner? planningRunner,
    StructuredPlanningOutputService? structuredOutput,
    ProjectLifecycleService? lifecycle,
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectRecoveryService? recoveryService,
  }) : _delegate = ProjectRuntimeContext(
         taskController: taskController,
         taskPersistence: taskPersistence,
         toolService: toolService,
         sandbox: sandbox,
         materializer: materializer,
         repository: repository,
         aggregateRepository: aggregateRepository,
         planner: planner,
         completionEvaluator: completionEvaluator,
         scheduler: scheduler,
         memoryService: memoryService,
         progressMonitor: progressMonitor,
         persistenceCoordinator: persistenceCoordinator,
         stateStore: stateStore,
         commandService: commandService,
         executionPort: executionPort,
         recoveryPort: recoveryPort,
         planningRunner: planningRunner ?? const PlanningToolCallRunner(),
         structuredOutput:
             structuredOutput ?? const StructuredPlanningOutputService(),
         lifecycle: lifecycle ?? const ProjectLifecycleService(),
         taskLifecycle: taskLifecycle,
         completion: completion,
         recoveryService: recoveryService,
       );

  final ProjectRuntimeContext _delegate;

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _delegate.execute(request);

  @override
  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  }) => _delegate.executeUntilStop(request, boundedRun: boundedRun);

  @override
  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request) =>
      _delegate.recover(request);

  Future<ProjectTransactionRecoveryResult> recoverPersistence(
    WorkspaceAttachment workspace,
  ) => _delegate.recoverPersistence(workspace);

  @override
  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _delegate.listProjects(workspace, chatSessionId: chatSessionId);

  @override
  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _delegate.loadLatestProject(workspace, chatSessionId: chatSessionId);

  @override
  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) =>
      _delegate.loadProject(workspace, projectId, chatSessionId: chatSessionId);

  @override
  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _delegate.deleteProjectsForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  @override
  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _delegate.deleteOrphanedChatProjects(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  @override
  Future<ProjectDocument> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String chatSessionId,
  }) => _delegate.updateProjectChatSessionId(
    workspace: workspace,
    snapshot: snapshot,
    chatSessionId: chatSessionId,
  );

  @override
  String encodeProject(ProjectDocument project) =>
      _delegate.encodeProject(project);

  @override
  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelCompletionPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) => _delegate.createProject(
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

  @override
  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  }) => _delegate.updateProject(
    workspace: workspace,
    snapshot: snapshot,
    rawJson: rawJson,
  );

  @override
  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  }) => _delegate.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  @override
  Future<ProjectDocument> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String text,
  }) => _delegate.addUserContext(
    workspace: workspace,
    snapshot: snapshot,
    text: text,
  );

  @override
  Future<ProjectDocument> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String context,
  }) => _delegate.requestScopeChange(
    workspace: workspace,
    snapshot: snapshot,
    context: context,
  );

  @override
  Future<ProjectDocument> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _delegate.pauseProject(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectDocument> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _delegate.clearTaskBlocker(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectDocument> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _delegate.approvePlanRevision(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectDocument> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _delegate.rejectPlanRevision(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectDocument> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String incidentId,
  }) => _delegate.retryRecoveryIncident(
    workspace: workspace,
    snapshot: snapshot,
    incidentId: incidentId,
  );

  @override
  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _delegate.stopProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _delegate.cancelProject(workspace: workspace, snapshot: snapshot);
}
