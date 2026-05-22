import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/overlays/workspace_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWorkspaceService workspaceService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await serviceProvider.dispose();
    workspaceService = _FakeWorkspaceService();
    serviceProvider.registerSingleton<WorkspaceService>(workspaceService);
  });

  tearDown(() async {
    await serviceProvider.dispose();
  });

  testWidgets('lays out in the reported short workspace panel', (tester) async {
    workspaceService.recent = [
      WorkspaceAttachment(
        rootPath: '/tmp/hermes/a/really/long/workspace/path',
        displayName: 'Workspace with a long display name',
        lastOpenedAt: DateTime(2024, 1, 1),
      ),
    ];

    await tester.pumpWidget(_panelApp(width: 268, height: 109));
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
        child: WorkspacePanel(chat: null, onSelectWorkspace: () {}),
      ),
    ),
  );
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

class _FakeWorkspaceService extends WorkspaceService {
  List<WorkspaceAttachment> recent = const [];

  @override
  Future<List<WorkspaceAttachment>> recentWorkspaces() async => recent;
}
