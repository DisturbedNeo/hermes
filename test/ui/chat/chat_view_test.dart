import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/scroll.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/chat_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late SystemPromptLibraryService promptLibrary;
  late ToolService toolService;
  late TaskService taskService;
  late WorkspaceService workspaceService;
  late ChatTabsService tabs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    tempDir = await Directory.systemTemp.createTemp('hermes_chat_view_test_');
    preferences = PreferencesService();
    await preferences.setDiagnosticsVisibility(DiagnosticsVisibility.compact);

    final sandbox = WorkspaceSandbox();
    toolService = ToolService(workspaceSandbox: sandbox);
    taskService = TaskService(toolService: toolService, sandbox: sandbox);
    workspaceService = WorkspaceService(sandbox: sandbox);
    chatLibrary = ChatLibraryService(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    promptLibrary = SystemPromptLibraryService(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    tabs = ChatTabsService(
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      toolService: toolService,
      taskService: taskService,
      projectService: ProjectService(taskService: taskService),
      workspaceService: workspaceService,
      preferencesService: preferences,
    );
  });

  tearDown(() async {
    await tabs.dispose();
    await promptLibrary.dispose();
    await chatLibrary.dispose();
    workspaceService.dispose();
    preferences.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('lays out in the reported short viewport', (tester) async {
    await _setViewport(tester, const Size(190, 286));
    final chat = tabs.activeChat!;
    chat.workspace = WorkspaceAttachment(
      rootPath: tempDir.path,
      displayName: 'workspace',
      lastOpenedAt: DateTime(2024, 1, 1),
    );
    chat.insertMessage('A short user message.', MessageRole.user);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the footer scrollable in a very short viewport', (
    tester,
  ) async {
    await _setViewport(tester, const Size(240, 220));
    final chat = tabs.activeChat!;
    chat.insertMessage('A short user message.', MessageRole.user);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at unrenderable chat view sizes', (
    tester,
  ) async {
    final chat = tabs.activeChat!;
    chat.insertMessage('A short user message.', MessageRole.user);

    await tester.pumpWidget(
      _chatViewBoxApp(tabs, preferences, toolService, width: 190, height: 1),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _chatViewBoxApp(tabs, preferences, toolService, width: 1, height: 1),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _chatViewBoxApp(tabs, preferences, toolService, width: 0, height: 0),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll to bottom button returns to the latest message', (
    tester,
  ) async {
    await _setViewport(tester, const Size(420, 640));
    final chat = tabs.activeChat!;
    chat.messageStore.setMessages([
      chat.systemPrompt,
      for (var i = 0; i < 40; i++)
        Bubble(
          id: 'm$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: 'Chat message $i',
          reasoning: '',
        ),
    ]);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();

    expect(_isVisible(tester, find.byKey(const ValueKey('message_m39'))), true);

    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller!;
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(find.text('Scroll to bottom'), findsOneWidget);
    expect(
      controller.position.pixels,
      lessThan(controller.position.maxScrollExtent),
    );

    await tester.tap(find.text('Scroll to bottom'));
    await tester.pumpAndSettle();

    expect(_isVisible(tester, find.byKey(const ValueKey('message_m39'))), true);
    expect(find.text('Scroll to bottom'), findsNothing);
  });

  testWidgets('follows streaming growth without waiting for a quiet period', (
    tester,
  ) async {
    await _setViewport(tester, const Size(420, 640));
    final chat = tabs.activeChat!;
    chat.messageStore.setMessages([
      chat.systemPrompt,
      for (var i = 0; i < 30; i++)
        Bubble(
          id: 'stream-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: 'Chat message $i',
          reasoning: '',
        ),
    ]);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller!;
    for (var i = 1; i <= 5; i++) {
      final latest = chat.messageStore.last;
      chat.messageStore.upsert(
        latest.copyWith(text: List.filled(i * 4, 'streaming line').join('\n')),
      );
      await tester.pump();
      expect(controller.position.pixels, controller.position.maxScrollExtent);
    }
  });

  testWidgets('new messages do not take over while reading older content', (
    tester,
  ) async {
    await _setViewport(tester, const Size(420, 640));
    final chat = tabs.activeChat!;
    chat.messageStore.setMessages([
      chat.systemPrompt,
      for (var i = 0; i < 40; i++)
        Bubble(
          id: 'paused-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: 'Chat message $i',
          reasoning: '',
        ),
    ]);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 220));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    final readingOffset = controller.position.pixels;
    chat.insertMessage('A newly submitted prompt', MessageRole.user);
    await tester.pump();

    expect(controller.position.pixels, readingOffset);
    expect(find.text('Scroll to bottom'), findsOneWidget);
  });

  testWidgets('restores each tab reading position for the session', (
    tester,
  ) async {
    await _setViewport(tester, const Size(420, 640));
    final firstChat = tabs.activeChat!;
    firstChat.messageStore.setMessages([
      firstChat.systemPrompt,
      for (var i = 0; i < 40; i++)
        Bubble(
          id: 'tab-a-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: 'First tab message $i',
          reasoning: '',
        ),
    ]);

    await tester.pumpWidget(_activeChatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();
    final firstController =
        tester.widget<ListView>(find.byType(ListView)).controller!
            as ChatScrollController;
    final firstOffset = firstController.position.pixels;
    expect(firstController.mode, ChatScrollMode.paused);

    tabs.newTab();
    await tester.pumpAndSettle();
    await tabs.selectTab(firstChat.tabId);
    await tester.pumpAndSettle();

    final restoredController =
        tester.widget<ListView>(find.byType(ListView)).controller!
            as ChatScrollController;
    final restored = restoredController.position.pixels;
    expect(
      restored,
      closeTo(firstOffset, 0.01),
      reason:
          'mode=${restoredController.mode}, max=${restoredController.position.maxScrollExtent}',
    );
    expect(find.text('Scroll to bottom'), findsOneWidget);

    final secondChat = tabs.tabs.firstWhere(
      (chat) => chat.tabId != firstChat.tabId,
    );
    await tabs.closeTab(secondChat.tabId);
  });

  testWidgets('wholesale history replacement resets the same tab to latest', (
    tester,
  ) async {
    await _setViewport(tester, const Size(420, 640));
    final chat = tabs.activeChat!;
    chat.messageStore.setMessages([
      chat.systemPrompt,
      for (var i = 0; i < 40; i++)
        Bubble(
          id: 'old-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: 'Old message $i',
          reasoning: '',
        ),
    ]);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(find.text('Scroll to bottom'), findsOneWidget);

    await tester.runAsync(chat.newChat);
    chat.messageStore.setMessages([
      chat.systemPrompt,
      for (var i = 0; i < 40; i++)
        Bubble(
          id: 'new-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          text: 'New message $i',
          reasoning: '',
        ),
    ]);
    await tester.pump();
    await tester.pump();

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.position.pixels, controller.position.maxScrollExtent);
    expect(
      _isVisible(tester, find.byKey(const ValueKey('message_new-39'))),
      true,
    );
    expect(find.text('Scroll to bottom'), findsNothing);
  });

  testWidgets('shows creation timestamp under message bubbles', (tester) async {
    await _setViewport(tester, const Size(420, 640));
    final chat = tabs.activeChat!;
    chat.messageStore.setMessages([
      chat.systemPrompt,
      Bubble(
        id: 'timestamped',
        role: MessageRole.user,
        text: 'Timed message',
        reasoning: '',
        createdAt: DateTime(2026, 5, 9, 4, 7),
      ),
    ]);

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();

    expect(find.text('09/05/26 04:07'), findsOneWidget);
  });

  testWidgets('Ctrl slash focuses the composer', (tester) async {
    await _setViewport(tester, const Size(420, 640));
    final chat = tabs.activeChat!;
    chat.serverManager.handle.value = LlamaServerHandle(
      process: _FakeProcess(),
      stdoutSub: const Stream<List<int>>.empty().listen((_) {}),
      stderrSub: const Stream<List<int>>.empty().listen((_) {}),
    );

    await tester.pumpWidget(_chatViewApp(tabs, preferences, toolService));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
    chat.serverManager.handle.value = null;
  });
}

Widget _chatViewApp(
  ChatTabsService tabs,
  PreferencesService preferences,
  ToolService toolService,
) {
  return MaterialApp(
    home: Scaffold(
      body: ChatView(
        chat: tabs.activeChat!,
        preferencesService: preferences,
        toolService: toolService,
        onOpenWorkspace: () {},
      ),
    ),
  );
}

Widget _activeChatViewApp(
  ChatTabsService tabs,
  PreferencesService preferences,
  ToolService toolService,
) {
  return MaterialApp(
    home: Scaffold(
      body: AnimatedBuilder(
        animation: tabs,
        builder: (context, _) {
          final chat = tabs.activeChat;
          if (chat == null) return const SizedBox.shrink();
          return ChatView(
            key: ValueKey('chat_${chat.tabId}'),
            chat: chat,
            preferencesService: preferences,
            toolService: toolService,
            onOpenWorkspace: () {},
          );
        },
      ),
    ),
  );
}

Widget _chatViewBoxApp(
  ChatTabsService tabs,
  PreferencesService preferences,
  ToolService toolService, {
  required double width,
  required double height,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: ChatView(
          chat: tabs.activeChat!,
          preferencesService: preferences,
          toolService: toolService,
          onOpenWorkspace: () {},
        ),
      ),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

bool _isVisible(WidgetTester tester, Finder finder) {
  final element = finder.evaluate().firstOrNull;
  if (element == null) return false;

  final rect = tester.getRect(find.byWidget(element.widget));
  final screenRect = Offset.zero & tester.view.physicalSize;
  return rect.overlaps(screenRect);
}

class _FakeProcess implements Process {
  final _exitCode = Completer<int>();
  final _stdinController = StreamController<List<int>>();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCode.isCompleted) _exitCode.complete(0);
    unawaited(_stdinController.close());
    return true;
  }
}
