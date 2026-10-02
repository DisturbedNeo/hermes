part of 'chat_session_orchestrator.dart';

extension ChatSessionCommands on ChatWorkUseCase {
  Future<void> _refinePromptFromCommand(ChatSlashCommand command) async {
    final client = serverManager.completionProvider;
    if (client == null) return;

    final prompt = command.argument.trim();
    if (prompt.isEmpty) {
      _session.insertUserAndAssistant(
        command.raw,
        'Usage: `/refine <request>` creates a Task Brief without planning or running a task.',
      );
      return;
    }
    if (!await _taskSystemEnabled()) {
      _session.insertUserAndAssistant(
        command.raw,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: command.raw,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage('Refining task brief...');
    _beginTaskModelOutput('Task Brief Model Output');
    emitChange();

    try {
      final brief = await _taskPlanning.refineTaskBrief(
        client: client,
        workspace: workspace?.missing == true ? null : workspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.refine,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: _presentationMessages.taskBrief(brief),
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task brief refinement cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to refine task brief: $e');
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }

  Future<void> _continueTaskFromCommand(String rawCommand) async {
    if (!await _taskSystemEnabled()) {
      _session.insertUserAndAssistant(
        rawCommand,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: rawCommand,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              '`/continue` needs an attached workspace with a saved task under `.agent/tasks`.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final scopeId = _taskScopeId;
    if (activeTask == null) {
      dispatchActiveTask(
        await _recoverTaskSnapshot(
          currentWorkspace,
          await _taskQueries.loadLatestTask(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ),
      );
    }
    await reloadTasks();
    if (activeTask == null) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'No saved task was found for this chat.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    await _runTaskInternal();
  }

  Future<void> _continueProjectFromCommand(String rawCommand) async {
    if (!await _taskSystemEnabled()) {
      _session.insertUserAndAssistant(
        rawCommand,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: rawCommand,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              '`/continue-project` needs an attached workspace with a saved project under `.agent/projects`.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final scopeId = _taskScopeId;
    if (activeProject == null) {
      dispatchActiveProject(
        (await _recoverProject(
          currentWorkspace,
          await _projectQueries.loadLatestProject(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ))?.project,
      );
    }
    await reloadTasks();
    if (activeProject == null) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'No saved project was found for this chat.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    await _runProjectInternal();
  }

  Future<void> _startProjectFromPrompt(
    String prompt, {
    required bool runAfterCreation,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    if (client == null) return;
    final settings = await _refreshTaskSystemSettings();
    if (!settings.enabled) {
      _session.insertUserAndAssistant(
        prompt,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: prompt,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              'Project mode needs an attached workspace so it can persist `.agent/projects` and `.agent/tasks` artifacts. Attach a workspace and try again.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final scopeId = await _ensureTaskScopeId();
    final existingProject =
        activeProject ??
        (await _recoverProject(
          currentWorkspace,
          await _projectQueries.loadLatestProject(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ))?.project;
    if (existingProject != null && !existingProject.isTerminal) {
      dispatchActiveProject(
        await _projectPlanning.addUserContext(
          workspace: currentWorkspace,
          snapshot: existingProject,
          text: prompt,
        ),
      );
      dispatchActiveTask(null);
      await reloadTasks();
      _insertTaskAssistantMessage(
        _presentationMessages.projectStatus(
          activeProject!,
          activeTask: activeTask,
        ),
      );
      if (runAfterCreation) {
        await _runProjectInternal();
      }
      return;
    }

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage(
      runAfterCreation
          ? 'Creating project and preparing first task...'
          : 'Creating project...',
    );
    _beginTaskModelOutput('Project Creation Model Output');
    emitChange();

    try {
      final project = await _projectPlanning.createProject(
        workspace: currentWorkspace,
        userPrompt: prompt,
        chatSessionId: scopeId,
        client: client,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        maxIterations: settings.maxProjectIterations,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
        questionAutonomy: settings.questionAutonomy,
      );
      dispatchActiveProject(project);
      dispatchActiveTask(null);
      await reloadTasks();
      _insertTaskAssistantMessage(
        _presentationMessages.projectCreated(project),
      );

      if (runAfterCreation) {
        dispatchActiveProject(project);
        await _runProjectInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project creation cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to create project: $e');
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }

  Future<void> _runProjectInternal({
    bool keepBusy = false,
    int? maxNewTasks,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      dispatchTaskBusy(true);
      dispatchTaskError(null);
      _beginTaskModelOutput('Project Run Model Output');
      emitChange();
    }
    final settings = await _refreshTaskSystemSettings();
    dispatchTaskStatusMessage('Running project...');
    emitChange();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final result = await _projectExecution.executeUntilStop(
        ProjectExecutionRequest(
          client: client,
          workspace: currentWorkspace,
          snapshot: snapshot,
          baseSystemPrompt: _buildProjectSystemPrompt(snapshot),
          maxNewTasks: maxNewTasks ?? settings.maxProjectTasksPerRun,
          maxIterations: settings.maxProjectIterations,
          requirePhaseApproval: settings.requireApprovalBeforeFileEdits,
          questionAutonomy: settings.questionAutonomy,
          planApprovalPolicy: settings.planApprovalPolicy,
          compactionSettings: compactionSettings,
          contextLimitTokens: _diagnosticsContextLimit,
          onCompactionStatus: (status) {
            dispatchTaskStatusMessage(status);
            emitChange();
          },
          onModelOutput: _handleTaskModelOutput,
          onTaskUpdated: (task) {
            dispatchActiveTask(task);
            emitChange();
          },
          cancellationToken: token,
        ),
        boundedRun: maxNewTasks != null,
      );
      dispatchActiveProject(result.project);
      dispatchActiveTask(result.activeTask);
      dispatchActiveProjectPersistenceDiagnostics(
        result.persistenceDiagnostics,
      );
      emitChange();
      await reloadTasks();
      _insertTaskAssistantMessage(
        _presentationMessages.projectStatus(
          activeProject!,
          activeTask: activeTask,
        ),
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project run cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to run project: $e');
    } finally {
      if (!keepBusy) {
        dispatchTaskBusy(false);
        _endTaskCancellationScope(token);
        dispatchTaskStatusMessage(null);
        _finishTaskModelOutput();
        emitChange();
      }
    }
  }

  Future<void> _runNextTaskStepInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final nextStep = snapshot.nextRunnableStep;
    if (nextStep == null) {
      _insertTaskAssistantMessage(
        'Task `${snapshot.title}` has no pending steps.',
      );
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      dispatchTaskBusy(true);
      dispatchTaskError(null);
      _beginTaskModelOutput('Task Step Model Output');
      emitChange();
    }
    dispatchTaskStatusMessage('Running step ${nextStep.id}: ${nextStep.title}');
    emitChange();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final updated = await _taskExecution.runNextStep(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
        requirePhaseApproval: taskSystemSettings.requireApprovalBeforeFileEdits,
        questionAutonomy: taskSystemSettings.questionAutonomy,
        compactionSettings: compactionSettings,
        contextLimitTokens: _diagnosticsContextLimit,
        onCompactionStatus: (status) {
          dispatchTaskStatusMessage(status);
          emitChange();
        },
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      dispatchActiveTask(updated);
      await reloadTasks();
      _insertTaskAssistantMessage(_presentationMessages.stepFinished(updated));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task step cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to run task step: $e');
    } finally {
      if (!keepBusy) {
        dispatchTaskBusy(false);
        _endTaskCancellationScope(token);
        dispatchTaskStatusMessage(null);
        _finishTaskModelOutput();
        emitChange();
      }
    }
  }

  // ── Task creation (shared by send() in task/project mode and slash commands) ──

  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    if (client == null) return;
    final settings = await _refreshTaskSystemSettings();
    if (!settings.enabled) {
      _session.insertUserAndAssistant(
        prompt,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: prompt,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              'Task mode needs an attached workspace so it can persist `.agent/tasks` artifacts. Attach a workspace and try again.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage(
      runFirstPhase
          ? 'Creating task plan and preparing first phase...'
          : 'Creating task plan...',
    );
    _beginTaskModelOutput('Task Creation Model Output');
    emitChange();

    try {
      final scopeId = await _ensureTaskScopeId();
      final snapshot = await _taskPlanning.createTask(
        client: client,
        workspace: currentWorkspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        chatSessionId: scopeId,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      dispatchActiveTask(snapshot);
      await reloadTasks();
      _insertTaskAssistantMessage(_presentationMessages.taskCreated(snapshot));

      if (runFirstPhase) {
        dispatchActiveTask(snapshot);
        await _runTaskInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task creation cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to create task: $e');
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }
}
