import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/runtime/chat_controller.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/features/settings/application/preferences_port.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

import 'package:hermes/core/disposable.dart';
import 'package:hermes/features/chat/application/contracts/chat_workspace_contracts.dart';
import 'package:hermes/features/chat/application/contracts/chat_presentation_ports.dart';
import 'package:hermes/features/chat/runtime/chat_workflow_compatibility.dart';

typedef ChatTabFactory =
    ChatRuntimeController Function({
      required ModelServerPort serverManager,
      required ToolRegistryPort toolService,
      required ToolProtocolAdapter toolProtocol,
      required ChatToolExecutionPort toolExecution,
      required TaskWorkflowQueryPort taskQueries,
      required TaskSessionPort taskSessions,
      required TaskPresentationPort taskPresentation,
      required ChatPanelProtocolAdapter panelProtocol,
      required TaskWorkflowPort taskPlanning,
      required TaskWorkflowPort taskExecution,
      required TaskWorkflowPort taskRecovery,
      required ProjectWorkflowQueryPort projectQueries,
      required ProjectSessionPort projectSessions,
      required ProjectWorkflowPort projectPlanning,
      required ProjectWorkflowPort projectCommands,
      required ProjectWorkflowPort projectExecution,
      required ProjectWorkflowPort projectRecovery,
      required ChatLibraryService chatLibrary,
      required WorkspacePort workspaceService,
      required ChatRuntimePreferencesPort preferencesService,
      SystemPromptSnapshot? initialSystemPromptSnapshot,
    });

class ChatRuntimeWorkspaceController extends ChangeNotifier
    implements Disposable, ChatWorkspacePresentationPort {
  final ChatLibraryService _chatLibrary;
  final SystemPromptLibraryService _systemPromptLibrary;
  final ToolRegistryPort _toolService;
  final ToolProtocolAdapter _toolProtocol;
  final ChatToolExecutionPort _toolExecution;
  final TaskWorkflowQueryPort _taskQueries;
  final TaskSessionPort _taskSessions;
  final TaskPresentationPort _taskPresentation;
  final ChatPanelProtocolAdapter _panelProtocol;
  final TaskWorkflowPort _taskPlanning;
  final TaskWorkflowPort _taskExecution;
  final TaskWorkflowPort _taskRecovery;
  final ProjectWorkflowQueryPort _projectQueries;
  final ProjectSessionPort _projectSessions;
  final ProjectWorkflowPort _projectPlanning;
  final ProjectWorkflowPort _projectCommands;
  final ProjectWorkflowPort _projectExecution;
  final ProjectWorkflowPort _projectRecovery;
  final WorkspacePort _workspaceService;
  final ChatRuntimePreferencesPort _preferencesService;
  final ChatTabFactory? _tabFactory;

  final ModelServerPort serverManager;
  final List<ChatRuntimeController> _tabs = [];

  String? activeTabId;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  ChatRuntimeWorkspaceController({
    required this.serverManager,
    required ChatLibraryService chatLibrary,
    required SystemPromptLibraryService systemPromptLibrary,
    required ToolRegistryPort toolService,
    required ToolProtocolAdapter toolProtocol,
    required ChatToolExecutionPort toolExecution,
    required TaskWorkflowQueryPort taskQueries,
    required TaskSessionPort taskSessions,
    required TaskPresentationPort taskPresentation,
    required ChatPanelProtocolAdapter panelProtocol,
    required Object taskPlanning,
    required Object taskExecution,
    required Object taskRecovery,
    required ProjectWorkflowQueryPort projectQueries,
    required ProjectSessionPort projectSessions,
    required Object projectPlanning,
    required Object projectCommands,
    required Object projectExecution,
    required Object projectRecovery,
    required WorkspacePort workspaceService,
    required ChatRuntimePreferencesPort preferencesService,
    ChatTabFactory? tabFactory,
  }) : _chatLibrary = chatLibrary,
       _systemPromptLibrary = systemPromptLibrary,
       _toolService = toolService,
       _toolProtocol = toolProtocol,
       _toolExecution = toolExecution,
       _taskQueries = taskQueries,
       _taskSessions = taskSessions,
       _taskPresentation = taskPresentation,
       _panelProtocol = panelProtocol,
       _taskPlanning = resolveTaskWorkflowPort(
         taskPlanning,
         taskExecution,
         taskRecovery,
       ),
       _taskExecution = resolveTaskWorkflowPort(
         taskPlanning,
         taskExecution,
         taskRecovery,
       ),
       _taskRecovery = resolveTaskWorkflowPort(
         taskPlanning,
         taskExecution,
         taskRecovery,
       ),
       _projectQueries = projectQueries,
       _projectSessions = projectSessions,
       _projectPlanning = resolveProjectWorkflowPort(
         projectPlanning,
         projectCommands,
         projectExecution,
         projectRecovery,
       ),
       _projectCommands = resolveProjectWorkflowPort(
         projectPlanning,
         projectCommands,
         projectExecution,
         projectRecovery,
       ),
       _projectExecution = resolveProjectWorkflowPort(
         projectPlanning,
         projectCommands,
         projectExecution,
         projectRecovery,
       ),
       _projectRecovery = resolveProjectWorkflowPort(
         projectPlanning,
         projectCommands,
         projectExecution,
         projectRecovery,
       ),
       _workspaceService = workspaceService,
       _preferencesService = preferencesService,
       _tabFactory = tabFactory {
    newTab();
  }

  UnmodifiableListView<ChatRuntimeController> get tabs =>
      UnmodifiableListView(_tabs);

  @override
  List<ChatTabPresentationPort> get presentationTabs =>
      List<ChatTabPresentationPort>.unmodifiable(_tabs);

  ChatRuntimeController? get activeChat {
    final id = activeTabId;
    if (id == null) return _tabs.firstOrNull;
    return _tabs.where((tab) => tab.tabId == id).firstOrNull;
  }

  @override
  ChatTabPresentationPort? get presentationActiveChat => activeChat;

  ChatRuntimeController newTab({SystemPromptSnapshot? systemPromptSnapshot}) {
    final tab = _createTab(systemPromptSnapshot: systemPromptSnapshot);
    _tabs.add(tab);
    activeTabId = tab.tabId;
    notifyListeners();
    return tab;
  }

  Future<void> selectTab(String tabId) async {
    if (activeTabId == tabId) return;
    final tab = _tabById(tabId);
    if (tab == null) return;

    activeTabId = tabId;
    notifyListeners();
    await tab.refreshModelRestorePrompt();
  }

  bool isSavedChatOpen(String chatId) =>
      _tabs.any((tab) => tab.currentChatId == chatId);

  ChatRuntimeController? tabForSavedChat(String chatId) =>
      _tabs.where((tab) => tab.currentChatId == chatId).firstOrNull;

  Future<bool> openSavedChat(
    String chatId, {
    required OpenChatTarget target,
  }) async {
    final existing = tabForSavedChat(chatId);
    if (existing != null) {
      await selectTab(existing.tabId);
      return true;
    }

    final tab = target == OpenChatTarget.newTab ? _createTab() : activeChat;
    if (tab == null) return false;

    if (target == OpenChatTarget.newTab) {
      _tabs.add(tab);
      activeTabId = tab.tabId;
      notifyListeners();
    }

    final opened = await tab.openChat(chatId);
    if (!opened && target == OpenChatTarget.newTab) {
      await _removeTab(tab);
    }

    notifyListeners();
    return opened;
  }

  Future<void> saveCurrentChat({String? title}) async {
    await activeChat?.saveCurrentChat(title: title);
    notifyListeners();
  }

  Future<void> prepareForExit(NewChatExitPolicy newChatPolicy) async {
    final failures = <ChatFlushFailure>[];
    final tabsThatFailedToQuiesce = <String>{};
    final snapshot = List<ChatRuntimeController>.of(_tabs);

    for (final tab in snapshot) {
      try {
        await tab.quiesceForExit();
      } catch (error, stackTrace) {
        tabsThatFailedToQuiesce.add(tab.tabId);
        failures.add(
          ChatFlushFailure(
            tabId: tab.tabId,
            title: tab.displayTitle,
            stage: 'stop active work in',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    for (final tab in snapshot) {
      if (tabsThatFailedToQuiesce.contains(tab.tabId)) continue;
      try {
        if (tab.currentChatId != null) {
          await tab.flushCurrentChat();
        } else if (newChatPolicy == NewChatExitPolicy.save &&
            tab.isUnsavedNonEmpty) {
          await tab.saveCurrentChat();
        }
      } catch (error, stackTrace) {
        failures.add(
          ChatFlushFailure(
            tabId: tab.tabId,
            title: tab.displayTitle,
            stage: 'save',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    if (failures.isNotEmpty) {
      throw ChatFlushException(List.unmodifiable(failures));
    }
  }

  Future<SystemPromptLoadTarget> loadPromptPresetIntoActiveChat(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
  }) async {
    final active = activeChat;
    if (active != null && !active.isSystemPromptLocked) {
      final snapshot = await _systemPromptLibrary.snapshotForPreset(
        preset,
        selectedOptionalModuleIds: selectedOptionalModuleIds,
        workspace: active.workspace,
      );
      active.updateSystemPromptSnapshot(snapshot);
      await _systemPromptLibrary.markPresetUsed(preset.id);
      notifyListeners();
      return SystemPromptLoadTarget.currentChat;
    }

    final snapshot = await _systemPromptLibrary.snapshotForPreset(
      preset,
      selectedOptionalModuleIds: selectedOptionalModuleIds,
    );
    newTab(systemPromptSnapshot: snapshot);
    await _systemPromptLibrary.markPresetUsed(preset.id);
    notifyListeners();
    return SystemPromptLoadTarget.newTab;
  }

  Future<void> closeTab(String tabId) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    final wasActive = activeTabId == tabId;
    await _removeTab(tab);
    if (_tabs.isEmpty) {
      newTab();
    } else if (wasActive) {
      await activeChat?.refreshModelRestorePrompt();
      notifyListeners();
    }
  }

  Future<void> saveAndCloseTab(String tabId) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    await tab.saveCurrentChat();
    await closeTab(tabId);
  }

  Future<void> deleteSavedChat(String chatId) async {
    final snapshot = await _chatLibrary.getChat(chatId);
    final workspaces = _workspacesForDeletedChat(
      chatId,
      snapshot?.chat.workspace,
    );
    await _chatLibrary.deleteChat(chatId);
    try {
      await _deleteProjectsForChatSessionInWorkspaces(chatId, workspaces);
      await _deleteTasksForChatSessionInWorkspaces(chatId, workspaces);
    } finally {
      for (final tab in _tabs.where((tab) => tab.currentChatId == chatId)) {
        await tab.resetIfCurrentSavedChatDeleted(chatId);
      }
    }
    notifyListeners();
  }

  ChatRuntimeController _createTab({
    SystemPromptSnapshot? systemPromptSnapshot,
  }) {
    final factory = _tabFactory;
    final tab = factory == null
        ? ChatRuntimeController(
            serverManager: serverManager,
            toolService: _toolService,
            toolProtocol: _toolProtocol,
            toolExecution: _toolExecution,
            taskQueries: _taskQueries,
            taskSessions: _taskSessions,
            taskPresentation: _taskPresentation,
            panelProtocol: _panelProtocol,
            taskPlanning: _taskPlanning,
            taskExecution: _taskExecution,
            taskRecovery: _taskRecovery,
            projectQueries: _projectQueries,
            projectSessions: _projectSessions,
            projectPlanning: _projectPlanning,
            projectCommands: _projectCommands,
            projectExecution: _projectExecution,
            projectRecovery: _projectRecovery,
            chatLibrary: _chatLibrary,
            workspaceService: _workspaceService,
            preferencesService: _preferencesService,
            initialSystemPromptSnapshot: systemPromptSnapshot,
          )
        : factory(
            serverManager: serverManager,
            toolService: _toolService,
            toolProtocol: _toolProtocol,
            toolExecution: _toolExecution,
            taskQueries: _taskQueries,
            taskSessions: _taskSessions,
            taskPresentation: _taskPresentation,
            panelProtocol: _panelProtocol,
            taskPlanning: _taskPlanning,
            taskExecution: _taskExecution,
            taskRecovery: _taskRecovery,
            projectQueries: _projectQueries,
            projectSessions: _projectSessions,
            projectPlanning: _projectPlanning,
            projectCommands: _projectCommands,
            projectExecution: _projectExecution,
            projectRecovery: _projectRecovery,
            chatLibrary: _chatLibrary,
            workspaceService: _workspaceService,
            preferencesService: _preferencesService,
            initialSystemPromptSnapshot: systemPromptSnapshot,
          );
    tab.addListener(notifyListeners);
    return tab;
  }

  ChatRuntimeController? _tabById(String tabId) =>
      _tabs.where((tab) => tab.tabId == tabId).firstOrNull;

  Future<void> _removeTab(ChatRuntimeController tab) async {
    final index = _tabs.indexOf(tab);
    if (index == -1) return;

    tab.removeListener(notifyListeners);
    try {
      await tab.dispose();
    } catch (_) {
      tab.addListener(notifyListeners);
      rethrow;
    }
    _tabs.removeAt(index);

    if (activeTabId == tab.tabId) {
      if (_tabs.isEmpty) {
        activeTabId = null;
      } else {
        final nextIndex = index.clamp(0, _tabs.length - 1);
        activeTabId = _tabs[nextIndex].tabId;
      }
    }

    notifyListeners();
  }

  @override
  // ignore: must_call_super, super.dispose is called by _dispose after async cleanup.
  Future<void> dispose() => _startDispose(prepare: true);

  Future<void> disposeWithoutSaving() => _startDispose(prepare: false);

  Future<void> _startDispose({required bool prepare}) {
    if (_disposed) return Future.value();
    final pending = _disposeFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _dispose(prepare: prepare).whenComplete(() {
      if (!_disposed && identical(_disposeFuture, operation)) {
        _disposeFuture = null;
      }
    });
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _dispose({required bool prepare}) async {
    if (prepare) {
      await prepareForExit(NewChatExitPolicy.discard);
    }
    _disposed = true;

    for (final tab in List<ChatRuntimeController>.of(_tabs)) {
      tab.removeListener(notifyListeners);
      _tabs.remove(tab);
      try {
        await tab.disposeWithoutSaving();
      } catch (error, stackTrace) {
        _reportDisposalFailure(
          error,
          stackTrace,
          context: 'while disposing chat tab ${tab.tabId}',
        );
      }
    }
    try {
      await _cleanupOrphanedTasks();
    } catch (error, stackTrace) {
      _reportDisposalFailure(
        error,
        stackTrace,
        context: 'while cleaning orphaned chat work',
      );
    }
    super.dispose();
  }

  void _reportDisposalFailure(
    Object error,
    StackTrace stackTrace, {
    required String context,
  }) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'hermes chat tabs disposal',
        context: ErrorDescription(context),
      ),
    );
  }

  /// Collects unique workspaces from the given attachments, keyed by root path.
  Map<String, WorkspaceAttachment> _collectWorkspacesByRoot(
    List<WorkspaceAttachment?> attachments,
  ) {
    final byRoot = <String, WorkspaceAttachment>{};
    for (final workspace in attachments) {
      if (workspace == null || workspace.missing) continue;
      byRoot[workspace.rootPath] = workspace;
    }
    return byRoot;
  }

  List<WorkspaceAttachment> _workspacesForDeletedChat(
    String chatId,
    WorkspaceAttachment? savedWorkspace,
  ) {
    final attachments = <WorkspaceAttachment?>[savedWorkspace];
    for (final tab in _tabs.where((tab) => tab.currentChatId == chatId)) {
      attachments.add(tab.workspace);
    }
    return _collectWorkspacesByRoot(attachments).values.toList();
  }

  Future<void> _deleteTasksForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) async {
    for (final workspace in workspaces) {
      await _taskSessions.deleteTasksForChatSession(
        workspace,
        chatSessionId: chatSessionId,
      );
    }
  }

  Future<void> _deleteProjectsForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) async {
    for (final workspace in workspaces) {
      await _projectSessions.deleteProjectsForChatSession(
        workspace,
        chatSessionId: chatSessionId,
      );
    }
  }

  Future<void> _cleanupOrphanedTasks() async {
    final savedChats = await _chatLibrary.listChats();
    final retainedChatSessionIds = savedChats.map((chat) => chat.id).toSet();

    final allWorkspaces = <WorkspaceAttachment?>[];
    for (final chat in savedChats) {
      allWorkspaces.add(chat.workspace);
    }
    for (final tab in _tabs) {
      allWorkspaces.add(tab.workspace);
    }
    allWorkspaces.addAll(await _workspaceService.recentWorkspaces());

    final byRoot = _collectWorkspacesByRoot(allWorkspaces);
    for (final workspace in byRoot.values) {
      await _taskSessions.deleteOrphanedChatTasks(
        workspace,
        retainedChatSessionIds: retainedChatSessionIds,
      );
      await _projectSessions.deleteOrphanedChatProjects(
        workspace,
        retainedChatSessionIds: retainedChatSessionIds,
      );
    }
  }
}
