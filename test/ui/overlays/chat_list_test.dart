import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/overlays/chat_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late _FakeChatLibraryService chatLibrary;
  late SystemPromptLibraryRepository promptLibraryRepository;
  late SystemPromptLibraryService promptLibrary;
  late ChatTabsService tabs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    preferences = PreferencesService();
    final sandbox = WorkspaceSandbox();
    final toolService = ToolService(workspaceSandbox: sandbox);
    final taskService = TaskService(toolService: toolService, sandbox: sandbox);
    chatLibrary = _FakeChatLibraryService();
    promptLibraryRepository = SystemPromptLibraryRepository(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    promptLibrary = SystemPromptLibraryService(
      repository: promptLibraryRepository,
    );
    tabs = ChatTabsService(
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      toolService: toolService,
      taskService: taskService,
      projectService: ProjectService(taskService: taskService),
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
  });

  tearDown(() async {
    await tabs.dispose();
    await chatLibrary.dispose();
    await promptLibrary.dispose();
    preferences.dispose();
  });

  testWidgets('lays out in the reported short chat list panel', (tester) async {
    await tester.pumpWidget(
      _panelApp(width: 412, height: 99, tabs: tabs, library: chatLibrary),
    );
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at pathological panel sizes', (tester) async {
    await tester.pumpWidget(
      _panelApp(width: 1, height: 1, tabs: tabs, library: chatLibrary),
    );
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _panelApp(width: 0, height: 0, tabs: tabs, library: chatLibrary),
    );
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);
  });
}

Widget _panelApp({
  required double width,
  required double height,
  required ChatTabsService tabs,
  required ChatLibraryService library,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: ChatList(
          tabs: tabs,
          library: library,
          onOpenChat: (_) {},
          onOpenChatInNewTab: (_) {},
          onNewChat: () {},
        ),
      ),
    ),
  );
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _FakeChatLibraryService extends ChatLibraryService {
  _FakeChatLibraryService()
    : super(repository: ChatLibraryRepository(
        preferencesService: PreferencesService(),
        databasePath: ':memory:',
      ));

  List<SavedChat> chats = const [];

  @override
  Future<List<SavedChat>> listChats() async => chats;

  @override
  Future<List<SavedChat>> searchChats(String query) async => chats;
}
