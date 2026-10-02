import 'dart:async';

import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';

import 'package:hermes/features/project/runtime/project_execution_runtime.dart';

class ProjectRuntimeApplication
    implements
        ProjectWorkflowQueryPort,
        ProjectSessionPort,
        ProjectPlanningPort,
        ProjectCommandPort,
        ProjectRecoveryCommandsPort,
        ProjectExecutionPort {
  ProjectRuntimeApplication({
    required TaskWorkflowQueryPort taskQueries,
    required TaskPlanningPort taskPlanning,
    required TaskProjectPlanningPort taskProjectPlanning,
    required TaskExecutionPort taskExecution,
    required TaskRecoveryPort taskRecovery,
    required ToolRegistryPort toolService,
    required TaskMaterializerPort materializer,
    required ProjectAggregateReadPort aggregateRepository,
    required ProjectRuntimeDependencies dependencies,
  }) {
    final executionPort =
        dependencies.executionPort ??
        CallbackProjectCommandExecutionPort(
          (request) => _delegate.runProjectForCommand(request),
        );
    final recoveryPort =
        dependencies.recoveryPort ??
        CallbackProjectRecoveryPort(
          (request) => _delegate.recoverProjectForCommand(request),
        );
    _delegate = ProjectExecutionRuntime(
      taskQueries: taskQueries,
      taskPlanning: taskPlanning,
      taskProjectPlanning: taskProjectPlanning,
      taskExecution: taskExecution,
      taskRecovery: taskRecovery,
      toolService: toolService,
      materializer: materializer,
      aggregateRepository: aggregateRepository,
      dependencies: dependencies,
      executionPort: executionPort,
      recoveryPort: recoveryPort,
    );
  }

  late final ProjectExecutionRuntime _delegate;

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
  Future<ProjectAggregate?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _delegate.loadLatestProject(workspace, chatSessionId: chatSessionId);

  @override
  Future<ProjectAggregate?> loadProject(
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
  Future<void> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String sourceChatSessionId,
    required String chatSessionId,
  }) => _delegate.updateProjectChatSessionId(
    workspace: workspace,
    projectId: projectId,
    sourceChatSessionId: sourceChatSessionId,
    chatSessionId: chatSessionId,
  );

  @override
  Future<ProjectAggregate> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelConversationPort? client,
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
  Future<ProjectAggregate> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required ProjectUpdateCommand command,
  }) => _delegate.updateProject(
    workspace: workspace,
    snapshot: snapshot,
    command: command,
  );

  @override
  Future<ProjectAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String answer,
  }) => _delegate.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  @override
  Future<ProjectAggregate> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String text,
  }) => _delegate.addUserContext(
    workspace: workspace,
    snapshot: snapshot,
    text: text,
  );

  @override
  Future<ProjectAggregate> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String context,
  }) => _delegate.requestScopeChange(
    workspace: workspace,
    snapshot: snapshot,
    context: context,
  );

  @override
  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _delegate.pauseProject(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectAggregate> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _delegate.clearTaskBlocker(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectAggregate> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _delegate.approvePlanRevision(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectAggregate> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _delegate.rejectPlanRevision(workspace: workspace, snapshot: snapshot);

  @override
  Future<ProjectAggregate> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String incidentId,
  }) => _delegate.retryRecoveryIncident(
    workspace: workspace,
    snapshot: snapshot,
    incidentId: incidentId,
  );

  @override
  Future<ProjectAggregate> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _delegate.stopProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectAggregate> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _delegate.cancelProject(workspace: workspace, snapshot: snapshot);
}
