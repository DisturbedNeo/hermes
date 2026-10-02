import 'package:flutter/material.dart';
import 'package:hermes/app/test_factories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/infrastructure/chat_library_repository.dart';
import 'package:hermes/features/chat/application/chat_controller.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';
import 'package:hermes/features/model/infrastructure/llama_server_manager.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/platform/workspace_service.dart';
import 'package:hermes/features/chat/presentation/chat/composer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late LlamaServerManager serverManager;
  late ToolService toolService;
  late ChatController chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    final sandbox = WorkspaceSandbox();
    toolService = ToolService(workspaceSandbox: sandbox);
    final taskController = createTestTaskController(
      toolService: toolService,
      sandbox: sandbox,
    );

    preferences = PreferencesService();
    final chatLibraryRepository = ChatLibraryRepository(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
    serverManager = LlamaServerManager();
    final projectApplication = createTestProjectApplication(
      taskController: taskController,
    );
    chat = ChatController(
      serverManager: serverManager,
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
      chatLibrary: chatLibrary,
      workspaceService: WorkspaceService(sandbox: sandbox),
      preferencesService: preferences,
    );
  });

  tearDown(() async {
    await chat.dispose();
    await serverManager.dispose();
    await chatLibrary.dispose();
  });

  testWidgets('lays out the role dropdown in a narrow composer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Composer(
              chat: chat,
              toolService: toolService,
              enabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(DropdownButtonFormField<MessageRole>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Assistant').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes project execution mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Composer(
              chat: chat,
              toolService: toolService,
              enabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Project'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
