part of 'chat_session_orchestrator.dart';

/// Owns workspace, conversation-generation, and task/project work commands.
///
/// State reducers and low-level model/task helpers stay on the host runtime;
/// this class owns the user-facing work flows that compose them.
class ChatWorkUseCase {
  ChatWorkUseCase(this._host);

  final ChatUseCaseContext _host;

  ModelServerPort get serverManager => _host.serverManager;
  MessageStore get messageStore => _host.messageStore;
  ChatStream<ChatToken> get chatStream => _host.chatStream;
  WorkspaceAttachment? get workspace => _host.workspace;
  ProjectAggregate? get activeProject => _host.activeProject;
  Task? get activeTask => _host.activeTask;
  TaskSystemSettings get taskSystemSettings => _host.taskSystemSettings;
  bool get taskBusy => _host.taskBusy;
  ExecutionMode get executionMode => _host.executionMode;
  String? get currentChatId => _host.currentChatId;
  SavedChat? get currentSavedChat => _host.currentSavedChat;
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _host.currentModelSnapshot;
  int? get _diagnosticsContextLimit => _host.sessionDiagnosticsContextLimit;
  int get _currentPersistenceRevision => _host._currentPersistenceRevision;
  int get _persistedRevision => _host._persistedRevision;
  String get _taskScopeId => _host._taskScopeId;
  ChatPresentationMessageBuilder get _presentationMessages =>
      _host._presentationMessages;
  ChatPanelProtocolAdapter get _panelProtocol => _host._panelProtocol;
  ChatSessionManager get _session => _host._session;
  TaskQueryPort get _taskQueries => _host._taskQueries;
  TaskPlanningPort get _taskPlanning => _host._taskPlanning;
  TaskExecutionPort get _taskExecution => _host._taskExecution;
  TaskRecoveryPort get _taskRecovery => _host._taskRecovery;
  ProjectQueryPort get _projectQueries => _host._projectQueries;
  ProjectPlanningPort get _projectPlanning => _host._projectPlanning;
  ProjectExecutionPort get _projectExecution => _host._projectExecution;
  ChatRuntimePreferencesPort get _preferencesService =>
      _host._preferencesService;

  void emitChange() => _host.emitChange();
  void dispatchTaskBusy(bool value) => _host.dispatchTaskBusy(value);
  void dispatchTaskError(Object? value) => _host.dispatchTaskError(value);
  void dispatchTaskStatusMessage(String? value) =>
      _host.dispatchTaskStatusMessage(value);
  void dispatchActiveTask(Task? value) => _host.dispatchActiveTask(value);
  void dispatchActiveProject(ProjectAggregate? value) =>
      _host.dispatchActiveProject(value);
  void dispatchActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) => _host.dispatchActiveProjectPersistenceDiagnostics(value);
  void dispatchTaskCancellationRequested(bool value) =>
      _host.dispatchTaskCancellationRequested(value);

  Future<bool> _taskSystemEnabled() => _host._taskSystemEnabled();
  Future<String> _ensureTaskScopeId() => _host._ensureTaskScopeId();
  Future<TaskSystemSettings> _refreshTaskSystemSettings() =>
      _host._refreshTaskSystemSettings();
  CancellationToken _beginTaskCancellationScope({bool reuseExisting = false}) =>
      _host.beginTaskCancellationScope(reuseExisting: reuseExisting);
  void _endTaskCancellationScope(CancellationToken token) =>
      _host._endTaskCancellationScope(token);
  void _beginTaskModelOutput(String title) =>
      _host._beginTaskModelOutput(title);
  void _finishTaskModelOutput() => _host._finishTaskModelOutput();
  void _handleTaskModelOutput(TaskModelOutputEvent event) =>
      _host._handleTaskModelOutput(event);
  void _insertTaskAssistantMessage(String text) =>
      _host._insertTaskAssistantMessage(text);
  void _insertTaskErrorBubble(String text) =>
      _host._insertTaskErrorBubble(text);
  void _adoptActiveModelIfRestoreDismissed() =>
      _host._adoptActiveModelIfRestoreDismissed();
  String _buildSystemPrompt({String? currentUserRequest}) =>
      _host.buildSystemPromptInternal(currentUserRequest: currentUserRequest);
  String _buildTaskSystemPrompt(Task snapshot) =>
      _host._buildTaskSystemPrompt(snapshot);
  String _buildProjectSystemPrompt(ProjectAggregate snapshot) =>
      _host._buildProjectSystemPrompt(snapshot);
  Future<void> attachWorkspace(String folderPath) async {
    if (_host.chatStream.isStreaming) return;
    final result = await _host._workspaceLifecycle.attach(
      folderPath: folderPath,
      previousWorkspace: _host.workspace,
      previousChatId: _host.currentChatId,
      previousScopeId: _host._chatSessionScopeId,
    );
    _host.dispatchWorkspace(result.workspace);
    _host._syncSystemPrompt();
    _host.dispatchActiveProject(result.activeProject);
    _host.dispatchAvailableProjects(result.availableProjects);
    _host.dispatchActiveTask(result.activeTask);
    _host.dispatchAvailableTasks(result.availableTasks);
    _host._markWorkspaceChanged();
  }

  Future<void> detachWorkspace() async {
    if (_host.chatStream.isStreaming) return;
    await _host._deleteTransientTasksForCurrentScope();
    await _host._deleteTransientProjectsForCurrentScope();
    _host.dispatchWorkspace(null);
    _host.dispatchActiveProject(null);
    _host.dispatchAvailableProjects(const []);
    _host.dispatchActiveTask(null);
    _host.dispatchAvailableTasks(const []);
    _host._syncSystemPrompt();
    _host._markWorkspaceChanged();
  }

  Future<void> send(String text, {List<String>? tools = const []}) async {
    if (_host.chatStream.isStreaming || _host.taskBusy) return;

    final t = text.trim();
    if (t.isEmpty) return;

    final command = _host._commandDispatcher.parse(t);
    if (command != null) {
      await _host._commandDispatcher.dispatch(
        command,
        insertUserAndAssistant: _host._session.insertUserAndAssistant,
        startTask: (prompt, {required runFirstPhase}) =>
            _host._startTaskFromPrompt(prompt, runFirstPhase: runFirstPhase),
        startProject: (prompt, {required runAfterCreation}) =>
            _host._startProjectFromPrompt(
              prompt,
              runAfterCreation: runAfterCreation,
            ),
        refine: _host._refinePromptFromCommand,
        continueTask: _host._continueTaskFromCommand,
        continueProject: _host._continueProjectFromCommand,
      );
      return;
    }

    if (_host.executionMode == ExecutionMode.task) {
      final settings = await _host._refreshTaskSystemSettings();
      await _host._startTaskFromPrompt(
        t,
        runFirstPhase: !settings.requireApprovalBeforeExecution,
      );
      return;
    }

    if (_host.executionMode == ExecutionMode.project) {
      final settings = await _host._refreshTaskSystemSettings();
      await _host._startProjectFromPrompt(
        t,
        runAfterCreation: !settings.requireApprovalBeforeExecution,
      );
      return;
    }

    _host._adoptActiveModelIfRestoreDismissed();
    _host.messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: t,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );
    await _host._session.streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: true,
      selectedToolIds: tools ?? const [],
      anchorId: null,
    );
  }

  Future<void> generateOrContinue({
    List<String>? tools = const [],
    bool preferActiveWork = true,
  }) async {
    if (_host.chatStream.isStreaming || _host.taskBusy) return;
    if (preferActiveWork && await _continueActiveWorkIfAvailable()) return;
    if (_host.messageStore.isEmpty) return;

    _host._adoptActiveModelIfRestoreDismissed();
    var lastMessage = _host.messageStore.last;
    if (lastMessage.role == MessageRole.assistant) {
      lastMessage = ContentNormaliser.normalise(lastMessage);
      _host.messageStore.upsert(lastMessage);
    }
    final continuationTargetId =
        lastMessage.role == MessageRole.assistant && lastMessage.tools.isEmpty
        ? lastMessage.id
        : null;
    await _host._session.streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: lastMessage.role != MessageRole.assistant,
      selectedToolIds: tools ?? const [],
      anchorId: null,
      targetAssistantId: continuationTargetId,
    );
  }

  Future<bool> _continueActiveWorkIfAvailable() async {
    final project = _host.activeProject;
    if (project != null) {
      if (project.isTerminal) return false;
      await runProject();
      return true;
    }
    final task = _host.activeTask;
    if (task == null || task.isTerminal || task.nextRunnableStep == null) {
      return false;
    }
    await runTask();
    return true;
  }

  Future<void> cancelGeneration() => _host._session.cancelGeneration();

  Future<void> cancelTaskRun() async {
    if (!_host.taskBusy) return;
    final token = _host._commandCoordinator.activeToken;
    _host.dispatchTaskCancellationRequested(true);
    _host.dispatchTaskStatusMessage('Cancelling run...');
    _host.emitChange();
    if (token == null) {
      await _host._commandCoordinator.cancel();
      return;
    }
    await _host._commandCoordinator.cancel();
  }

  Future<void> reloadTasks() async {
    final current = _host.workspace;
    if (current == null || current.missing) {
      _host.dispatchAvailableTasks(const []);
      _host.dispatchAvailableProjects(const []);
      _host.dispatchActiveTask(null);
      _host.dispatchActiveProject(null);
      _host.emitChange();
      return;
    }

    final scopeId = _host._taskScopeId;
    _host.dispatchActiveProject(
      (await _host._recoverProject(
        current,
        _host.activeProject ??
            await _host._projectQueries.loadLatestProject(
              current,
              chatSessionId: scopeId,
            ),
      ))?.project,
    );
    _host.dispatchAvailableProjects(
      await _host._projectQueries.listProjects(current, chatSessionId: scopeId),
    );
    final activeScopeId = _host.activeTask?.chatSessionId;
    final scopedActiveTask =
        _host.activeTask != null &&
            (activeScopeId == null || activeScopeId == scopeId)
        ? _host.activeTask
        : null;
    _host.dispatchActiveTask(
      await _host._taskForActiveProject(current, _host.activeProject),
    );
    if (_host.activeTask == null && _host.activeProject == null) {
      _host.dispatchActiveTask(
        await _host._recoverTaskSnapshot(
          current,
          scopedActiveTask ??
              await _host._taskQueries.loadLatestTask(
                current,
                chatSessionId: scopeId,
              ),
        ),
      );
    }
    _host.dispatchAvailableTasks(
      await _host._taskQueries.listTasks(current, chatSessionId: scopeId),
    );
    _host.emitChange();
  }

  Future<void> resumeLatestTask() async {
    final current = _host.workspace;
    final scopeId = _host._taskScopeId;
    if (current == null || current.missing || _host.taskBusy) return;
    _host.dispatchActiveTask(
      await _host._recoverTaskSnapshot(
        current,
        await _host._taskQueries.loadLatestTask(
          current,
          chatSessionId: scopeId,
        ),
      ),
    );
    await reloadTasks();
  }

  Future<void> loadTask(String taskId) async {
    final current = _host.workspace;
    final scopeId = _host._taskScopeId;
    if (current == null || current.missing || _host.taskBusy) return;
    _host.dispatchActiveTask(
      await _host._recoverTaskSnapshot(
        current,
        await _host._taskQueries.loadTask(
          current,
          taskId,
          chatSessionId: scopeId,
        ),
      ),
    );
    await reloadTasks();
  }

  Future<void> resumeLatestProject() async {
    final current = _host.workspace;
    final scopeId = _host._taskScopeId;
    if (current == null || current.missing || _host.taskBusy) return;
    final result = await _host._recoverProject(
      current,
      await _host._projectQueries.loadLatestProject(
        current,
        chatSessionId: scopeId,
      ),
    );
    _host.dispatchActiveProject(result?.project);
    _host.dispatchActiveTask(result?.activeTask);
    _host.dispatchActiveProjectPersistenceDiagnostics(
      result?.persistenceDiagnostics,
    );
    await reloadTasks();
  }

  Future<void> loadProject(String projectId) async {
    final current = _host.workspace;
    final scopeId = _host._taskScopeId;
    if (current == null || current.missing || _host.taskBusy) return;
    final result = await _host._recoverProject(
      current,
      await _host._projectQueries.loadProject(
        current,
        projectId,
        chatSessionId: scopeId,
      ),
    );
    _host.dispatchActiveProject(result?.project);
    _host.dispatchActiveTask(result?.activeTask);
    _host.dispatchActiveProjectPersistenceDiagnostics(
      result?.persistenceDiagnostics,
    );
    await reloadTasks();
  }

  Future<void> runNextProjectTask() =>
      _host._runProjectInternal(maxNewTasks: 1);
  Future<void> runProject() => _host._runProjectInternal();
  Future<void> runNextTaskPhase() => _host.runNextTaskStepInternal();
  Future<void> runTask() => _host.runTaskInternal();

  Future<void> planActiveTask({bool runAfterPlanning = false}) async {
    if (runAfterPlanning) await runTask();
  }

  Future<void> retryTaskPhase() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveTask(
      await _host._taskCommandCoordinator.execute(
        command: const RetryTaskPhaseCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _host._clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> skipTaskPhase() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveTask(
      await _host._taskCommandCoordinator.execute(
        command: const SkipTaskPhaseCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _host._clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> stopTask() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null) {
      return;
    }
    if (_host.taskBusy) {
      await cancelTaskRun();
      return;
    }
    _host.dispatchActiveTask(
      await _host._taskCommandCoordinator.execute(
        command: const StopTaskCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> answerTaskQuestion(String answer) async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveTask(
      await _host._taskCommandCoordinator.execute(
        command: AnswerTaskQuestionCommand(answer),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _host._clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> approveTaskStep() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveTask(
      await _host._taskCommandCoordinator.execute(
        command: const ApproveTaskStepCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _host._clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> answerProjectQuestion(String answer) async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: AnswerProjectQuestionCommand(answer),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> stopProject() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null) {
      return;
    }
    if (_host.taskBusy) {
      await cancelTaskRun();
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: const StopProjectCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    _host.dispatchActiveTask(null);
    await reloadTasks();
  }

  Future<void> pauseProject() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: const PauseProjectCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> retryProjectRecovery(String incidentId) async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: RetryProjectRecoveryCommand(incidentId),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> approveProjectPlanRevision() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy ||
        snapshot.pendingPlanApproval == null) {
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: const ApproveProjectPlanCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> rejectProjectPlanRevision() async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy ||
        snapshot.pendingPlanApproval == null) {
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: const RejectProjectPlanCommand(),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> replanProject([String reason = '']) async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        snapshot.activeTaskId != null ||
        snapshot.pendingPlanApproval != null ||
        _host.taskBusy) {
      return;
    }
    _host.dispatchActiveProject(
      await _host._projectCommandCoordinator.execute(
        command: RequestProjectReplanCommand(reason),
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
    await _host._runProjectInternal();
  }
}
