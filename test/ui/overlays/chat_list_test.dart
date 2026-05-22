import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/overlays/chat_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late _FakeChatLibraryService chatLibrary;
  late SystemPromptLibraryService promptLibrary;
  late ChatTabsService tabs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await serviceProvider.dispose();

    preferences = PreferencesService();
    final toolService = ToolService();
    chatLibrary = _FakeChatLibraryService(preferencesService: preferences);
    promptLibrary = SystemPromptLibraryService(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    tabs = ChatTabsService(
      chatLibrary: chatLibrary,
      systemPromptLibrary: promptLibrary,
      toolService: toolService,
      jobService: JobService(toolService: toolService),
      workspaceService: WorkspaceService(),
      preferencesService: preferences,
    );

    serviceProvider.registerSingleton<ChatLibraryService>(chatLibrary);
    serviceProvider.registerSingleton<ChatTabsService>(tabs);
  });

  tearDown(() async {
    await serviceProvider.dispose();
    await promptLibrary.dispose();
  });

  testWidgets('lays out in the reported short chat list panel', (tester) async {
    await tester.pumpWidget(_panelApp(width: 412, height: 99));
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at pathological panel sizes', (tester) async {
    await tester.pumpWidget(_panelApp(width: 1, height: 1));
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_panelApp(width: 0, height: 0));
    await _pumpAsyncWork(tester);

    expect(tester.takeException(), isNull);
  });
}

Widget _panelApp({required double width, required double height}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: ChatList(
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
  _FakeChatLibraryService({required super.preferencesService})
    : super(databasePath: ':memory:');

  List<SavedChat> chats = const [];

  @override
  Future<List<SavedChat>> listChats() async => chats;

  @override
  Future<List<SavedChat>> searchChats(String query) async => chats;
}
