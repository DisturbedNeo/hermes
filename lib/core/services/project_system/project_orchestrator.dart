import 'dart:async';

import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_completion_service.dart';
import 'package:hermes/core/services/project_system/project_execution_service.dart';
import 'package:hermes/core/services/project_system/project_lifecycle_service.dart';
import 'package:hermes/core/services/project_system/project_recovery_service.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_lifecycle_service.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';

/// Application-facing project command boundary.
///
/// ProjectService remains as a compatibility implementation for existing
/// callers and tests. New callers use this class, which adds lifecycle guards,
/// revision validation, and a shared non-queueing command gate around it.
class ProjectOrchestrator extends ProjectService {
  ProjectOrchestrator({
    required super.taskService,
    super.repository,
    super.planner,
    super.completionEvaluator,
    super.scheduler,
    super.memoryService,
    super.progressMonitor,
    super.persistenceCoordinator,
    super.aggregateRepository,
    super.planningRunner,
    super.structuredOutput,
    ProjectLifecycleService lifecycle = const ProjectLifecycleService(),
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectExecutionService? execution,
    ProjectRecoveryService? recovery,
  }) : _persistenceCoordinator =
           persistenceCoordinator ?? taskService.repository.coordinator,
       lifecycleService = lifecycle,
       taskLifecycleService = taskLifecycle ?? const TaskLifecycleService(),
       completionService =
           completion ?? ProjectCompletionService(lifecycle: lifecycle) {
    executionService =
        execution ?? ProjectExecutionService(run: _runLegacyExecution);
    recoveryService =
        recovery ?? ProjectRecoveryService(recover: _runLegacyRecovery);
  }

  final WorkspacePersistenceCoordinator _persistenceCoordinator;
  final ProjectLifecycleService lifecycleService;
  final TaskLifecycleService taskLifecycleService;
  final ProjectCompletionService completionService;
  late final ProjectExecutionService executionService;
  late final ProjectRecoveryService recoveryService;

  final Set<String> _busyProjects = <String>{};
  final Object _commandZoneKey = Object();

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) {
    return _withProjectCommand(
      request.workspace,
      request.snapshot,
      () => _executeOnce(request),
    );
  }

  /// Executes successive bounded runs until the project reaches a user-facing
  /// boundary. The command gate is held for the whole sequence, so another
  /// tab cannot start a second project command between automatic continuations.
  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  }) {
    return _withProjectCommand(request.workspace, request.snapshot, () async {
      var current = request;
      while (true) {
        final result = await _executeOnce(current);
        if (boundedRun || !_shouldContinue(result)) return result;
        current = current.copyWith(snapshot: result.project);
      }
    });
  }

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request) {
    return _withProjectCommand(request.workspace, request.snapshot, () async {
      final readOnly = await _ensureCurrentSnapshot(
        ProjectExecutionRequest(
          client: _NoopChatClient(),
          workspace: request.workspace,
          snapshot: request.snapshot,
          baseSystemPrompt: '',
          maxNewTasks: 0,
        ),
      );
      if (readOnly != null) {
        return ProjectCommandResult(
          project: request.snapshot,
          stopReason: ProjectCommandStopReason.readOnly,
          persistenceDiagnostics: readOnly,
        );
      }
      final result = await recoveryService.recover(request);
      return ProjectCommandResult.fromRun(
        result: result,
        before: request.snapshot,
        trigger: 'recover',
      );
    });
  }

  @override
  Future<ProjectRunResult> runProject({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    required int maxNewTasks,
    int? maxIterations,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    ProjectPlanApprovalPolicy planApprovalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) async {
    final result = await execute(
      ProjectExecutionRequest(
        client: client,
        workspace: workspace,
        snapshot: snapshot,
        baseSystemPrompt: baseSystemPrompt,
        maxNewTasks: maxNewTasks,
        maxIterations: maxIterations,
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        onTaskUpdated: onTaskUpdated,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
        planApprovalPolicy: planApprovalPolicy,
      ),
    );
    return result.asRunResult();
  }

  @override
  Future<ProjectRunResult> runNextProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    ProjectPlanApprovalPolicy planApprovalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) {
    return runProject(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      maxNewTasks: 1,
      requirePhaseApproval: requirePhaseApproval,
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      onModelOutput: onModelOutput,
      onTaskUpdated: onTaskUpdated,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
      planApprovalPolicy: planApprovalPolicy,
    );
  }

  @override
  Future<ProjectRunResult> recoverProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    ProjectTaskSnapshotSink? onTaskUpdated,
  }) async {
    if (Zone.current[_commandZoneKey] == true) {
      return super.recoverProject(
        workspace: workspace,
        snapshot: snapshot,
        onTaskUpdated: onTaskUpdated,
      );
    }
    final result = await recover(
      ProjectRecoveryRequest(
        workspace: workspace,
        snapshot: snapshot,
        onTaskUpdated: onTaskUpdated,
      ),
    );
    return result.asRunResult();
  }

  Future<ProjectRunResult> _runLegacyExecution(
    ProjectExecutionRequest request,
  ) => super.runProject(
    client: request.client,
    workspace: request.workspace,
    snapshot: request.snapshot,
    baseSystemPrompt: request.baseSystemPrompt,
    maxNewTasks: request.maxNewTasks,
    maxIterations: request.maxIterations,
    requirePhaseApproval: request.requirePhaseApproval,
    compactionSettings: request.compactionSettings,
    contextLimitTokens: request.contextLimitTokens,
    onCompactionStatus: request.onCompactionStatus,
    onModelOutput: request.onModelOutput,
    onTaskUpdated: request.onTaskUpdated,
    cancellationToken: request.cancellationToken,
    questionAutonomy: request.questionAutonomy,
    planApprovalPolicy: request.planApprovalPolicy,
  );

  Future<ProjectRunResult> _runLegacyRecovery(ProjectRecoveryRequest request) =>
      super.recoverProject(
        workspace: request.workspace,
        snapshot: request.snapshot,
        onTaskUpdated: request.onTaskUpdated,
      );

  Future<ProjectPersistenceDiagnostics?> _ensureCurrentSnapshot(
    ProjectExecutionRequest request,
  ) async {
    final loaded = await loadProjectResult(
      request.workspace,
      request.snapshot.id,
      chatSessionId: request.snapshot.chatSessionId,
    );
    final diagnostics = loaded.diagnostics;
    if (diagnostics.isReadOnly) return diagnostics;
    final current = loaded.project;
    if (current == null) return null;
    if (current.persistenceRevision != request.snapshot.persistenceRevision) {
      throw StaleSnapshotException(
        path:
            '${ProjectRepository.projectsRoot}/${request.snapshot.id}/'
            '${ProjectRepository.documentFileName}',
        expectedRevision: request.snapshot.persistenceRevision,
        actualRevision: current.persistenceRevision,
      );
    }
    final currentTasks = {for (final task in current.tasks) task.id: task};
    for (final task in request.snapshot.tasks) {
      final currentTask = currentTasks[task.id];
      if (currentTask == null) {
        throw StaleSnapshotException(
          path: '.agent/tasks/${task.id}/task.json',
          expectedRevision: task.persistenceRevision,
          actualRevision: -1,
        );
      }
      if (currentTask.persistenceRevision != task.persistenceRevision) {
        throw StaleSnapshotException(
          path: '.agent/tasks/${task.id}/task.json',
          expectedRevision: task.persistenceRevision,
          actualRevision: currentTask.persistenceRevision,
        );
      }
    }
    return null;
  }

  Future<ProjectCommandResult> _executeOnce(
    ProjectExecutionRequest request,
  ) async {
    final readOnly = await _ensureCurrentSnapshot(request);
    if (readOnly != null) {
      return ProjectCommandResult(
        project: request.snapshot,
        stopReason: ProjectCommandStopReason.readOnly,
        persistenceDiagnostics: readOnly,
      );
    }
    final result = await executionService.execute(request);
    return ProjectCommandResult.fromRun(
      result: result,
      before: request.snapshot,
      trigger: 'execute',
    );
  }

  bool _shouldContinue(ProjectCommandResult result) {
    final project = result.project;
    return project.status == ProjectStatus.paused &&
        project.activeTaskId == null &&
        project.pendingPlanApproval == null &&
        project.openQuestions.isEmpty &&
        project.blocker == null;
  }

  Future<T> _withProjectCommand<T>(
    WorkspaceAttachment workspace,
    ProjectDocument project,
    Future<T> Function() operation,
  ) async {
    if (Zone.current[_commandZoneKey] == true) return operation();
    final key =
        '${_persistenceCoordinator.canonicalWorkspacePath(workspace.rootPath)}'
        ':${project.id}';
    if (!_busyProjects.add(key)) {
      throw ProjectBusyException(
        workspaceRoot: workspace.rootPath,
        projectId: project.id,
      );
    }
    return await runZoned(() async {
      try {
        return await operation();
      } finally {
        _busyProjects.remove(key);
      }
    }, zoneValues: {_commandZoneKey: true});
  }
}

/// A client is only needed to satisfy the legacy recovery delegate; recovery
/// itself never calls it.
class _NoopChatClient implements ChatClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Recovery does not use a chat client.');
}
