import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ChatLibraryService chatLibrary;
  late SystemPromptLibraryService promptLibrary;
  late ChatTabsService tabs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await serviceProvider.dispose();

    preferences = PreferencesService();
    final toolService = ToolService();
    final workspaceService = WorkspaceService();
    final jobService = JobService(toolService: toolService);
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
      jobService: jobService,
      workspaceService: workspaceService,
      preferencesService: preferences,
    );

    serviceProvider.registerSingleton<PreferencesService>(preferences);
    serviceProvider.registerSingleton<ToolService>(toolService);
    serviceProvider.registerSingleton<WorkspaceService>(workspaceService);
    serviceProvider.registerSingleton<ChatLibraryService>(chatLibrary);
    serviceProvider.registerSingleton<SystemPromptLibraryService>(
      promptLibrary,
    );
    serviceProvider.registerSingleton<ChatTabsService>(tabs);
  });

  tearDown(() async {
    await serviceProvider.dispose();
  });

  testWidgets('lays out when the scaffold body is smaller than the tab strip', (
    tester,
  ) async {
    await _setViewport(tester, const Size(190, 74));

    await tester.pumpWidget(const MaterialApp(home: Chat()));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at pathological chat screen sizes', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1, 1));

    await tester.pumpWidget(const MaterialApp(home: Chat()));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await _setViewport(tester, const Size(0, 0));
    await tester.pumpWidget(const MaterialApp(home: Chat()));
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
