import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
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
  late JobService jobService;
  late WorkspaceService workspaceService;
  late ChatTabsService tabs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await serviceProvider.dispose();

    tempDir = await Directory.systemTemp.createTemp('hermes_chat_view_test_');
    preferences = PreferencesService();
    await preferences.setDiagnosticsVisibility(DiagnosticsVisibility.compact);

    toolService = ToolService();
    jobService = JobService(toolService: toolService);
    workspaceService = WorkspaceService();
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
    serviceProvider.registerSingleton<ChatTabsService>(tabs);
  });

  tearDown(() async {
    await serviceProvider.dispose();
    await promptLibrary.dispose();
    await chatLibrary.dispose();
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

    await tester.pumpWidget(_chatViewApp(tabs));
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

    await tester.pumpWidget(_chatViewApp(tabs));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at unrenderable chat view sizes', (
    tester,
  ) async {
    final chat = tabs.activeChat!;
    chat.insertMessage('A short user message.', MessageRole.user);

    await tester.pumpWidget(_chatViewBoxApp(tabs, width: 190, height: 1));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_chatViewBoxApp(tabs, width: 1, height: 1));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_chatViewBoxApp(tabs, width: 0, height: 0));
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

    await tester.pumpWidget(_chatViewApp(tabs));
    await tester.pumpAndSettle();

    expect(_isVisible(tester, find.byKey(const ValueKey('message_m39'))), true);

    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(find.text('Scroll to bottom'), findsOneWidget);
    expect(
      _isVisible(tester, find.byKey(const ValueKey('message_m39'))),
      false,
    );

    await tester.tap(find.text('Scroll to bottom'));
    await tester.pumpAndSettle();

    expect(_isVisible(tester, find.byKey(const ValueKey('message_m39'))), true);
    expect(find.text('Scroll to bottom'), findsNothing);
  });
}

Widget _chatViewApp(ChatTabsService tabs) {
  return MaterialApp(
    home: Scaffold(
      body: ChatView(chat: tabs.activeChat!, onOpenWorkspace: () {}),
    ),
  );
}

Widget _chatViewBoxApp(
  ChatTabsService tabs, {
  required double width,
  required double height,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: ChatView(chat: tabs.activeChat!, onOpenWorkspace: () {}),
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
