import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_persistence.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed save does not poison later saves or disposal', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('hermes_save_chain_');
    final preferences = PreferencesService();
    final library = _FailingChatLibraryService(
      ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      ),
    );
    final serverManager = LlamaServerManager();
    final sandbox = WorkspaceSandbox();
    final tools = ToolService(workspaceSandbox: sandbox);
    final tasks = TaskService(toolService: tools, sandbox: sandbox);
    final chat = ChatService(
      serverManager: serverManager,
      toolService: tools,
      taskService: tasks,
      projectService: ProjectService(taskService: tasks),
      chatLibrary: library,
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
    addTearDown(() async {
      await chat.disposeWithoutSaving();
      await serverManager.dispose();
      await library.dispose();
      preferences.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    chat.messageStore.upsert(_message('user', 'Initial message'));
    await chat.saveCurrentChat();
    chat.messageStore.upsert(_message('assistant', 'Unsaved response'));
    library.failNextSave();

    await expectLater(chat.saveCurrentChat(), throwsStateError);

    expect(chat.isDirty, isTrue);
    expect(chat.saveFailure?.error, isA<StateError>());
    final attemptsAfterFailure = library.saveAttempts;

    await chat.retrySave();
    await chat.flushCurrentChat();

    expect(library.saveAttempts, attemptsAfterFailure + 1);
    expect(chat.isDirty, isFalse);
    expect(chat.saveFailure, isNull);
    await chat.dispose();
  });

  test('autosave failure is handled and remains retryable', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('hermes_autosave_');
    final preferences = PreferencesService();
    final library = _FailingChatLibraryService(
      ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      ),
    );
    final serverManager = LlamaServerManager();
    final sandbox = WorkspaceSandbox();
    final tools = ToolService(workspaceSandbox: sandbox);
    final tasks = TaskService(toolService: tools, sandbox: sandbox);
    final chat = ChatService(
      serverManager: serverManager,
      toolService: tools,
      taskService: tasks,
      projectService: ProjectService(taskService: tasks),
      chatLibrary: library,
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
    addTearDown(() async {
      await chat.disposeWithoutSaving();
      await serverManager.dispose();
      await library.dispose();
      preferences.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    chat.messageStore.upsert(_message('user', 'Initial message'));
    await chat.saveCurrentChat();
    library.failNextSave();
    chat.messageStore.upsert(_message('assistant', 'Triggers autosave'));

    await Future<void>.delayed(const Duration(milliseconds: 750));

    expect(chat.saveFailure, isNotNull);
    expect(chat.isDirty, isTrue);
    await chat.retrySave();
    expect(chat.saveFailure, isNull);
  });

  test('first save keeps edits made while persistence is in flight', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp(
      'hermes_save_revision_',
    );
    final preferences = PreferencesService();
    final library = _DelayedChatLibraryService(
      ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      ),
    );
    final serverManager = LlamaServerManager();
    final sandbox = WorkspaceSandbox();
    final tools = ToolService(workspaceSandbox: sandbox);
    final tasks = TaskService(toolService: tools, sandbox: sandbox);
    final chat = ChatService(
      serverManager: serverManager,
      toolService: tools,
      taskService: tasks,
      projectService: ProjectService(taskService: tasks),
      chatLibrary: library,
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
    addTearDown(() async {
      await chat.disposeWithoutSaving();
      await serverManager.dispose();
      await library.dispose();
      preferences.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    chat.messageStore.upsert(_message('first', 'Captured by first save'));
    library.delayNextSave();
    final firstSave = chat.saveCurrentChat();
    await library.saveStarted;

    chat.messageStore.upsert(_message('second', 'Added during first save'));
    library.releaseSave();
    await firstSave;

    expect(chat.currentChatId, isNotNull);
    expect(chat.isDirty, isTrue);
    expect(
      library.savedSnapshots.single.map((message) => message.id),
      isNot(contains('second')),
    );

    await chat.flushCurrentChat();

    final restored = await library.getChat(chat.currentChatId!);
    expect(restored?.messages.map((message) => message.id), contains('second'));
    expect(library.saveAttempts, 2);
    expect(chat.isDirty, isFalse);
  });

  test('exit preparation attempts every tab and can be retried', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('hermes_tab_flush_');
    final preferences = PreferencesService();
    final chatLibrary = _FailingChatLibraryService(
      ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      ),
    );
    final promptLibrary = SystemPromptLibraryService(
      repository: SystemPromptLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      ),
    );
    final sandbox = WorkspaceSandbox();
    final tools = ToolService(workspaceSandbox: sandbox);
    final tasks = TaskService(toolService: tools, sandbox: sandbox);
    final tabs = ChatTabsService(
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      toolService: tools,
      taskService: tasks,
      projectService: ProjectService(taskService: tasks),
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
    addTearDown(() async {
      await tabs.disposeWithoutSaving();
      await chatLibrary.dispose();
      await promptLibrary.dispose();
      preferences.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final first = tabs.activeChat!;
    first.messageStore.upsert(_message('first', 'First tab'));
    await first.saveCurrentChat();
    final second = tabs.newTab();
    second.messageStore.upsert(_message('second', 'Second tab'));
    await second.saveCurrentChat();
    first.messageStore.upsert(_message('first-change', 'First change'));
    second.messageStore.upsert(_message('second-change', 'Second change'));
    chatLibrary.failNextSave();
    final attemptsBeforeExit = chatLibrary.saveAttempts;

    await expectLater(
      tabs.prepareForExit(NewChatExitPolicy.discard),
      throwsA(
        isA<ChatFlushException>().having(
          (error) => error.failures.length,
          'failure count',
          1,
        ),
      ),
    );

    expect(chatLibrary.saveAttempts, attemptsBeforeExit + 2);
    expect(tabs.tabs, hasLength(2));
    expect(first.isDirty, isTrue);
    expect(second.isDirty, isFalse);

    await tabs.prepareForExit(NewChatExitPolicy.discard);
    expect(first.isDirty, isFalse);

    first.messageStore.upsert(_message('close-failure', 'Keep this tab'));
    chatLibrary.failNextSave();
    await expectLater(tabs.closeTab(first.tabId), throwsStateError);
    expect(tabs.tabs.map((tab) => tab.tabId), contains(first.tabId));

    await first.retrySave();
    await tabs.closeTab(first.tabId);
    expect(tabs.tabs.map((tab) => tab.tabId), isNot(contains(first.tabId)));

    await tabs.disposeWithoutSaving();
    expect(tabs.tabs, isEmpty);
    expect(tabs.serverManager.current, isNull);
  });
}

Bubble _message(String id, String text) => Bubble(
  id: id,
  role: MessageRole.user,
  text: text,
  reasoning: '',
  createdAt: DateTime.now(),
);

class _FailingChatLibraryService extends ChatLibraryService {
  _FailingChatLibraryService(ChatLibraryRepository repository)
    : super(repository: repository);

  var saveAttempts = 0;
  var _failuresRemaining = 0;

  void failNextSave() => _failuresRemaining++;

  @override
  Future<SavedChat> saveChatSnapshot({
    required List<Bubble> messages,
    required ModelConfigurationSnapshot? modelSnapshot,
    required WorkspaceAttachment? workspace,
    required SystemPromptSnapshot? systemPromptSnapshot,
    String? chatId,
    String? title,
  }) {
    saveAttempts++;
    if (_failuresRemaining > 0) {
      _failuresRemaining--;
      return Future.error(StateError('Injected save failure'));
    }
    return super.saveChatSnapshot(
      messages: messages,
      modelSnapshot: modelSnapshot,
      workspace: workspace,
      systemPromptSnapshot: systemPromptSnapshot,
      chatId: chatId,
      title: title,
    );
  }
}

class _DelayedChatLibraryService extends ChatLibraryService {
  _DelayedChatLibraryService(ChatLibraryRepository repository)
    : super(repository: repository);

  final savedSnapshots = <List<Bubble>>[];
  var saveAttempts = 0;
  Completer<void>? _saveStarted;
  Completer<void>? _saveRelease;

  Future<void> get saveStarted => _saveStarted!.future;

  void delayNextSave() {
    _saveStarted = Completer<void>();
    _saveRelease = Completer<void>();
  }

  void releaseSave() => _saveRelease!.complete();

  @override
  Future<SavedChat> saveChatSnapshot({
    required List<Bubble> messages,
    required ModelConfigurationSnapshot? modelSnapshot,
    required WorkspaceAttachment? workspace,
    required SystemPromptSnapshot? systemPromptSnapshot,
    String? chatId,
    String? title,
  }) async {
    saveAttempts++;
    savedSnapshots.add(List<Bubble>.of(messages));
    final started = _saveStarted;
    final release = _saveRelease;
    if (started != null && release != null) {
      started.complete();
      await release.future;
      _saveStarted = null;
      _saveRelease = null;
    }
    return super.saveChatSnapshot(
      messages: messages,
      modelSnapshot: modelSnapshot,
      workspace: workspace,
      systemPromptSnapshot: systemPromptSnapshot,
      chatId: chatId,
      title: title,
    );
  }
}
