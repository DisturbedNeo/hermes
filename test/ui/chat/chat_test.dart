import 'package:flutter/material.dart';
import 'package:hermes/app/test_factories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/infrastructure/chat_library_repository.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';
import 'package:hermes/features/model/infrastructure/llama_server_manager.dart';
import 'package:hermes/features/model/infrastructure/model_catalog_service.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/features/chat/infrastructure/system_prompt_library_repository.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/platform/workspace_service.dart';
import 'package:hermes/features/chat/presentation/chat/chat.dart';
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
    final taskController = createTestTaskController(
      toolService: toolService,
      sandbox: sandbox,
    );
    final projectApplication = createTestProjectApplication(
      taskController: taskController,
    );
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
      toolProtocol: ToolProtocolAdapter(registry: toolService),
      toolExecution: ChatToolExecutionService(
        protocol: ToolProtocolAdapter(registry: toolService),
      ),
      taskQueries: taskController,
      taskSessions: taskController,
      taskPresentation: taskController,
      panelProtocol: const ChatPanelProtocolAdapter(),
      taskPlanning: createTestTaskWorkflow(taskController),
      taskExecution: createTestTaskWorkflow(taskController),
      taskRecovery: createTestTaskWorkflow(taskController),
      projectQueries: projectApplication,
      projectSessions: projectApplication,
      projectPlanning: createTestProjectWorkflow(projectApplication),
      projectCommands: createTestProjectWorkflow(projectApplication),
      projectExecution: createTestProjectWorkflow(projectApplication),
      projectRecovery: createTestProjectWorkflow(projectApplication),
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
      modelCatalog: ModelCatalogService(preferences: preferences),
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
