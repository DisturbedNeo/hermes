import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late LlamaServerManager serverManager;
  late ToolService toolService;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await serviceProvider.dispose();

    toolService = ToolService();
    serviceProvider.registerSingleton<ToolService>(toolService);

    preferences = PreferencesService();
    chatLibrary = ChatLibraryService(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    serverManager = LlamaServerManager();
    chat = ChatService(
      serverManager: serverManager,
      toolService: toolService,
      chatLibrary: chatLibrary,
      workspaceService: WorkspaceService(),
      preferencesService: preferences,
    );
  });

  tearDown(() async {
    await chat.dispose();
    await serverManager.dispose();
    await chatLibrary.dispose();
    await serviceProvider.dispose();
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
            child: Composer(chat: chat, enabled: true),
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
            child: Composer(chat: chat, enabled: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Project'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
