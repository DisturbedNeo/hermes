import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/task_panel.dart';
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

    final sandbox = WorkspaceSandbox();
    toolService = ToolService(workspaceSandbox: sandbox);
    final taskService = TaskService(toolService: toolService, sandbox: sandbox);

    preferences = PreferencesService();
    final chatLibraryRepository = ChatLibraryRepository(
      preferencesService: preferences,
      databasePath: ':memory:',
    );
    chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
    serverManager = LlamaServerManager();
    chat = ChatService(
      serverManager: serverManager,
      toolService: toolService,
      taskService: taskService,
      projectService: ProjectService(taskService: taskService),
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

  testWidgets(
    'expanded panel renders artifact tiles without ListTile asserts',
    (tester) async {
      chat.activeTask = _taskWithArtifact();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: TaskPanel(
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
      expect(find.text('.agent/tasks/task_test/output.md'), findsOneWidget);
    },
  );

  testWidgets('expanded panel renders project state', (tester) async {
    chat.activeProject = _projectWithTask();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 640,
            child: TaskPanel(
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
    expect(find.text('Project task'), findsOneWidget);
    expect(find.text('Recent Decisions'), findsOneWidget);
  });
}

TaskDocument _taskWithArtifact() {
  final now = DateTime(2024, 1, 1);
  return TaskDocument(
    id: 'task_test',
    title: 'Test task',
    originalPrompt: 'Create an artifact.',
    goal: 'Create an artifact.',
    constraints: const [],
    successCriteria: const [],
    steps: const [
      TaskStep(
        id: 'write',
        title: 'Write artifact',
        objective: 'Write the output artifact.',
        instructions: [],
        mayEditFiles: false,
        artifacts: [
          TaskArtifact(
            path: '.agent/tasks/task_test/output.md',
            description: 'Generated output',
          ),
        ],
        status: TaskStepStatus.completed,
      ),
    ],
    status: TaskStatus.completed,
    currentStepId: null,
    memorySummary: '',
    runs: [
      TaskRun(
        runId: 'run_test',
        stepId: 'write',
        status: TaskRunStatus.completed,
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

ProjectDocument _projectWithTask() {
  final now = DateTime(2024, 1, 1);
  return ProjectDocument(
    id: 'project_test',
    title: 'Test project',
    originalPrompt: 'Build project.',
    goal: 'Build project.',
    constraints: const [],
    successCriteria: const [],
    status: ProjectStatus.paused,
    activeTaskId: null,
    memorySummary: 'Project memory.',
    completionSummary: '',
    tasks: [
      ProjectTaskRef(
        taskId: 'task_test',
        title: 'Project task',
        status: TaskStatus.completed,
        summary: 'Finished.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    decisions: [
      ProjectDecisionRecord(
        id: 'decision_test',
        decision: ProjectDecisionType.createTask,
        summary: 'Created task.',
        memoryUpdate: '',
        taskId: 'task_test',
        taskTitle: 'Project task',
        taskPrompt: 'Do work.',
        createdAt: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}
