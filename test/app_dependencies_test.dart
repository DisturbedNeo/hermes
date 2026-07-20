import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/app_dependencies.dart';
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
}
