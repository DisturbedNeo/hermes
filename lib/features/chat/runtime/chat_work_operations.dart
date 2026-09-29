// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_field
part of 'chat_controller.dart';

extension _ChatWorkOperations on _ChatApplicationContext {
  Future<void> generateOrContinue({
    List<String>? tools = const [],
    bool preferActiveWork = true,
  }) async {
    if (chatStream.isStreaming || taskBusy) return;

    if (preferActiveWork && await _continueActiveWorkIfAvailable()) {
      return;
    }

    if (messageStore.isEmpty) return;

    _adoptActiveModelIfRestoreDismissed();

    var lastMessage = messageStore.last;
    if (lastMessage.role == MessageRole.assistant) {
      lastMessage = ContentNormaliser.normalise(lastMessage);
      messageStore.upsert(lastMessage);
    }

    final continuationTargetId =
        lastMessage.role == MessageRole.assistant && lastMessage.tools.isEmpty
        ? lastMessage.id
        : null;

    await _session.streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: lastMessage.role != MessageRole.assistant,
      selectedToolIds: tools ?? const [],
      anchorId: null,
      targetAssistantId: continuationTargetId,
    );
  }

  Future<bool> _continueActiveWorkIfAvailable() async {
    final project = activeProject;
    if (project != null) {
      if (project.isTerminal) return false;
      await runProject();
      return true;
    }

    final task = activeTask;
    if (task == null || task.isTerminal || task.nextRunnableStep == null) {
      return false;
    }

    await runTask();
    return true;
  }

  Future<void> cancelGeneration() async {
    await _session.cancelGeneration();
  }

  Future<void> cancelTaskRun() async {
    if (!taskBusy) return;
    final token = _commandCoordinator.activeToken;
    taskCancellationRequested = true;
    taskStatusMessage = 'Cancelling run...';
    notifyListeners();
    if (token == null) {
      await _commandCoordinator.cancel();
      return;
    }
    await _commandCoordinator.cancel();
  }

  Future<void> reloadTasks() async {
    final current = workspace;
    if (current == null || current.missing) {
      availableTasks = const [];
      availableProjects = const [];
      activeTask = null;
      activeProject = null;
      notifyListeners();
      return;
    }

    final scopeId = _taskScopeId;
    activeProject = (await _recoverProject(
      current,
      activeProject ??
          await _projectApplication.loadLatestProject(
            current,
            chatSessionId: scopeId,
          ),
    ))?.project;
    availableProjects = await _projectApplication.listProjects(
      current,
      chatSessionId: scopeId,
    );
    final activeScopeId = activeTask?.chatSessionId;
    final scopedActiveTask =
        activeTask != null &&
            (activeScopeId == null || activeScopeId == scopeId)
        ? activeTask
        : null;
    activeTask = await _taskForActiveProject(current, activeProject);
    if (activeTask == null && activeProject == null) {
      activeTask = await _recoverTaskSnapshot(
        current,
        scopedActiveTask ??
            await _taskController.loadLatestTask(
              current,
              chatSessionId: scopeId,
            ),
      );
    }
    availableTasks = await _taskController.listTasks(
      current,
      chatSessionId: scopeId,
    );
    notifyListeners();
  }

  Future<Task?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    Task? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _taskController.recoverTask(workspace: current, snapshot: snapshot);
  }

  Future<ProjectCommandResult?> _recoverProject(
    WorkspaceAttachment current,
    ProjectDocument? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _projectApplication.recover(
      ProjectRecoveryRequest(
        workspace: current,
        snapshot: snapshot,
        onTaskUpdated: (task) => activeTask = task,
      ),
    );
  }

  Future<Task?> _taskForActiveProject(
    WorkspaceAttachment current,
    ProjectDocument? project,
  ) async {
    final taskId = project?.activeTaskId;
    if (project == null || taskId == null) return null;
    return _recoverTaskSnapshot(
      current,
      await _taskController.loadTask(
        current,
        taskId,
        chatSessionId: project.chatSessionId,
        projectId: project.id,
      ),
    );
  }

  Future<void> resumeLatestTask() async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    activeTask = await _recoverTaskSnapshot(
      current,
      await _taskController.loadLatestTask(current, chatSessionId: scopeId),
    );
    await reloadTasks();
  }

  Future<void> loadTask(String taskId) async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    activeTask = await _recoverTaskSnapshot(
      current,
      await _taskController.loadTask(current, taskId, chatSessionId: scopeId),
    );
    await reloadTasks();
  }

  Future<void> resumeLatestProject() async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    final result = await _recoverProject(
      current,
      await _projectApplication.loadLatestProject(
        current,
        chatSessionId: scopeId,
      ),
    );
    activeProject = result?.project;
    activeTask = result?.activeTask;
    activeProjectPersistenceDiagnostics = result?.persistenceDiagnostics;
    await reloadTasks();
  }

  Future<void> loadProject(String projectId) async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    final result = await _recoverProject(
      current,
      await _projectApplication.loadProject(
        current,
        projectId,
        chatSessionId: scopeId,
      ),
    );
    activeProject = result?.project;
    activeTask = result?.activeTask;
    activeProjectPersistenceDiagnostics = result?.persistenceDiagnostics;
    await reloadTasks();
  }

  Future<void> runNextProjectTask() async {
    await _runProjectInternal(maxNewTasks: 1);
  }

  Future<void> runProject() async {
    await _runProjectInternal();
  }

  Future<void> runNextTaskPhase() async {
    await _runNextTaskStepInternal();
  }

  Future<void> runTask() async {
    await _runTaskInternal();
  }

  Future<void> planActiveTask({bool runAfterPlanning = false}) async {
    if (runAfterPlanning) await runTask();
  }

  // ── Task orchestration ──────────────────────────────────────────────────

  Future<void> _runTaskInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        activeTask == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      taskBusy = true;
      taskError = null;
      _beginTaskModelOutput('Task Run Model Output');
      notifyListeners();
    }
    await _refreshTaskSystemSettings();
    taskStatusMessage = 'Running task...';
    notifyListeners();

    try {
      while (true) {
        if (token.isCancelled) break;
        final snapshot = activeTask;
        if (snapshot == null) break;
        if (snapshot.nextRunnableStep == null) break;
        await _runNextTaskStepInternal(keepBusy: true);
        if (token.isCancelled) break;

        final updated = activeTask;
        if (updated == null ||
            updated.status == TaskStatus.completed ||
            updated.status == TaskStatus.blocked ||
            updated.status == TaskStatus.failed ||
            updated.status == TaskStatus.cancelled ||
            _taskNeedsInterventionBeforeContinuing(updated)) {
          break;
        }
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task run cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to run task: $e');
    } finally {
      if (!keepBusy) {
        taskBusy = false;
        _endTaskCancellationScope(token);
        taskStatusMessage = null;
        _finishTaskModelOutput();
        notifyListeners();
      }
    }
  }

  Future<void> retryTaskPhase() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeTask = await _taskController.retryCurrentStep(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> skipTaskPhase() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeTask = await _taskController.skipCurrentStep(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> stopTask() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null) {
      return;
    }

    if (taskBusy) {
      await cancelTaskRun();
      return;
    }

    activeTask = await _taskController.stopTask(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadTasks();
  }

  Future<void> answerTaskQuestion(String answer) async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeTask = await _taskController.answerOpenQuestion(
      workspace: currentWorkspace,
      snapshot: snapshot,
      answer: answer,
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> approveTaskStep() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeTask = await _taskController.approvePendingStep(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> answerProjectQuestion(String answer) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeProject = await _projectApplication.answerOpenQuestion(
      workspace: currentWorkspace,
      snapshot: snapshot,
      answer: answer,
    );
    await reloadTasks();
  }

  Future<void> stopProject() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null) {
      return;
    }

    if (taskBusy) {
      await cancelTaskRun();
      return;
    }

    activeProject = await _projectApplication.stopProject(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    activeTask = null;
    await reloadTasks();
  }

  Future<void> pauseProject() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeProject = await _projectApplication.pauseProject(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadTasks();
  }

  Future<void> retryProjectRecovery(String incidentId) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    activeProject = await _projectApplication.retryRecoveryIncident(
      workspace: currentWorkspace,
      snapshot: snapshot,
      incidentId: incidentId,
    );
    await reloadTasks();
  }

  Future<void> approveProjectPlanRevision() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy ||
        snapshot.pendingPlanApproval == null) {
      return;
    }
    activeProject = await _projectApplication.approvePlanRevision(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadTasks();
  }

  Future<void> rejectProjectPlanRevision() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy ||
        snapshot.pendingPlanApproval == null) {
      return;
    }
    activeProject = await _projectApplication.rejectPlanRevision(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadTasks();
  }

  Future<void> replanProject([String reason = '']) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        snapshot.activeTaskId != null ||
        snapshot.pendingPlanApproval != null ||
        taskBusy) {
      return;
    }
    activeProject = await _projectApplication.requestScopeChange(
      workspace: currentWorkspace,
      snapshot: snapshot,
      context: reason.trim().isEmpty
          ? 'User explicitly requested a roadmap revision.'
          : reason,
    );
    await reloadTasks();
    await _runProjectInternal();
  }

  Future<void> _handleSlashCommand(_SlashCommand command) async {
    switch (command.name) {
      case 'task':
        if (command.argument.trim().isEmpty) {
          _session.insertUserAndAssistant(
            command.raw,
            'Usage: `/task <request>` creates and runs a structured task.',
          );
          return;
        }
        await _startTaskFromPrompt(command.argument, runFirstPhase: true);
      case 'plan':
        if (command.argument.trim().isEmpty) {
          _session.insertUserAndAssistant(
            command.raw,
            'Usage: `/plan <request>` creates a task plan without running it.',
          );
          return;
        }
        await _startTaskFromPrompt(command.argument, runFirstPhase: false);
      case 'refine':
        await _refinePromptFromCommand(command);
      case 'continue':
        await _continueTaskFromCommand(command.raw);
      case 'project':
        if (command.argument.trim().isEmpty) {
          _session.insertUserAndAssistant(
            command.raw,
            'Usage: `/project <goal>` creates and runs a supervised project.',
          );
          return;
        }
        await _startProjectFromPrompt(command.argument, runAfterCreation: true);
      case 'continue-project':
        await _continueProjectFromCommand(command.raw);
      default:
        throw StateError('Unknown slash command: ${command.name}');
    }
  }

  Future<void> _refinePromptFromCommand(_SlashCommand command) async {
    final client = serverManager.chatClient;
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

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = 'Refining task brief...';
    _beginTaskModelOutput('Task Brief Model Output');
    notifyListeners();

    try {
      final brief = await _taskController.refineTaskBrief(
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
          text: _taskBriefMessage(brief),
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task brief refinement cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to refine task brief: $e');
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
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
    activeTask ??= await _recoverTaskSnapshot(
      currentWorkspace,
      await _taskController.loadLatestTask(
        currentWorkspace,
        chatSessionId: scopeId,
      ),
    );
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
    activeProject ??= (await _recoverProject(
      currentWorkspace,
      await _projectApplication.loadLatestProject(
        currentWorkspace,
        chatSessionId: scopeId,
      ),
    ))?.project;
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
    final client = serverManager.chatClient;
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
          await _projectApplication.loadLatestProject(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ))?.project;
    if (existingProject != null && !existingProject.isTerminal) {
      activeProject = await _projectApplication.addUserContext(
        workspace: currentWorkspace,
        snapshot: existingProject,
        text: prompt,
      );
      activeTask = null;
      await reloadTasks();
      _insertTaskAssistantMessage(_projectStatusMessage(activeProject!));
      if (runAfterCreation) {
        await _runProjectInternal();
      }
      return;
    }

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = runAfterCreation
        ? 'Creating project and preparing first task...'
        : 'Creating project...';
    _beginTaskModelOutput('Project Creation Model Output');
    notifyListeners();

    try {
      final project = await _projectApplication.createProject(
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
      activeProject = project;
      activeTask = null;
      await reloadTasks();
      _insertTaskAssistantMessage(_projectCreatedMessage(project));

      if (runAfterCreation) {
        activeProject = project;
        await _runProjectInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project creation cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to create project: $e');
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
    }
  }

  Future<void> _runProjectInternal({
    bool keepBusy = false,
    int? maxNewTasks,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
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
      taskBusy = true;
      taskError = null;
      _beginTaskModelOutput('Project Run Model Output');
      notifyListeners();
    }
    final settings = await _refreshTaskSystemSettings();
    taskStatusMessage = 'Running project...';
    notifyListeners();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final result = await _projectApplication.executeUntilStop(
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
            taskStatusMessage = status;
            notifyListeners();
          },
          onModelOutput: _handleTaskModelOutput,
          onTaskUpdated: (task) {
            activeTask = task;
            notifyListeners();
          },
          cancellationToken: token,
        ),
        boundedRun: maxNewTasks != null,
      );
      activeProject = result.project;
      activeTask = result.activeTask;
      activeProjectPersistenceDiagnostics = result.persistenceDiagnostics;
      notifyListeners();
      await reloadTasks();
      _insertTaskAssistantMessage(_projectStatusMessage(activeProject!));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project run cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to run project: $e');
    } finally {
      if (!keepBusy) {
        taskBusy = false;
        _endTaskCancellationScope(token);
        taskStatusMessage = null;
        _finishTaskModelOutput();
        notifyListeners();
      }
    }
  }

  Future<void> _runNextTaskStepInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
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
      taskBusy = true;
      taskError = null;
      _beginTaskModelOutput('Task Step Model Output');
      notifyListeners();
    }
    taskStatusMessage = 'Running step ${nextStep.id}: ${nextStep.title}';
    notifyListeners();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final updated = await _taskController.runNextStep(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
        requirePhaseApproval: taskSystemSettings.requireApprovalBeforeFileEdits,
        questionAutonomy: taskSystemSettings.questionAutonomy,
        compactionSettings: compactionSettings,
        contextLimitTokens: _diagnosticsContextLimit,
        onCompactionStatus: (status) {
          taskStatusMessage = status;
          notifyListeners();
        },
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      activeTask = updated;
      await reloadTasks();
      _insertTaskAssistantMessage(_stepFinishedMessage(updated));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task step cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to run task step: $e');
    } finally {
      if (!keepBusy) {
        taskBusy = false;
        _endTaskCancellationScope(token);
        taskStatusMessage = null;
        _finishTaskModelOutput();
        notifyListeners();
      }
    }
  }

  // ── Task creation (shared by send() in task/project mode and slash commands) ──

  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
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

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = runFirstPhase
        ? 'Creating task plan and preparing first phase...'
        : 'Creating task plan...';
    _beginTaskModelOutput('Task Creation Model Output');
    notifyListeners();

    try {
      final scopeId = await _ensureTaskScopeId();
      final snapshot = await _taskController.createTask(
        client: client,
        workspace: currentWorkspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        chatSessionId: scopeId,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      activeTask = snapshot;
      await reloadTasks();
      _insertTaskAssistantMessage(_taskCreatedMessage(snapshot));

      if (runFirstPhase) {
        activeTask = snapshot;
        await _runTaskInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task creation cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to create task: $e');
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
    }
  }

  // ── Business operations delegated to other services ─────────────────────

  Future<void> replanRemainingTask() async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = 'Replanning unfinished work...';
    _beginTaskModelOutput('Replan Model Output');
    notifyListeners();
    try {
      activeTask = await _taskController.replanUnfinished(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Unfinished work replanned for **${activeTask!.title}**. Next step: `${activeTask!.currentStepId ?? 'none'}`.',
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Replan cancelled.');
    } catch (e) {
      taskError = e;
      rethrow;
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
    }
  }

  Future<void> updateTaskTaskBrief(String rawJson) async {
    await updateTaskPlan(rawJson);
  }

  Future<void> updateTaskSpec(String rawJson) async {
    await updateTaskPlan(rawJson);
  }

  Future<void> updateTaskPlan(String rawJson) async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    taskBusy = true;
    taskError = null;
    taskStatusMessage = 'Updating task plan...';
    notifyListeners();
    try {
      activeTask = await _taskController.updateTaskPlan(
        workspace: currentWorkspace,
        snapshot: snapshot,
        rawJson: rawJson,
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Task plan updated for **${activeTask!.title}**.',
      );
    } catch (e) {
      taskError = e;
      rethrow;
    } finally {
      taskBusy = false;
      taskStatusMessage = null;
      notifyListeners();
    }
  }

  Future<void> updateProjectPlan(String rawJson) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    taskBusy = true;
    taskError = null;
    taskStatusMessage = 'Updating project...';
    notifyListeners();
    try {
      activeProject = await _projectApplication.updateProject(
        workspace: currentWorkspace,
        snapshot: snapshot,
        rawJson: rawJson,
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Project updated for **${activeProject!.title}**.',
      );
    } catch (e) {
      taskError = e;
      rethrow;
    } finally {
      taskBusy = false;
      taskStatusMessage = null;
      notifyListeners();
    }
  }

  Future<String> readTaskArtifact(String artifactPath) async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      throw StateError('No active workspace is attached.');
    }
    return _taskController.readArtifact(
      workspace: currentWorkspace,
      artifactPath: artifactPath,
    );
  }

  // ── Session state management ────────────────────────────────────────────

  void _handleMessagesChanged() {
    _state = _state.copyWith(
      messages: messageStore.messages,
      historyRevision: _historyRevision,
    );
    _requestContextEstimateUpdate();
    if (_disposed || _loadingSnapshot) return;
    _markPersistableChange();
  }
}
