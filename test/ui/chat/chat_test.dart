import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/chat_application/chat_library_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late SystemPromptLibraryService promptLibrary;
  late ChatWorkspaceController tabs;
  late ToolService toolService;
  late WorkspaceService workspaceService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    preferences = PreferencesService();
    final sandbox = WorkspaceSandbox();
    toolService = ToolService(workspaceSandbox: sandbox);
    workspaceService = WorkspaceService(sandbox: sandbox);
    final taskController = TaskController(toolService: toolService, sandbox: sandbox);
    final chatLibraryRepository = ChatLibraryRepository(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
    final repository = SystemPromptLibraryRepository(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    promptLibrary = SystemPromptLibraryService(repository: repository);
    tabs = ChatWorkspaceController(
      serverManager: LlamaServerManager(),
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      toolService: toolService,
      taskController: taskController,
      projectApplication: ProjectApplication(taskController: taskController),
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
  });

  Widget app() => MaterialApp(
    home: Chat(
      tabs: tabs,
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      workspaceService: workspaceService,
      preferencesService: preferences,
      toolService: toolService,
    ),
  );

  testWidgets('lays out when the scaffold body is smaller than the tab strip', (
    tester,
  ) async {
    await _setViewport(tester, const Size(190, 74));

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at pathological chat screen sizes', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1, 1));

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await _setViewport(tester, const Size(0, 0));
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
