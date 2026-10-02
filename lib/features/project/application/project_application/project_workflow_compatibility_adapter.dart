import 'package:hermes/core/cancellation.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/model/application/model_capabilities.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Bridges aggregate-shaped project ports at the owning feature boundary.
class ProjectWorkflowCompatibilityAdapter implements ProjectWorkflowPort {
  const ProjectWorkflowCompatibilityAdapter({
    required ProjectAggregateQueryPort queries,
    required ProjectPlanningPort planning,
    required ProjectCommandPort commands,
    required ProjectRecoveryCommandsPort recovery,
    required ProjectExecutionPort execution,
  }) : _queries = queries,
       _planning = planning,
       _commands = commands,
       _recovery = recovery,
       _execution = execution;

  final ProjectAggregateQueryPort _queries;
  final ProjectPlanningPort _planning;
  final ProjectCommandPort _commands;
  final ProjectRecoveryCommandsPort _recovery;
  final ProjectExecutionPort _execution;

  ProjectSummary _summary(ProjectAggregate project) => ProjectSummary(
    id: project.id,
    title: project.title,
    status: project.status,
    updatedAt: project.updatedAt,
    activeTaskId: project.activeTaskId,
    chatSessionId: project.chatSessionId,
  );

  TaskSummary _taskSummary(Task task) => TaskSummary(
    id: task.id,
    title: task.title,
    status: task.status,
    updatedAt: task.updatedAt,
    currentPhaseId: task.currentStepId,
    chatSessionId: task.chatSessionId,
    projectId: task.projectId,
  );

  ProjectWorkflowResult _result(ProjectCommandResult result) =>
      ProjectWorkflowResult(
        project: _summary(result.project),
        activeTask: result.activeTask == null
            ? null
            : _taskSummary(result.activeTask!),
        stopReason: _stopReason(result.stopReason),
        persistenceDiagnostics: result.persistenceDiagnostics,
      );

  ProjectWorkflowResult _projectResult(
    ProjectAggregate project, {
    Task? activeTask,
  }) => ProjectWorkflowResult(
    project: _summary(project),
    activeTask: activeTask == null ? null : _taskSummary(activeTask),
    stopReason: _stopReason(ProjectCommandStopReasonFor.project(project)),
  );

  ProjectWorkflowStopReason _stopReason(
    ProjectCommandStopReason reason,
  ) => switch (reason) {
    ProjectCommandStopReason.active => ProjectWorkflowStopReason.active,
    ProjectCommandStopReason.paused => ProjectWorkflowStopReason.paused,
    ProjectCommandStopReason.waitingForUser =>
      ProjectWorkflowStopReason.waitingForUser,
    ProjectCommandStopReason.blocked => ProjectWorkflowStopReason.blocked,
    ProjectCommandStopReason.degradedPlanning =>
      ProjectWorkflowStopReason.degradedPlanning,
    ProjectCommandStopReason.completed => ProjectWorkflowStopReason.completed,
    ProjectCommandStopReason.failed => ProjectWorkflowStopReason.failed,
    ProjectCommandStopReason.cancelled => ProjectWorkflowStopReason.cancelled,
    ProjectCommandStopReason.readOnly => ProjectWorkflowStopReason.readOnly,
  };

  Future<ProjectAggregate> _load(
    WorkspaceAttachment workspace,
    String projectId,
  ) async {
    final project = await _queries.loadProject(workspace, projectId);
    if (project == null) {
      throw StateError('Project $projectId could not be loaded.');
    }
    return project;
  }

  @override
  Future<ProjectWorkflowResult> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelConversationPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async => _projectResult(
    await _planning.createProject(
      workspace: workspace,
      userPrompt: userPrompt,
      chatSessionId: chatSessionId,
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      maxIterations: maxIterations,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
    ),
  );

  @override
  Future<ProjectWorkflowResult> addUserContext({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String text,
  }) async => _projectResult(
    await _planning.addUserContext(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
      text: text,
    ),
  );

  @override
  Future<ProjectWorkflowResult> requestScopeChange({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String context,
  }) async => _projectResult(
    await _planning.requestScopeChange(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
      context: context,
    ),
  );

  @override
  Future<ProjectWorkflowResult> updateProject({
    required WorkspaceAttachment workspace,
    required String projectId,
    required ProjectUpdateCommand command,
  }) async => _projectResult(
    await _commands.updateProject(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
      command: command,
    ),
  );

  @override
  Future<ProjectWorkflowResult> pauseProject({
    required WorkspaceAttachment workspace,
    required String projectId,
  }) async => _projectResult(
    await _commands.pauseProject(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
    ),
  );

  @override
  Future<ProjectWorkflowResult> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String answer,
  }) async => _projectResult(
    await _commands.answerOpenQuestion(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
      answer: answer,
    ),
  );

  @override
  Future<ProjectWorkflowResult> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required String projectId,
  }) async => _projectResult(
    await _commands.clearTaskBlocker(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
    ),
  );

  @override
  Future<ProjectWorkflowResult> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required String projectId,
  }) async => _projectResult(
    await _commands.approvePlanRevision(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
    ),
  );

  @override
  Future<ProjectWorkflowResult> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required String projectId,
  }) async => _projectResult(
    await _commands.rejectPlanRevision(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
    ),
  );

  @override
  Future<ProjectWorkflowResult> stopProject({
    required WorkspaceAttachment workspace,
    required String projectId,
  }) async => _projectResult(
    await _commands.stopProject(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
    ),
  );

  @override
  Future<ProjectWorkflowResult> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String incidentId,
  }) async => _projectResult(
    await _recovery.retryRecoveryIncident(
      workspace: workspace,
      snapshot: await _load(workspace, projectId),
      incidentId: incidentId,
    ),
  );

  @override
  Future<ProjectWorkflowResult> executeUntilStop(
    ProjectWorkflowExecution request, {
    required bool boundedRun,
  }) async {
    final result = await _execution.executeUntilStop(
      ProjectExecutionRequest(
        client: request.client,
        workspace: request.workspace,
        snapshot: await _load(request.workspace, request.projectId),
        baseSystemPrompt: request.baseSystemPrompt,
        maxNewTasks: request.maxNewTasks,
        maxIterations: request.maxIterations,
        requirePhaseApproval: request.requirePhaseApproval,
        compactionSettings: request.compactionSettings,
        contextLimitTokens: request.contextLimitTokens,
        onCompactionStatus: request.onCompactionStatus,
        onModelOutput: request.onModelOutput,
        onTaskUpdated: (task) => request.onTaskUpdated?.call(
          task == null ? null : _taskSummary(task),
        ),
        cancellationToken: request.cancellationToken,
        questionAutonomy: request.questionAutonomy,
        planApprovalPolicy: request.planApprovalPolicy,
      ),
      boundedRun: boundedRun,
    );
    return _result(result);
  }

  @override
  Future<ProjectWorkflowResult> recover(ProjectWorkflowRecovery request) async {
    final result = await _execution.recover(
      ProjectRecoveryRequest(
        workspace: request.workspace,
        snapshot: await _load(request.workspace, request.projectId),
        onTaskUpdated: (task) => request.onTaskUpdated?.call(
          task == null ? null : _taskSummary(task),
        ),
      ),
    );
    return _result(result);
  }
}

ProjectWorkflowPort adaptProjectWorkflowDependencies({
  required Object planning,
  required Object commands,
  required Object execution,
  required Object recovery,
}) {
  if (planning is ProjectWorkflowPort &&
      commands is ProjectWorkflowPort &&
      execution is ProjectWorkflowPort &&
      recovery is ProjectWorkflowPort) {
    return planning;
  }
  if (planning is ProjectPlanningPort &&
      planning is ProjectAggregateQueryPort &&
      commands is ProjectCommandPort &&
      execution is ProjectExecutionPort &&
      recovery is ProjectRecoveryCommandsPort) {
    final queryOwner = planning as ProjectAggregateQueryPort;
    return ProjectWorkflowCompatibilityAdapter(
      queries: queryOwner,
      planning: planning,
      commands: commands,
      recovery: recovery,
      execution: execution,
    );
  }
  throw ArgumentError('Unsupported project workflow dependency set.');
}
