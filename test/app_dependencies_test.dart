import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/app_dependencies.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataDirectory;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('hermes_app_data_');
    SharedPreferences.setMockInitialValues({
      'data_location_path': dataDirectory.path,
    });
  });

  tearDown(() async {
    if (await dataDirectory.exists()) {
      await dataDirectory.delete(recursive: true);
    }
  });

  test('creates one typed graph with a shared workspace sandbox', () async {
    final dependencies = AppDependencies.create();
    final root = await Directory.systemTemp.createTemp(
      'hermes_app_dependencies_',
    );
    addTearDown(() async {
      await dependencies.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    expect(
      identical(
        dependencies.workspaceSandbox,
        dependencies.workspaceService.sandbox,
      ),
      isTrue,
    );

    final result = await dependencies.toolService.execute(
      toolId: 'list_directory',
      argumentsJson: '{"path":"."}',
      context: WorkspaceToolContext(
        workspace: WorkspaceAttachment.fromPath(root.path),
      ),
    );
    expect(result, contains('entries'));
  });

  test('dispose is awaited and idempotent', () async {
    final dependencies = AppDependencies.create();

    final first = dependencies.dispose();
    final second = dependencies.dispose();

    expect(identical(first, second), isTrue);
    await first;
    await dependencies.dispose();
  });

  testWidgets('root MultiProvider exposes stable service instances', (
    tester,
  ) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final preferences = context.read<PreferencesService>();
    final theme = context.read<ThemeManager>();
    final tools = context.read<ToolService>();
    final tabs = context.read<ChatTabsService>();

    expect(identical(preferences, context.read<PreferencesService>()), isTrue);
    expect(identical(theme, context.read<ThemeManager>()), isTrue);
    expect(identical(tools, context.read<ToolService>()), isTrue);
    expect(identical(tabs, context.read<ChatTabsService>()), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('exit prompt can cancel or save all new chats', (tester) async {
    var exitRequests = 0;
    AppExitType? requestedExitType;
    await tester.pumpWidget(
      App(
        exitApplication: (type) async {
          requestedExitType = type;
          exitRequests++;
          return AppExitResponse.exit;
        },
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final chat = context.read<ChatTabsService>().activeChat!;
    chat.messageStore.upsert(_userMessage('new-chat', 'Keep this chat'));

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await _pumpAsyncUi(tester);
    expect(find.text('Save new chats before exiting?'), findsOneWidget);
    expect(find.text('Discard new chats'), findsOneWidget);
    expect(find.text('Save all and exit'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _pumpAsyncUi(tester);
    expect(exitRequests, 0);
    expect(chat.currentChatId, isNull);

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await _pumpAsyncUi(tester);
    await tester.tap(find.text('Save all and exit'));
    await _pumpAsyncUi(tester);

    expect(chat.currentChatId, isNotNull);
    expect(exitRequests, 1);
    expect(requestedExitType, AppExitType.required);
  });

  testWidgets('exit prompt can discard only new chats', (tester) async {
    var exitRequests = 0;
    await tester.pumpWidget(
      App(
        exitApplication: (_) async {
          exitRequests++;
          return AppExitResponse.exit;
        },
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final chat = context.read<ChatTabsService>().activeChat!;
    chat.messageStore.upsert(_userMessage('discard-chat', 'Discard this chat'));

    await tester.binding.handleRequestAppExit();
    await _pumpAsyncUi(tester);
    await tester.tap(find.text('Discard new chats'));
    await _pumpAsyncUi(tester);

    expect(chat.currentChatId, isNull);
    expect(exitRequests, 1);
  });

  testWidgets('blank new tabs exit without prompting', (tester) async {
    var preparationAttempts = 0;
    var exitRequests = 0;
    await tester.pumpWidget(
      App(
        prepareForExit: (_) async {
          preparationAttempts++;
        },
        exitApplication: (_) async {
          exitRequests++;
          return AppExitResponse.exit;
        },
      ),
    );
    await tester.pump();

    await tester.binding.handleRequestAppExit();
    await _pumpAsyncUi(tester);

    expect(find.text('Save new chats before exiting?'), findsNothing);
    expect(preparationAttempts, 1);
    expect(exitRequests, 1);
  });

  testWidgets('failed exit save can retry successfully', (tester) async {
    var exitRequests = 0;
    var preparationAttempts = 0;
    var failPreparation = true;
    await tester.pumpWidget(
      App(
        prepareForExit: (_) async {
          preparationAttempts++;
          if (failPreparation) throw StateError('Injected save failure');
        },
        exitApplication: (_) async {
          exitRequests++;
          return AppExitResponse.exit;
        },
      ),
    );
    await tester.pump();

    await tester.binding.handleRequestAppExit();
    await _pumpAsyncUi(tester);
    expect(find.text('Could not save chats'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Exit without saving'), findsOneWidget);

    failPreparation = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await _pumpAsyncUi(tester);
    expect(preparationAttempts, 2);
    expect(exitRequests, 1);
  });

  testWidgets('failed exit save can cancel or explicitly discard', (
    tester,
  ) async {
    var exitRequests = 0;
    await tester.pumpWidget(
      App(
        prepareForExit: (_) async {
          throw StateError('Injected save failure');
        },
        exitApplication: (_) async {
          exitRequests++;
          return AppExitResponse.exit;
        },
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final tabs = context.read<ChatTabsService>();

    await tester.binding.handleRequestAppExit();
    await _pumpAsyncUi(tester);
    expect(find.text('Could not save chats'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _pumpAsyncUi(tester);
    expect(tabs.tabs, hasLength(1));
    expect(exitRequests, 0);

    await tester.binding.handleRequestAppExit();
    await _pumpAsyncUi(tester);
    await tester.tap(find.text('Exit without saving'));
    await _pumpAsyncUi(tester);
    expect(exitRequests, 1);
  });
}

Bubble _userMessage(String id, String text) => Bubble(
  id: id,
  role: MessageRole.user,
  text: text,
  reasoning: '',
  createdAt: DateTime.now(),
);

Future<void> _pumpAsyncUi(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
