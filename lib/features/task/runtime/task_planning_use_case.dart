part of 'task_execution_coordinator.dart';

/// Owns task creation and plan-edit application at the task boundary.
class TaskPlanningUseCase {
  TaskPlanningUseCase(this._context);

  final TaskUseCaseContext _context;

  TaskPersistenceStore get _persistenceStore => _context.persistenceStore;
  TaskPlanningCoordinatorPort get _planningCoordinator =>
      _context.planningCoordinator;
  JsonEncoder get _encoder => _context.encoder;
  TaskToolExecutionPort get _toolExecution => _context.toolExecution;
  TaskExecutionPolicy get _executionPolicy => const TaskExecutionPolicy();

  Future<Task> createTask({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    String? projectId,
    String? canonicalTaskId,
    TaskPlanningContext? planningContext,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final taskId = canonicalTaskId ?? _context.newTaskId(userPrompt);
    final metadata = await _context.collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );

    Task task;
    var planningMetrics = PlanningMetrics(planningStartedAt: now);
    try {
      final incremental = await _context.completeTaskPlanWithCommands(
        client: client,
        baseSystemPrompt: baseSystemPrompt,
        workspace: workspace,
        taskId: taskId,
        userPrompt: userPrompt,
        metadata: metadata,
        planningContext: planningContext,
        now: now,
        chatSessionId: chatSessionId,
        projectId: projectId,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      planningMetrics = planningMetrics.add(incremental.planningMetrics);
      final plannedTask = incremental.task;
      if (plannedTask != null) {
        task = plannedTask;
      } else {
        task = planningContext == null
            ? _context.fallbackTask(
                taskId: taskId,
                userPrompt: userPrompt,
                chatSessionId: chatSessionId,
                projectId: projectId,
                now: now,
              )
            : _context.fallbackProjectBoundedTask(
                taskId: taskId,
                userPrompt: userPrompt,
                chatSessionId: chatSessionId,
                projectId: projectId,
                planningContext: planningContext,
                now: now,
              );
        task = task.copyWith(
          planningError:
              incremental.planningError ??
              'Task planner did not commit an executable plan; safe fallback used.',
        );
      }
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (error) {
      task = planningContext == null
          ? _context.fallbackTask(
              taskId: taskId,
              userPrompt: userPrompt,
              chatSessionId: chatSessionId,
              projectId: projectId,
              now: now,
            )
          : _context.fallbackProjectBoundedTask(
              taskId: taskId,
              userPrompt: userPrompt,
              chatSessionId: chatSessionId,
              projectId: projectId,
              planningContext: planningContext,
              now: now,
            );
      task = task.copyWith(
        planningError: 'Task planning failed; safe fallback used: $error',
      );
    }

    final firstExecutableAt = task.currentStepId == null
        ? null
        : DateTime.now();
    planningMetrics = planningMetrics.copyWith(
      timeToFirstExecutableMs: firstExecutableAt == null
          ? null
          : DateTime.now().difference(now).inMilliseconds,
    );
    task = task.copyWith(
      planningMetrics: task.planningMetrics.add(planningMetrics),
    );
    final existing = await _persistenceStore.loadSnapshot(
      workspace.rootPath,
      task.id,
      includeHistory: false,
    );
    if (existing != null) {
      task = task.copyWith(persistenceRevision: existing.revision);
    }
    return _context.persistTask(workspace.rootPath, task);
  }

  Future<Task> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  }) async {
    final now = DateTime.now();
    final taskId = canonicalTaskId ?? _context.newTaskId(userPrompt);
    final task = _context.fallbackProjectBoundedTask(
      taskId: taskId,
      userPrompt: userPrompt,
      chatSessionId: chatSessionId,
      projectId: projectId,
      planningContext: planningContext,
      now: now,
    );
    final existing = await _persistenceStore.loadSnapshot(
      workspace.rootPath,
      task.id,
      includeHistory: false,
    );
    final prepared = existing == null
        ? task
        : task.copyWith(persistenceRevision: existing.revision);
    return _context.persistTask(workspace.rootPath, prepared);
  }

  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required TaskPlanUpdateCommand command,
  }) async {
    final parsed = ModelJson.decode<Task>(command.toWire());
    final now = DateTime.now();
    final normalised = _context.normaliseEditedTask(
      parsed.copyWith(
        id: snapshot.id,
        persistenceRevision: snapshot.persistenceRevision,
        chatSessionId: snapshot.chatSessionId,
        projectId: snapshot.projectId,
      ),
      snapshot,
      now,
    );
    return _context.persistTask(workspace.rootPath, normalised);
  }
}
