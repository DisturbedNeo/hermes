import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/job_panel.dart';
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

  testWidgets(
    'expanded panel renders artifact tiles without ListTile asserts',
    (tester) async {
      chat.activeJob = _jobWithArtifact();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: JobPanel(
                chat: chat,
                expanded: true,
                onToggleExpanded: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('.agent/jobs/job_test/output.md'), findsOneWidget);
    },
  );
}

JobDocument _jobWithArtifact() {
  final now = DateTime(2024, 1, 1);
  return JobDocument(
    id: 'job_test',
    title: 'Test job',
    originalPrompt: 'Create an artifact.',
    goal: 'Create an artifact.',
    constraints: const [],
    successCriteria: const [],
    steps: const [
      JobStep(
        id: 'write',
        title: 'Write artifact',
        objective: 'Write the output artifact.',
        instructions: [],
        mayEditFiles: false,
        artifacts: [
          JobArtifact(
            path: '.agent/jobs/job_test/output.md',
            description: 'Generated output',
          ),
        ],
        status: JobStepStatus.completed,
      ),
    ],
    status: JobStatus.completed,
    currentStepId: null,
    memorySummary: '',
    runs: [
      JobRun(
        runId: 'run_test',
        stepId: 'write',
        status: JobRunStatus.completed,
        summary: 'Wrote the artifact.',
        memoryUpdate: '',
        toolCalls: [],
        artifacts: [],
        startedAt: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}
