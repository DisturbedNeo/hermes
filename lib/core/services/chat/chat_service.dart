import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/services/chat/chat_stream.dart';
import 'package:hermes/core/helpers/chat/compaction_manager.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/job_system_settings.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/services/job_system/job_model_output.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/job_system/job_summary.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';

class ChatService extends ChangeNotifier {
  static const String defaultSystemPromptName = 'Default';
  static const String defaultSystemPromptText = 'You are a helpful assistant.';

  final String tabId;
  final LlamaServerManager serverManager;
  final MessageStore messageStore = MessageStore();
  final ChatStream chatStream = ChatStream<ChatToken>();

  final ToolService _toolService;
  final JobService _jobService;
  final ChatLibraryService _chatLibrary;
  final WorkspaceService _workspaceService;
  final PreferencesService _preferencesService;
  final PromptAssembler _promptAssembler = const PromptAssembler();

  late final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: _buildSystemPrompt(),
    reasoning: '',
  );

  bool _disposed = false;
  bool _loadingSnapshot = false;
  bool _dirty = false;
  Timer? _autosaveTimer;
  Future<void> _saveChain = Future.value();
  String _chatSessionScopeId = uuid.v7();

  String? currentChatId;
  SavedChat? currentSavedChat;
  ModelConfigurationSnapshot? currentModelSnapshot;
  ModelConfigurationSnapshot? pendingModelRestore;
  String? pendingModelRestoreIssue;
  WorkspaceAttachment? workspace;
  SystemPromptSnapshot? currentSystemPromptSnapshot;
  ExecutionMode executionMode = ExecutionMode.chat;
  JobSnapshot? activeJob;
  List<JobSummary> availableJobs = const [];
  JobSystemSettings jobSystemSettings = const JobSystemSettings();
  bool jobBusy = false;
  String? jobStatusMessage;
  Object? jobError;
  String? jobModelOutputTitle;
  String jobModelOutputText = '';
  String jobModelOutputReasoning = '';
  bool jobModelOutputActive = false;
  String? _jobModelOutputLabel;
  String? _jobModelOutputTextSection;
  String? _jobModelOutputReasoningLabel;

  ChatService({
    String? tabId,
    required this.serverManager,
    required ToolService toolService,
    JobService? jobService,
    required ChatLibraryService chatLibrary,
    required WorkspaceService workspaceService,
    required PreferencesService preferencesService,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : tabId = tabId ?? uuid.v7(),
       _toolService = toolService,
       _jobService = jobService ?? JobService(toolService: toolService),
       _chatLibrary = chatLibrary,
       _workspaceService = workspaceService,
       _preferencesService = preferencesService {
    currentSystemPromptSnapshot = initialSystemPromptSnapshot;
    messageStore.setMessages([systemPrompt]);
    messageStore.addListener(_handleMessagesChanged);
    _preferencesService.addListener(_handlePreferencesChanged);
    unawaited(_loadJobSystemSettings());
    chatStream.onStop = serverManager.diagnostics.recordStreamEnded;
    currentModelSnapshot = _activeServerSnapshot;
  }

  bool get isDirty => _dirty;

  bool get hasMeaningfulContent => messageStore.messages.any(
    (message) =>
        message.role != MessageRole.system &&
        (message.text.trim().isNotEmpty ||
            message.reasoning.trim().isNotEmpty ||
            message.tools.isNotEmpty),
  );

  bool get isUnsavedNonEmpty => currentChatId == null && hasMeaningfulContent;

  bool get isSystemPromptLocked =>
      chatStream.isStreaming || hasMeaningfulContent || currentChatId != null;

  bool get hasActiveWorkspace =>
      workspace != null && workspace?.missing != true;

  bool get workspaceToolsEnabled => hasActiveWorkspace;

  String? get activeTaskBriefJson => activeJob == null
      ? null
      : _jobService.encodeTaskBrief(activeJob!.taskBrief);

  String? get activeJobSpecJson =>
      activeJob == null ? null : _jobService.encodeJobSpec(activeJob!.spec);

  List<String> get defaultToolIds => workspaceToolsEnabled
      ? _toolService.defaultToolIds(includeWorkspaceTools: true)
      : const [];

  String get displayTitle {
    final savedTitle = currentSavedChat?.title;
    if (savedTitle != null && savedTitle.trim().isNotEmpty) return savedTitle;

    final first = messageStore.messages
        .where((m) => m.role != MessageRole.system && m.text.trim().isNotEmpty)
        .map((m) => m.text.trim().replaceAll(RegExp(r'\s+'), ' '))
        .firstOrNull;

    if (first == null) return 'New chat';
    return first.length <= 40 ? first : '${first.substring(0, 37)}...';
  }

  ModelConfigurationSnapshot? get _activeServerSnapshot =>
      serverManager.current == null
      ? null
      : serverManager.diagnostics.modelSnapshot;

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot}) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    await _deleteTransientJobsForCurrentScope();
    _clearSavedState();
    currentSystemPromptSnapshot = systemPromptSnapshot;
    activeJob = null;
    availableJobs = const [];
    jobError = null;
    jobStatusMessage = null;
    _clearJobModelOutput(notify: false);
    currentModelSnapshot = _activeServerSnapshot;
    messageStore.setMessages([
      systemPrompt.copyWith(text: _buildSystemPrompt()),
    ]);
  }

  Future<bool> openChat(String id) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    final snapshot = await _chatLibrary.getChat(id);
    if (snapshot == null) return false;

    await _deleteTransientJobsForCurrentScope();
    _loadingSnapshot = true;
    try {
      currentChatId = snapshot.chat.id;
      _chatSessionScopeId = snapshot.chat.id;
      currentSavedChat = snapshot.chat;
      currentModelSnapshot = snapshot.chat.modelSnapshot;
      _clearJobModelOutput(notify: false);
      workspace = await _restoreWorkspace(snapshot.chat.workspace);
      if (workspace != null && workspace?.missing != true) {
        activeJob = await _recoverJobSnapshot(
          workspace!,
          await _jobService.loadLatestJob(
            workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        );
        availableJobs = await _jobService.listJobs(
          workspace!,
          chatSessionId: snapshot.chat.id,
        );
      } else {
        availableJobs = const [];
        activeJob = null;
      }
      currentSystemPromptSnapshot = snapshot.chat.systemPromptSnapshot;
      _dirty = false;
      messageStore.setMessages(_withCurrentSystemPrompt(snapshot.messages));
      await _chatLibrary.markOpened(snapshot.chat.id);
      await refreshModelRestorePrompt();
    } finally {
      _loadingSnapshot = false;
    }

    notifyListeners();
    return true;
  }

  Future<SavedChat> saveCurrentChat({String? title}) async {
    return _queueSave(title: title, force: true);
  }

  Future<void> deleteSavedChat(String chatId) async {
    final snapshot = await _chatLibrary.getChat(chatId);
    final workspaces = _workspacesForSavedChatDeletion(
      chatId,
      snapshot?.chat.workspace,
    );
    await _chatLibrary.deleteChat(chatId);
    try {
      await _deleteJobsForChatSessionInWorkspaces(chatId, workspaces);
    } finally {
      await resetIfCurrentSavedChatDeleted(chatId);
    }
  }

  Future<void> resetIfCurrentSavedChatDeleted(String chatId) async {
    if (currentChatId == chatId) {
      _clearSavedState();
      await newChat();
    }
  }

  Future<void> flushCurrentChat() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (currentChatId != null && _dirty) {
      await _queueSave(force: true);
    }
    await _saveChain;
  }

  void setCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) {
    currentModelSnapshot = snapshot;
    _updateContextEstimate();
    if (currentChatId != null) {
      _dirty = true;
      _scheduleAutosave();
    }

    if (pendingModelRestore?.matches(snapshot) ?? false) {
      pendingModelRestore = null;
      pendingModelRestoreIssue = null;
    }

    notifyListeners();
  }

  Future<void> restorePendingModel() async {
    final snapshot = pendingModelRestore;
    if (snapshot == null) return;

    if (!await File(snapshot.modelPath).exists()) {
      throw FlutterError('Saved model file not found: ${snapshot.modelPath}');
    }

    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    notifyListeners();

    await serverManager.startWithSnapshot(snapshot);
    setCurrentModelSnapshot(snapshot);
  }

  void dismissPendingModelRestore() {
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    notifyListeners();
  }

  void setSystemPromptSnapshot(SystemPromptSnapshot snapshot) {
    if (isSystemPromptLocked) {
      throw StateError('System prompt is locked for this chat');
    }

    currentSystemPromptSnapshot = snapshot;
    _syncSystemPrompt();
    notifyListeners();
  }

  @visibleForTesting
  String buildSystemPromptForTesting({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) {
    return _buildSystemPrompt(
      currentUserRequest: currentUserRequest,
      additionalModuleIds: additionalModuleIds,
    );
  }

  Future<void> refreshModelRestorePrompt() async {
    await _prepareModelRestorePrompt(currentModelSnapshot);
    notifyListeners();
  }

  void insertMessage(String text, MessageRole role) {
    if (chatStream.isStreaming) return;

    final t = text.trim();

    if (t.isEmpty) return;

    _adoptActiveModelIfRestoreDismissed();

    messageStore.upsert(
      Bubble(id: uuid.v7(), role: role, text: t, reasoning: ''),
    );
  }

  Future<void> attachWorkspace(String folderPath) async {
    if (chatStream.isStreaming) return;
    final previousWorkspace = workspace;
    final previousChatId = currentChatId;
    final previousScopeId = _chatSessionScopeId;
    final nextWorkspace = await _workspaceService.attach(folderPath);
    if (previousChatId == null &&
        previousWorkspace != null &&
        !previousWorkspace.missing &&
        previousWorkspace.rootPath != nextWorkspace.rootPath) {
      await _jobService.deleteJobsForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
    }
    workspace = nextWorkspace;
    _syncSystemPrompt();
    final scopeId = _jobScopeId;
    activeJob = await _recoverJobSnapshot(
      workspace!,
      await _jobService.loadLatestJob(workspace!, chatSessionId: scopeId),
    );
    availableJobs = await _jobService.listJobs(
      workspace!,
      chatSessionId: scopeId,
    );
    _markWorkspaceChanged();
  }

  Future<void> detachWorkspace() async {
    if (chatStream.isStreaming) return;
    await _deleteTransientJobsForCurrentScope();
    workspace = null;
    activeJob = null;
    availableJobs = const [];
    _syncSystemPrompt();
    _markWorkspaceChanged();
  }

  void setCommandExecutionApproved(bool approved) {
    final current = workspace;
    if (current == null) return;
    workspace = current.copyWith(commandExecutionApproved: approved);
    _markWorkspaceChanged();
  }

  void setExecutionMode(ExecutionMode mode) {
    if (chatStream.isStreaming || jobBusy) return;
    if (executionMode == mode) return;
    executionMode = mode;
    notifyListeners();
  }

  Future<void> send(String text, {List<String>? tools = const []}) async {
    if (chatStream.isStreaming || jobBusy) return;

    final t = text.trim();
    if (t.isEmpty) return;

    final command = _parseSlashCommand(t);
    if (command != null) {
      await _handleSlashCommand(command);
      return;
    }

    if (executionMode == ExecutionMode.plan ||
        executionMode == ExecutionMode.job) {
      await _startJobFromPrompt(
        t,
        runFirstPhase: executionMode == ExecutionMode.job,
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();

    messageStore.upsert(
      Bubble(id: uuid.v7(), role: MessageRole.user, text: t, reasoning: ''),
    );

    await _streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: true,
      selectedToolIds: tools ?? const [],
      anchorId: null,
    );
  }

  Future<void> generateOrContinue({List<String>? tools = const []}) async {
    if (chatStream.isStreaming || jobBusy || messageStore.isEmpty) return;

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

    await _streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: lastMessage.role != MessageRole.assistant,
      selectedToolIds: tools ?? const [],
      anchorId: null,
      targetAssistantId: continuationTargetId,
    );
  }

  Future<void> cancelGeneration() async {
    if (!chatStream.isStreaming) return;

    final current = messageStore.currentMessage;
    if (current != null) {
      messageStore.upsert(ContentNormaliser.normalise(current));
    }

    messageStore.clearCurrentId();
    await chatStream.stop();
  }

  Future<void> reloadJobs() async {
    final current = workspace;
    if (current == null || current.missing) {
      availableJobs = const [];
      activeJob = null;
      notifyListeners();
      return;
    }

    final scopeId = _jobScopeId;
    final activeScopeId = activeJob?.state.chatSessionId;
    final scopedActiveJob =
        activeJob != null && (activeScopeId == null || activeScopeId == scopeId)
        ? activeJob
        : null;
    activeJob = await _recoverJobSnapshot(
      current,
      scopedActiveJob ??
          await _jobService.loadLatestJob(current, chatSessionId: scopeId),
    );
    availableJobs = await _jobService.listJobs(current, chatSessionId: scopeId);
    notifyListeners();
  }

  Future<JobSnapshot?> _recoverJobSnapshot(
    WorkspaceAttachment current,
    JobSnapshot? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _jobService.recoverJob(workspace: current, snapshot: snapshot);
  }

  Future<void> resumeLatestJob() async {
    final current = workspace;
    final scopeId = _jobScopeId;
    if (current == null || current.missing || jobBusy) {
      return;
    }
    activeJob = await _recoverJobSnapshot(
      current,
      await _jobService.loadLatestJob(current, chatSessionId: scopeId),
    );
    await reloadJobs();
  }

  Future<void> loadJob(String jobId) async {
    final current = workspace;
    final scopeId = _jobScopeId;
    if (current == null || current.missing || jobBusy) {
      return;
    }
    activeJob = await _recoverJobSnapshot(
      current,
      await _jobService.loadJob(current, jobId, chatSessionId: scopeId),
    );
    await reloadJobs();
  }

  Future<void> runNextJobPhase() async {
    await _runNextJobPhaseInternal();
  }

  Future<void> runJob() async {
    if (activeJob?.spec.status == JobStatus.draft) {
      await planActiveJob(runAfterPlanning: true);
      return;
    }
    await _runJobInternal();
  }

  Future<void> planActiveJob({bool runAfterPlanning = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    final settings = await _refreshJobSystemSettings();
    if (!settings.enabled) {
      _insertJobAssistantMessage('Structured jobs are disabled in Settings.');
      return;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage = 'Creating job plan...';
    _beginJobModelOutput('Job Plan Model Output');
    notifyListeners();
    try {
      activeJob = await _jobService.planDraftJob(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildJobSystemPrompt(snapshot),
        autonomyPreference: settings.defaultAutonomy,
        maxPhaseRetries: settings.maxPhaseRetries,
        onModelOutput: _handleJobModelOutput,
      );
      await reloadJobs();
      _insertJobAssistantMessage(_jobCreatedMessage(activeJob!));
      if (runAfterPlanning) {
        await _runJobInternal(keepBusy: true);
      }
    } catch (e) {
      jobError = e;
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'Failed to create job plan: $e',
          reasoning: '',
        ),
      );
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      _finishJobModelOutput();
      notifyListeners();
    }
  }

  Future<void> _runJobInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        activeJob == null ||
        jobBusy && !keepBusy) {
      return;
    }

    if (!keepBusy) {
      jobBusy = true;
      jobError = null;
      _beginJobModelOutput('Job Run Model Output');
      notifyListeners();
    }
    await _refreshJobSystemSettings();
    jobStatusMessage = 'Running job...';
    notifyListeners();

    try {
      var phasesRun = 0;
      while (true) {
        final snapshot = activeJob;
        if (snapshot == null) break;
        final nextPhase = _nextRunnablePhase(snapshot);
        if (nextPhase == null) break;

        if (_shouldPauseBeforePhase(snapshot, nextPhase, phasesRun)) {
          activeJob = await _jobService.pauseAtCheckpoint(
            workspace: currentWorkspace,
            snapshot: snapshot,
            phase: nextPhase,
          );
          await reloadJobs();
          _insertJobAssistantMessage(
            'Job paused before checkpoint phase: **${nextPhase.title}**.',
          );
          break;
        }

        await _runNextJobPhaseInternal(keepBusy: true);
        phasesRun++;

        final updated = activeJob;
        if (updated == null ||
            updated.state.status == JobStatus.completed ||
            updated.state.status == JobStatus.blocked ||
            updated.state.status == JobStatus.failed ||
            updated.state.status == JobStatus.cancelled) {
          break;
        }

        final maxPhases = updated.spec.stopPolicy.maxTotalPhases;
        if (maxPhases != null && phasesRun >= maxPhases) {
          activeJob = await _jobService.pauseAtCheckpoint(
            workspace: currentWorkspace,
            snapshot: updated,
            phase: _nextRunnablePhase(updated) ?? updated.spec.phases.last,
          );
          await reloadJobs();
          break;
        }
      }
    } catch (e) {
      jobError = e;
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'Failed to run job: $e',
          reasoning: '',
        ),
      );
    } finally {
      if (!keepBusy) {
        jobBusy = false;
        jobStatusMessage = null;
        _finishJobModelOutput();
        notifyListeners();
      }
    }
  }

  Future<void> retryJobPhase() async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.retryCurrentPhase(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadJobs();
  }

  Future<void> skipJobPhase() async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.skipCurrentPhase(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadJobs();
  }

  Future<void> stopJob() async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.stopJob(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadJobs();
  }

  Future<void> answerJobQuestion(String questionId, String answer) async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.answerOpenQuestion(
      workspace: currentWorkspace,
      snapshot: snapshot,
      questionId: questionId,
      answer: answer,
    );
    await reloadJobs();
  }

  Future<void> dismissJobQuestion(String questionId) async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.dismissOpenQuestion(
      workspace: currentWorkspace,
      snapshot: snapshot,
      questionId: questionId,
    );
    await reloadJobs();
  }

  Future<void> dismissOptionalJobQuestions() async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.dismissOptionalQuestions(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    await reloadJobs();
  }

  Future<void> resolveFileApproval(
    String approvalId,
    Set<String> approvedHunkIds,
  ) async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    activeJob = await _jobService.resolveFileApproval(
      workspace: currentWorkspace,
      snapshot: snapshot,
      approvalId: approvalId,
      approvedHunkIds: approvedHunkIds,
    );
    await reloadJobs();
    notifyListeners();
  }

  Future<void> _handleSlashCommand(_SlashCommand command) async {
    switch (command.name) {
      case 'job':
        if (command.argument.trim().isEmpty) {
          _insertUserAndAssistant(
            command.raw,
            'Usage: `/job <request>` creates and runs a structured job.',
          );
          return;
        }
        await _startJobFromPrompt(command.argument, runFirstPhase: true);
        break;
      case 'plan':
        if (command.argument.trim().isEmpty) {
          _insertUserAndAssistant(
            command.raw,
            'Usage: `/plan <request>` creates a job plan without running it.',
          );
          return;
        }
        await _startJobFromPrompt(command.argument, runFirstPhase: false);
        break;
      case 'refine':
        await _refinePromptFromCommand(command);
        break;
      case 'continue':
        await _continueJobFromCommand(command.raw);
        break;
    }
  }

  Future<void> _refinePromptFromCommand(_SlashCommand command) async {
    final client = serverManager.chatClient;
    if (client == null) return;

    final prompt = command.argument.trim();
    if (prompt.isEmpty) {
      _insertUserAndAssistant(
        command.raw,
        'Usage: `/refine <request>` creates a Task Brief without planning or running a job.',
      );
      return;
    }
    if (!await _jobSystemEnabled()) {
      _insertUserAndAssistant(
        command.raw,
        'Structured jobs are disabled in Settings.',
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
      ),
    );

    jobBusy = true;
    jobError = null;
    jobStatusMessage = 'Refining task brief...';
    _beginJobModelOutput('Task Brief Model Output');
    notifyListeners();

    try {
      final brief = await _jobService.refineTaskBrief(
        client: client,
        workspace: workspace?.missing == true ? null : workspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.refine,
        onModelOutput: _handleJobModelOutput,
      );
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: _taskBriefMessage(brief),
          reasoning: '',
        ),
      );
    } catch (e) {
      jobError = e;
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'Failed to refine task brief: $e',
          reasoning: '',
        ),
      );
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      _finishJobModelOutput();
      notifyListeners();
    }
  }

  Future<void> _continueJobFromCommand(String rawCommand) async {
    if (!await _jobSystemEnabled()) {
      _insertUserAndAssistant(
        rawCommand,
        'Structured jobs are disabled in Settings.',
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
      ),
    );

    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              '`/continue` needs an attached workspace with a saved job under `.agent/jobs`.',
          reasoning: '',
        ),
      );
      return;
    }

    final scopeId = _jobScopeId;
    activeJob ??= await _recoverJobSnapshot(
      currentWorkspace,
      await _jobService.loadLatestJob(currentWorkspace, chatSessionId: scopeId),
    );
    await reloadJobs();
    if (activeJob == null) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'No saved job was found for this chat.',
          reasoning: '',
        ),
      );
      return;
    }

    await _runJobInternal();
  }

  Future<String> readJobArtifact(String artifactPath) async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      throw StateError('No active workspace is attached.');
    }
    return _jobService.readArtifact(
      workspace: currentWorkspace,
      artifactPath: artifactPath,
    );
  }

  Future<void> updateJobTaskBrief(String rawJson) async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage = 'Updating task brief...';
    notifyListeners();
    try {
      activeJob = await _jobService.updateTaskBrief(
        workspace: currentWorkspace,
        snapshot: snapshot,
        rawJson: rawJson,
      );
      await reloadJobs();
      _insertJobAssistantMessage(
        'Task brief updated for **${activeJob!.spec.title}**.',
      );
    } catch (e) {
      jobError = e;
      rethrow;
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      notifyListeners();
    }
  }

  Future<void> updateJobSpec(String rawJson) async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage = 'Updating job spec...';
    notifyListeners();
    try {
      activeJob = await _jobService.updateJobSpec(
        workspace: currentWorkspace,
        snapshot: snapshot,
        rawJson: rawJson,
      );
      await reloadJobs();
      _insertJobAssistantMessage(
        'Job spec updated for **${activeJob!.spec.title}**.',
      );
    } catch (e) {
      jobError = e;
      rethrow;
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      notifyListeners();
    }
  }

  Future<void> replanRemainingJob() async {
    return replanJob(ReplanScope.remainingPhases);
  }

  Future<void> replanCurrentJobPhase() async {
    return replanJob(ReplanScope.currentPhase);
  }

  Future<void> replanEntireJob() async {
    return replanJob(ReplanScope.entireJob);
  }

  Future<JobSnapshot?> proposeReplanJob(ReplanScope scope) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        jobBusy) {
      return null;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage =
        'Preparing ${scope.label.toLowerCase()} replan preview...';
    _beginJobModelOutput('${scope.label} Replan Preview Model Output');
    notifyListeners();
    try {
      return await _jobService.proposeReplanJob(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildJobSystemPrompt(snapshot),
        scope: scope,
        onModelOutput: _handleJobModelOutput,
      );
    } catch (e) {
      jobError = e;
      rethrow;
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      _finishJobModelOutput();
      notifyListeners();
    }
  }

  Future<void> applyReplanProposal(
    JobSnapshot proposal,
    ReplanScope scope,
  ) async {
    final currentWorkspace = workspace;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage = 'Applying ${scope.label.toLowerCase()} replan...';
    notifyListeners();
    try {
      activeJob = await _jobService.applyReplanProposal(
        workspace: currentWorkspace,
        current: snapshot,
        proposal: proposal,
      );
      await reloadJobs();
      _insertJobAssistantMessage(
        '${scope.label} replan approved for **${activeJob!.spec.title}**. Next phase: `${activeJob!.state.currentPhaseId ?? 'none'}`.',
      );
    } catch (e) {
      jobError = e;
      rethrow;
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      notifyListeners();
    }
  }

  Future<void> replanJob(ReplanScope scope) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        jobBusy) {
      return;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage = 'Replanning ${scope.label.toLowerCase()}...';
    _beginJobModelOutput('${scope.label} Replan Model Output');
    notifyListeners();
    try {
      activeJob = switch (scope) {
        ReplanScope.currentPhase => await _jobService.replanCurrentPhase(
          client: client,
          workspace: currentWorkspace,
          snapshot: snapshot,
          baseSystemPrompt: _buildJobSystemPrompt(snapshot),
          onModelOutput: _handleJobModelOutput,
        ),
        ReplanScope.remainingPhases => await _jobService.replanRemaining(
          client: client,
          workspace: currentWorkspace,
          snapshot: snapshot,
          baseSystemPrompt: _buildJobSystemPrompt(snapshot),
          onModelOutput: _handleJobModelOutput,
        ),
        ReplanScope.entireJob => await _jobService.replanEntireJob(
          client: client,
          workspace: currentWorkspace,
          snapshot: snapshot,
          baseSystemPrompt: _buildJobSystemPrompt(snapshot),
          onModelOutput: _handleJobModelOutput,
        ),
      };
      await reloadJobs();
      _insertJobAssistantMessage(
        '${scope.label} replanned for **${activeJob!.spec.title}**. Next phase: `${activeJob!.state.currentPhaseId ?? 'none'}`.',
      );
    } catch (e) {
      jobError = e;
      rethrow;
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      _finishJobModelOutput();
      notifyListeners();
    }
  }

  Future<void> _startJobFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    if (client == null) return;
    final settings = await _refreshJobSystemSettings();
    if (!settings.enabled) {
      _insertUserAndAssistant(
        prompt,
        'Structured jobs are disabled in Settings.',
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
      ),
    );

    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              'Job mode needs an attached workspace so it can persist `.agent/jobs` artifacts. Attach a workspace and try again.',
          reasoning: '',
        ),
      );
      return;
    }

    jobBusy = true;
    jobError = null;
    jobStatusMessage = runFirstPhase
        ? 'Creating job plan and preparing first phase...'
        : 'Creating job plan...';
    _beginJobModelOutput('Job Creation Model Output');
    notifyListeners();

    try {
      final scopeId = await _ensureJobScopeId();
      final snapshot = await _jobService.createJob(
        client: client,
        workspace: currentWorkspace,
        userPrompt: prompt,
        selectedMode: runFirstPhase ? ExecutionMode.job : ExecutionMode.plan,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        chatSessionId: scopeId,
        autonomyPreference: settings.defaultAutonomy,
        maxPhaseRetries: settings.maxPhaseRetries,
        onModelOutput: _handleJobModelOutput,
      );
      activeJob = snapshot;
      await reloadJobs();
      _insertJobAssistantMessage(_jobCreatedMessage(snapshot));

      if (runFirstPhase) {
        activeJob = snapshot;
        await _runJobInternal(keepBusy: true);
      }
    } catch (e) {
      jobError = e;
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'Failed to create job: $e',
          reasoning: '',
        ),
      );
    } finally {
      jobBusy = false;
      jobStatusMessage = null;
      _finishJobModelOutput();
      notifyListeners();
    }
  }

  Future<void> _runNextJobPhaseInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    final snapshot = activeJob;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        jobBusy && !keepBusy) {
      return;
    }

    final nextPhase = snapshot.spec.phases
        .where(
          (phase) =>
              phase.status == PhaseStatus.pending ||
              phase.status == PhaseStatus.failed ||
              phase.status == PhaseStatus.blocked,
        )
        .firstOrNull;
    if (nextPhase == null) {
      _insertJobAssistantMessage(
        'Job `${snapshot.spec.title}` has no pending phases.',
      );
      return;
    }

    if (!keepBusy) {
      jobBusy = true;
      jobError = null;
      _beginJobModelOutput('Job Phase Model Output');
      notifyListeners();
    }
    jobStatusMessage = 'Running phase ${nextPhase.id}: ${nextPhase.title}';
    notifyListeners();

    try {
      final updated = await _jobService.runNextPhase(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildJobSystemPrompt(snapshot, phase: nextPhase),
        requireFileEditApproval:
            jobSystemSettings.requireApprovalBeforeFileEdits,
        onModelOutput: _handleJobModelOutput,
      );
      activeJob = updated;
      await reloadJobs();
      _insertJobAssistantMessage(_phaseFinishedMessage(updated));
    } catch (e) {
      jobError = e;
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'Failed to run job phase: $e',
          reasoning: '',
        ),
      );
    } finally {
      if (!keepBusy) {
        jobBusy = false;
        jobStatusMessage = null;
        _finishJobModelOutput();
        notifyListeners();
      }
    }
  }

  JobPhase? _nextRunnablePhase(JobSnapshot snapshot) {
    return snapshot.spec.phases
        .where(
          (phase) =>
              phase.status == PhaseStatus.pending ||
              phase.status == PhaseStatus.failed ||
              phase.status == PhaseStatus.blocked,
        )
        .firstOrNull;
  }

  bool _shouldPauseBeforePhase(
    JobSnapshot snapshot,
    JobPhase phase,
    int phasesRun,
  ) {
    if (snapshot.state.openQuestions.any(
      (question) =>
          question.required && question.status == OpenQuestionStatus.open,
    )) {
      return false;
    }

    final terminalPolicy = _effectiveTerminalPolicy(snapshot.spec, phase);
    final terminalNeedsApproval =
        jobSystemSettings.requireApprovalBeforeTerminal &&
        (terminalPolicy == TerminalPolicy.workspaceMutating ||
            terminalPolicy == TerminalPolicy.unrestrictedWorkspace);
    final fileEditsNeedApproval =
        jobSystemSettings.requireApprovalBeforeFileEdits &&
        _phaseUsesMutatingTools(phase);

    return switch (snapshot.spec.autonomy) {
      AutonomyLevel.manual => true,
      AutonomyLevel.automatic => false,
      AutonomyLevel.checkpointed =>
        phase.humanCheckpoint || terminalNeedsApproval || fileEditsNeedApproval,
    };
  }

  bool _phaseUsesMutatingTools(JobPhase phase) {
    const mutating = {
      'write_file',
      'patch_file',
      'create_directory',
      'rename_path',
      'delete_path',
    };
    return phase.allowedTools.any(mutating.contains);
  }

  TerminalPolicy _effectiveTerminalPolicy(JobSpec spec, JobPhase phase) {
    final terminal = spec.toolPolicy.terminal;
    if (terminal?.allowed == false) return TerminalPolicy.none;
    final global = terminal?.policy ?? phase.terminalPolicy;
    return _terminalPolicyRank(global) <=
            _terminalPolicyRank(phase.terminalPolicy)
        ? global
        : phase.terminalPolicy;
  }

  int _terminalPolicyRank(TerminalPolicy policy) {
    return switch (policy) {
      TerminalPolicy.none => 0,
      TerminalPolicy.readonly => 1,
      TerminalPolicy.workspaceMutating => 2,
      TerminalPolicy.unrestrictedWorkspace => 3,
    };
  }

  Future<void> _streamAssistantResponse({
    required bool includeToolResults,
    required bool addGenerationPrompt,
    List<String> selectedToolIds = const [],
    String? anchorId,
    String? targetAssistantId,
  }) async {
    if (chatStream.isStreaming) return;
    final client = serverManager.chatClient;
    if (client == null) return;

    chatStream.setState(StreamState.streaming);

    final activeToolIds = selectedToolIds.isEmpty
        ? defaultToolIds
        : selectedToolIds;
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: addGenerationPrompt,
      toolDefs: activeToolIds.isNotEmpty
          ? _toolService.getToolDefinitions(
              ids: activeToolIds,
              includeWorkspaceTools: workspaceToolsEnabled,
            )
          : const [],
    );

    try {
      final emergencyOmittedMessageIds = await _compactContextIfNeeded(
        client: client,
        extraParams: extraParams,
      );

      final targetIndex = targetAssistantId == null
          ? -1
          : messageStore.messages.indexWhere(
              (m) =>
                  m.id == targetAssistantId && m.role == MessageRole.assistant,
            );

      final contextIndex = targetIndex >= 0
          ? targetIndex
          : () {
              final bubble = Bubble(
                id: uuid.v7(),
                role: MessageRole.assistant,
                text: '',
                reasoning: '',
              );
              messageStore.upsert(bubble);
              messageStore.setCurrentId(bubble.id);

              if (anchorId != null) {
                final index = messageStore.messages.indexWhere(
                  (m) => m.id == anchorId,
                );
                return index > 0 ? (messageStore.messages.length - 2) : index;
              }

              return messageStore.messages.length - 2;
            }();

      if (targetIndex >= 0) {
        messageStore.setCurrentId(targetAssistantId);
      }

      final currentUserRequest = _currentUserRequestFor(contextIndex);
      final payloadMessages = _payloadMessages(
        currentUserRequest: currentUserRequest,
      );

      final payload = includeToolResults
          ? PayloadBuilder.buildPayloadWithTools(
              messages: payloadMessages,
              upToIndexInclusive: contextIndex,
              omitCoveredMessages: true,
              omittedMessageIds: emergencyOmittedMessageIds,
            )
          : PayloadBuilder.buildPayload(
              messages: payloadMessages,
              upToIndexInclusive: contextIndex,
              omitCoveredMessages: true,
              omittedMessageIds: emergencyOmittedMessageIds,
            );

      serverManager.diagnostics.recordStreamStarted(
        estimatedContextTokens: ContextEstimator.estimateChatCompletionRequest(
          messages: payload,
          extraParams: extraParams,
        ),
        contextLimitTokens: currentModelSnapshot?.nCtx,
      );

      final sub = client.streamMessage(
        messages: payload,
        extraParams: extraParams,
      );

      chatStream.attach(
        sub.listen(
          _handleStreamToken,
          onError: (e, _) async => await _handleStreamTerminal(error: e),
          onDone: () async => await _handleStreamTerminal(),
          cancelOnError: true,
        ),
      );
    } catch (e) {
      serverManager.diagnostics.recordCompactionFailed(e);
      messageStore.clearCurrentId();
      await chatStream.stop(next: StreamState.error);
    }
  }

  Future<Set<String>> _compactContextIfNeeded({
    required ChatClient client,
    required Map<String, dynamic> extraParams,
  }) async {
    final snapshot = currentModelSnapshot;
    if (snapshot == null) return const {};

    final settings = await _preferencesService.getCompactionSettings();
    final manager = CompactionManager(settings: settings, client: client);
    if (!manager.shouldCompact(
      messages: messageStore.messages,
      contextLimit: snapshot.nCtx,
      extraParams: extraParams,
    )) {
      return const {};
    }

    void status(String message) {
      if (serverManager.diagnostics.compactionActive) {
        serverManager.diagnostics.recordCompactionStatus(message);
      } else {
        serverManager.diagnostics.recordCompactionStarted(message);
      }
      notifyListeners();
    }

    final result = await manager.compactIfNeeded(
      messageStore: messageStore,
      contextLimit: snapshot.nCtx,
      extraParams: extraParams,
      onStatusChanged: status,
    );

    final finishStatus = result.emergencyPayloadTruncation
        ? 'Emergency context truncation active for this request.'
        : result.compacted
        ? 'Context compaction complete.'
        : 'Context compaction not needed.';
    final savedTokens = result.compacted || result.emergencyPayloadTruncation
        ? result.estimatedTokensSaved
        : null;
    final affectedMessages = result.compacted
        ? result.messagesCovered
        : result.emergencyPayloadTruncation
        ? result.emergencyOmittedMessageIds.length
        : null;

    serverManager.diagnostics.recordCompactionFinished(
      status: finishStatus,
      tokensSaved: savedTokens,
      messagesCovered: affectedMessages,
    );

    return result.emergencyOmittedMessageIds;
  }

  void _handleStreamToken(ChatToken token) {
    serverManager.diagnostics.recordStreamOutput(_streamedText(token));
    messageStore.appendToken(token);
  }

  String _streamedText(ChatToken token) {
    return [
      token.content,
      token.reasoning,
      token.tool?.name,
      token.tool?.argumentsChunk,
    ].whereType<String>().join();
  }

  Future<void> _runToolsAndContinue(List<BubbleToolCall> calls) async {
    final assistantBubble = messageStore.currentMessage;

    if (assistantBubble == null) {
      messageStore.clearCurrentId();
      return;
    }

    final Map<int, BubbleToolCall> updated = Map.of(assistantBubble.tools);

    for (final entry in assistantBubble.tools.entries) {
      final toolIndex = entry.key;
      final toolCall = entry.value;

      final toolName = toolCall.name;
      final argsJson = toolCall.arguments;

      if (toolName == null || argsJson == null) {
        updated[toolIndex] = toolCall.copyWith(
          result: '{"error":"missing tool name or args"}',
        );
        continue;
      }

      final resultJson = await _toolService.execute(
        toolId: toolName,
        argumentsJson: argsJson,
        context: hasActiveWorkspace
            ? WorkspaceToolContext(workspace: workspace!)
            : null,
      );

      updated[toolIndex] = toolCall.copyWith(result: resultJson);
    }

    messageStore.upsert(assistantBubble.copyWith(tools: updated));

    await _streamAssistantResponse(
      includeToolResults: true,
      addGenerationPrompt: true,
      selectedToolIds: const [],
      anchorId: assistantBubble.id,
    );
  }

  Future<void> _handleStreamTerminal({Object? error}) async {
    if (error != null) {
      serverManager.diagnostics.recordStreamError(error);
      messageStore.appendCurrentError(error);
      messageStore.clearCurrentId();
      await chatStream.stop(next: StreamState.error);
      return;
    }

    if (messageStore.currentMessage != null) {
      messageStore.upsert(
        ContentNormaliser.normalise(messageStore.currentMessage!),
      );
    }

    await chatStream.stop();
    serverManager.diagnostics.recordStreamEnded();

    final toolCalls = ToolCaller.extractToolCalls(messageStore.currentMessage);
    if (toolCalls.isNotEmpty) {
      try {
        await _runToolsAndContinue(toolCalls);
      } catch (e) {
        messageStore.appendCurrentError(e);
        messageStore.clearCurrentId();
        await chatStream.stop(next: StreamState.error);
      }

      return;
    }

    messageStore.clearCurrentId();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    messageStore.removeListener(_handleMessagesChanged);
    _preferencesService.removeListener(_handlePreferencesChanged);
    _autosaveTimer?.cancel();
    await flushCurrentChat();
    await _deleteTransientJobsForCurrentScope();
    _disposed = true;
    messageStore.clearCurrentId();
    messageStore.clearToolBuffers();
    try {
      await chatStream.stop();
    } finally {
      super.dispose();
    }
  }

  void _handleMessagesChanged() {
    _updateContextEstimate();
    if (_disposed || _loadingSnapshot || currentChatId == null) return;
    _dirty = true;
    _scheduleAutosave();
  }

  void _handlePreferencesChanged() {
    unawaited(_loadJobSystemSettings());
  }

  Future<JobSystemSettings> _loadJobSystemSettings() async {
    final settings = await _preferencesService.getJobSystemSettings();
    if (_disposed) return settings;
    if (jobSystemSettings != settings) {
      jobSystemSettings = settings;
      notifyListeners();
    }
    return settings;
  }

  Future<JobSystemSettings> _refreshJobSystemSettings() {
    return _loadJobSystemSettings();
  }

  Future<bool> _jobSystemEnabled() async {
    return (await _refreshJobSystemSettings()).enabled;
  }

  String get _jobScopeId => currentChatId ?? _chatSessionScopeId;

  Future<String> _ensureJobScopeId() async => _jobScopeId;

  Future<void> _deleteTransientJobsForCurrentScope() async {
    if (currentChatId != null) return;
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;
    await _jobService.deleteJobsForChatSession(
      currentWorkspace,
      chatSessionId: _chatSessionScopeId,
    );
    activeJob = null;
    availableJobs = const [];
  }

  List<WorkspaceAttachment> _workspacesForSavedChatDeletion(
    String chatId,
    WorkspaceAttachment? savedWorkspace,
  ) {
    final byRoot = <String, WorkspaceAttachment>{};
    void add(WorkspaceAttachment? item) {
      if (item == null || item.missing) return;
      byRoot[item.rootPath] = item;
    }

    add(savedWorkspace);
    if (currentChatId == chatId) add(workspace);
    return byRoot.values.toList();
  }

  Future<void> _deleteJobsForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) async {
    for (final workspace in workspaces) {
      await _jobService.deleteJobsForChatSession(
        workspace,
        chatSessionId: chatSessionId,
      );
    }
  }

  void _beginJobModelOutput(String title) {
    jobModelOutputTitle = title;
    jobModelOutputText = '';
    jobModelOutputReasoning = '';
    jobModelOutputActive = true;
    _jobModelOutputLabel = null;
    _jobModelOutputTextSection = null;
    _jobModelOutputReasoningLabel = null;
  }

  void _clearJobModelOutput({bool notify = true}) {
    jobModelOutputTitle = null;
    jobModelOutputText = '';
    jobModelOutputReasoning = '';
    jobModelOutputActive = false;
    _jobModelOutputLabel = null;
    _jobModelOutputTextSection = null;
    _jobModelOutputReasoningLabel = null;
    if (notify && !_disposed) notifyListeners();
  }

  void _handleJobModelOutput(JobModelOutputEvent event) {
    if (jobModelOutputTitle == null) {
      _beginJobModelOutput('Job Model Output');
    }

    switch (event.type) {
      case JobModelOutputEventType.start:
        _jobModelOutputLabel = event.label;
        _jobModelOutputTextSection = null;
        _appendJobModelText('\n\n## ${event.label}\n');
      case JobModelOutputEventType.content:
        _ensureJobModelTextSection(event.label, 'output');
        _appendJobModelText(event.text);
      case JobModelOutputEventType.reasoning:
        _ensureJobModelReasoningSection(event.label);
        jobModelOutputReasoning += event.text;
      case JobModelOutputEventType.toolCall:
        _ensureJobModelTextSection(event.label, 'tool-call');
        _appendJobModelText('\nTool call:\n${event.text}\n');
      case JobModelOutputEventType.toolResult:
        _ensureJobModelTextSection(event.label, 'tool-result');
        _appendJobModelText('\nTool result:\n${event.text}\n');
      case JobModelOutputEventType.done:
        _jobModelOutputTextSection = null;
      case JobModelOutputEventType.error:
        _ensureJobModelTextSection(event.label, 'error');
        _appendJobModelText('\nError: ${event.text}\n');
    }

    if (!_disposed) notifyListeners();
  }

  void _ensureJobModelTextSection(String label, String section) {
    if (_jobModelOutputLabel != label) {
      _jobModelOutputLabel = label;
      _jobModelOutputTextSection = null;
      _appendJobModelText('\n\n## $label\n');
    }
    if (_jobModelOutputTextSection == section) return;
    _jobModelOutputTextSection = section;
    switch (section) {
      case 'output':
        _appendJobModelText('\n');
      case 'tool-call':
        _appendJobModelText('\n');
      case 'tool-result':
        _appendJobModelText('\n');
      case 'error':
        _appendJobModelText('\n');
    }
  }

  void _ensureJobModelReasoningSection(String label) {
    if (_jobModelOutputReasoningLabel == label) return;
    _jobModelOutputReasoningLabel = label;
    jobModelOutputReasoning +=
        '${jobModelOutputReasoning.trim().isEmpty ? '' : '\n\n'}## $label\n';
  }

  void _appendJobModelText(String text) {
    jobModelOutputText += text;
  }

  void _finishJobModelOutput() {
    jobModelOutputActive = false;
  }

  void _insertJobAssistantMessage(String text) {
    if (!jobSystemSettings.showJobMessagesInChat) return;
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.assistant,
        text: text,
        reasoning: '',
      ),
    );
  }

  void _updateContextEstimate() {
    final snapshot = currentModelSnapshot;
    if (snapshot == null || messageStore.messages.isEmpty) {
      serverManager.diagnostics.updateContextEstimate(null);
      return;
    }

    final payload = PayloadBuilder.buildPayloadWithTools(
      messages: _payloadMessages(),
      upToIndexInclusive: messageStore.messages.length - 1,
      omitCoveredMessages: true,
    );
    serverManager.diagnostics.updateContextEstimate(
      ContextEstimator.estimateChatCompletionRequest(messages: payload),
      contextLimitTokens: snapshot.nCtx,
    );
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_queueSave(force: true)),
    );
  }

  Future<SavedChat> _queueSave({String? title, bool force = false}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    final completer = Completer<SavedChat>();

    final operation = _saveChain.then((_) async {
      if (_disposed) {
        throw StateError('ChatService is disposed');
      }

      if (!force && currentChatId != null && !_dirty) {
        return currentSavedChat!;
      }

      final previousChatId = currentChatId;
      final previousScopeId = _jobScopeId;
      final saved = await _chatLibrary.saveChatSnapshot(
        chatId: currentChatId,
        title: title,
        messages: messageStore.messages.toList(),
        modelSnapshot: currentModelSnapshot,
        workspace: workspace,
        systemPromptSnapshot: currentSystemPromptSnapshot,
      );

      currentChatId = saved.id;
      _chatSessionScopeId = saved.id;
      currentSavedChat = saved;
      if (previousChatId == null) {
        await _migrateJobScope(
          previousScopeId: previousScopeId,
          savedChatId: saved.id,
        );
      }
      _dirty = false;
      notifyListeners();
      return saved;
    });

    _saveChain = operation.then<void>((_) {});
    operation.then(completer.complete, onError: completer.completeError);
    return completer.future;
  }

  Future<void> _migrateJobScope({
    required String previousScopeId,
    required String savedChatId,
  }) async {
    if (previousScopeId == savedChatId) return;
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;

    final activeJobId = activeJob?.spec.id;
    final jobs = await _jobService.listJobs(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final job in jobs) {
      final snapshot = await _jobService.loadJob(
        currentWorkspace,
        job.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _jobService.updateJobChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.spec.id == activeJobId) {
        activeJob = updated;
      }
    }
    availableJobs = await _jobService.listJobs(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
  }

  Future<void> _prepareModelRestorePrompt(
    ModelConfigurationSnapshot? snapshot,
  ) async {
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;

    if (snapshot == null || snapshot.matches(_activeServerSnapshot)) return;

    pendingModelRestore = snapshot;
    if (!await File(snapshot.modelPath).exists()) {
      pendingModelRestoreIssue =
          'Saved model file not found: ${snapshot.modelPath}';
    }
  }

  void _clearSavedState() {
    currentChatId = null;
    _chatSessionScopeId = uuid.v7();
    currentSavedChat = null;
    workspace = null;
    activeJob = null;
    availableJobs = const [];
    jobError = null;
    jobStatusMessage = null;
    currentSystemPromptSnapshot = null;
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    _dirty = false;
    notifyListeners();
  }

  Future<WorkspaceAttachment?> _restoreWorkspace(
    WorkspaceAttachment? saved,
  ) async {
    if (saved == null) return null;
    return _workspaceService.restore(
      rootPath: saved.rootPath,
      displayName: saved.displayName,
      lastOpenedAt: saved.lastOpenedAt,
      commandExecutionApproved: saved.commandExecutionApproved,
    );
  }

  String _buildSystemPrompt({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) {
    final snapshot = currentSystemPromptSnapshot;
    if (snapshot?.preset != null) {
      final result = _promptAssembler.assemble(
        PromptAssemblyRequest(
          preset: snapshot!.preset,
          availableModules: snapshot.modules,
          selectedModuleIds: {
            ...snapshot.selectedModuleIds,
            ...additionalModuleIds,
          }.toList(),
          autoModuleIds: _autoModuleIdsForWorkspace(),
          workspaceRootPath: workspace?.rootPath,
          workspaceMissing: workspace?.missing ?? false,
          commandExecutionApproved: workspace?.commandExecutionApproved == true,
          currentUserRequest: currentUserRequest,
        ),
      );
      if (result.text.trim().isNotEmpty) return result.text;
      if (snapshot.text.trim().isNotEmpty) return snapshot.text.trim();
    }

    final basePrompt =
        currentSystemPromptSnapshot?.text.trim().isNotEmpty == true
        ? currentSystemPromptSnapshot!.text.trim()
        : defaultSystemPromptText;
    final currentWorkspace = workspace;
    if (currentWorkspace == null) {
      return basePrompt;
    }

    if (currentWorkspace.missing) {
      return '$basePrompt\n\nA workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.';
    }

    return '''
$basePrompt

This chat has an attached workspace. The workspace root is:
${currentWorkspace.rootPath}

Workspace rules:
- Use workspace tools for file and folder operations.
- Only operate inside the attached workspace and use workspace-relative paths.
- Inspect relevant files before editing them.
- Prefer small, precise changes.
- Explain destructive file operations before performing them.
- Terminal commands are guarded and may be unavailable unless the user enables them for this chat.
'''
        .trim();
  }

  String _buildJobSystemPrompt(JobSnapshot snapshot, {JobPhase? phase}) {
    return _buildSystemPrompt(
      currentUserRequest: snapshot.taskBrief.originalPrompt,
      additionalModuleIds: _jobPromptModuleIds(snapshot, phase: phase),
    );
  }

  List<String> _jobPromptModuleIds(JobSnapshot snapshot, {JobPhase? phase}) {
    return {...snapshot.spec.promptModules, ...?phase?.promptModules}.toList();
  }

  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    String? currentUserRequest,
  }) {
    final promptText = _buildSystemPrompt(
      currentUserRequest: currentUserRequest,
    );
    if (messages.isEmpty) return [systemPrompt.copyWith(text: promptText)];

    final copy = List<Bubble>.of(messages);
    if (copy.first.role == MessageRole.system) {
      copy[0] = copy.first.copyWith(text: promptText);
    } else {
      copy.insert(0, systemPrompt.copyWith(text: promptText));
    }
    return copy;
  }

  void _syncSystemPrompt() {
    messageStore.setMessages(_withCurrentSystemPrompt(messageStore.messages));
  }

  List<Bubble> _payloadMessages({String? currentUserRequest}) {
    return _withCurrentSystemPrompt(
      messageStore.messages,
      currentUserRequest: currentUserRequest,
    );
  }

  String? _currentUserRequestFor(int contextIndex) {
    final end = contextIndex.clamp(0, messageStore.messages.length - 1);
    for (var i = end; i >= 0; i--) {
      final message = messageStore.messages[i];
      if (message.role == MessageRole.user && message.text.trim().isNotEmpty) {
        return message.text.trim();
      }
    }
    return null;
  }

  List<String> _autoModuleIdsForWorkspace() {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return const [];
    return currentWorkspace.missing
        ? const [BuiltInPromptIds.workspaceMissingModule]
        : const [BuiltInPromptIds.workspaceRulesModule];
  }

  _SlashCommand? _parseSlashCommand(String text) {
    final match = RegExp(
      r'^/(job|plan|refine|continue)\b(.*)$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return _SlashCommand(
      name: match.group(1)!.toLowerCase(),
      argument: match.group(2)?.trim() ?? '',
      raw: text,
    );
  }

  void _insertUserAndAssistant(String userText, String assistantText) {
    messageStore
      ..upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.user,
          text: userText,
          reasoning: '',
        ),
      )
      ..upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: assistantText,
          reasoning: '',
        ),
      );
  }

  void _markWorkspaceChanged() {
    if (currentChatId != null) {
      _dirty = true;
      _scheduleAutosave();
    }
    notifyListeners();
  }

  void _adoptActiveModelIfRestoreDismissed() {
    if (pendingModelRestore != null) return;

    final activeSnapshot = _activeServerSnapshot;
    if (activeSnapshot == null ||
        activeSnapshot.matches(currentModelSnapshot)) {
      return;
    }

    currentModelSnapshot = activeSnapshot;
    _updateContextEstimate();
    if (currentChatId != null) {
      _dirty = true;
      _scheduleAutosave();
    }
    notifyListeners();
  }

  String _taskBriefMessage(TaskBrief brief) {
    final buffer = StringBuffer()
      ..writeln('Task brief refined: **${brief.title}**')
      ..writeln()
      ..writeln('Objective:')
      ..writeln(brief.objective)
      ..writeln()
      ..writeln('Success criteria:');
    for (final item in brief.successCriteria) {
      buffer.writeln('- $item');
    }
    if (brief.constraints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Constraints:');
      for (final item in brief.constraints) {
        buffer.writeln('- $item');
      }
    }
    if (brief.assumptions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Assumptions:');
      for (final item in brief.assumptions) {
        buffer.writeln('- $item');
      }
    }
    if (brief.clarifyingQuestions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Clarifying questions:');
      for (final question in brief.clarifyingQuestions.take(3)) {
        final required = question.required ? 'required' : 'optional';
        buffer.writeln('- [$required] ${question.question}');
      }
    }
    if (brief.requiredOutputs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Required outputs:');
      for (final output in brief.requiredOutputs) {
        buffer.writeln('- `${output.path}`');
      }
    }
    buffer
      ..writeln()
      ..writeln('Recommended mode: `${brief.recommendedMode.wire}`')
      ..writeln('Recommended autonomy: `${brief.recommendedAutonomy.wire}`')
      ..writeln('Risk level: `${brief.riskLevel.wire}`');
    return buffer.toString().trim();
  }

  String _jobCreatedMessage(JobSnapshot snapshot) {
    final spec = snapshot.spec;
    if (spec.status == JobStatus.draft) {
      final requiredQuestions = snapshot.state.openQuestions
          .where(
            (question) =>
                question.required && question.status == OpenQuestionStatus.open,
          )
          .length;
      final buffer = StringBuffer()
        ..writeln('Task brief created: **${spec.title}**')
        ..writeln()
        ..writeln('Status: `${snapshot.state.status.wire}`')
        ..writeln('Planning is paused at the clarification gate.');
      if (requiredQuestions > 0) {
        buffer.writeln(
          'Answer $requiredQuestions required question${requiredQuestions == 1 ? '' : 's'} before generating the job plan.',
        );
      }
      buffer
        ..writeln()
        ..writeln('Artifacts are stored under `.agent/jobs/${spec.id}/`.');
      return buffer.toString().trim();
    }

    final buffer = StringBuffer()
      ..writeln('Job created: **${spec.title}**')
      ..writeln()
      ..writeln('Status: `${spec.status.wire}`')
      ..writeln('Autonomy: `${spec.autonomy.wire}`')
      ..writeln()
      ..writeln('Phases:');
    for (var i = 0; i < spec.phases.length; i++) {
      final phase = spec.phases[i];
      buffer.writeln('${i + 1}. ${phase.title}');
    }
    buffer
      ..writeln()
      ..writeln('Artifacts are stored under `.agent/jobs/${spec.id}/`.');
    return buffer.toString().trim();
  }

  String _phaseFinishedMessage(JobSnapshot snapshot) {
    final latestRun = snapshot.state.phaseRuns.isEmpty
        ? null
        : snapshot.state.phaseRuns.last;
    final review = latestRun?.reviewResult;
    final buffer = StringBuffer()
      ..writeln('Job phase finished: **${latestRun?.phaseId ?? 'phase'}**')
      ..writeln()
      ..writeln('Job status: `${snapshot.state.status.wire}`');
    if (review != null) {
      buffer
        ..writeln('Review: `${review.status.wire}`')
        ..writeln()
        ..writeln(review.summary);
    } else if (latestRun != null) {
      buffer
        ..writeln()
        ..writeln(latestRun.summary);
    }
    if (snapshot.state.artifacts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Artifacts:');
      for (final artifact in snapshot.state.artifacts.take(8)) {
        buffer.writeln('- `${artifact.path}`');
      }
    }
    return buffer.toString().trim();
  }
}

class _SlashCommand {
  final String name;
  final String argument;
  final String raw;

  const _SlashCommand({
    required this.name,
    required this.argument,
    required this.raw,
  });
}
