import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/task_system/task_storage_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatService system prompts and tasks', () {
    late Directory tempDir;
    late ChatLibraryService chatLibrary;
    late PreferencesService preferences;
    late LlamaServerManager serverManager;
    late ChatService chat;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('hermes_chat_service_');
      preferences = PreferencesService();
      chatLibrary = ChatLibraryService(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      );
      serverManager = LlamaServerManager();
      final sandbox = WorkspaceSandbox();
      final toolService = ToolService(workspaceSandbox: sandbox);
      final taskService = TaskService(
        toolService: toolService,
        sandbox: sandbox,
      );
      chat = ChatService(
        serverManager: serverManager,
        toolService: toolService,
        taskService: taskService,
        projectService: ProjectService(taskService: taskService),
        chatLibrary: chatLibrary,
        workspaceService: WorkspaceService(sandbox: sandbox),
        preferencesService: preferences,
        initialSystemPromptSnapshot: const SystemPromptSnapshot(
          id: 'prompt-1',
          name: 'Reviewer',
          text: 'Review code carefully.',
        ),
      );
    });

    tearDown(() async {
      await chat.dispose();
      await serverManager.dispose();
      await chatLibrary.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('composes selected prompt with workspace instructions', () async {
      expect(chat.messageStore.first.text, 'Review code carefully.');

      await chat.attachWorkspace(tempDir.path);

      final systemText = chat.messageStore.first.text;
      expect(systemText, startsWith('Review code carefully.'));
      expect(systemText, contains('This chat has an attached workspace.'));
      expect(systemText, contains(tempDir.path));
    });

    test('locks prompt changes after meaningful content or save', () async {
      expect(chat.isSystemPromptLocked, isFalse);

      chat.insertMessage('Hello', MessageRole.user);

      expect(chat.isSystemPromptLocked, isTrue);
      expect(
        () => chat.setSystemPromptSnapshot(
          const SystemPromptSnapshot(
            id: 'prompt-2',
            name: 'Architect',
            text: 'Design APIs carefully.',
          ),
        ),
        throwsStateError,
      );
    });

    test('assembles current user request for prompt payloads', () {
      final now = DateTime(2026);
      final module = PromptModule(
        id: 'request-aware',
        name: 'Request aware',
        category: 'Context',
        content: 'Current task is {{currentRequest}}',
        priority: 10,
        isBuiltIn: false,
        requiredModuleIds: const [],
        conflictingModuleIds: const [],
        createdAt: now,
        updatedAt: now,
      );
      final preset = PromptPreset(
        id: 'preset',
        name: 'Request preset',
        baseModuleIds: const ['request-aware'],
        optionalModuleIds: const [],
        customInstructions: '',
        legacyFullPrompt: null,
        isBuiltIn: false,
        createdAt: now,
        updatedAt: now,
      );

      chat.setSystemPromptSnapshot(
        SystemPromptSnapshot(
          id: preset.id,
          name: preset.name,
          text: '',
          preset: preset,
          modules: [module],
          selectedModuleIds: const ['request-aware'],
        ),
      );

      expect(
        chat.buildSystemPromptForTesting(
          currentUserRequest: 'Review this diff',
        ),
        contains('Current task is Review this diff'),
      );
    });

    test('supports /refine without creating a task', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode({
          'title': 'Refined task',
          'goal': 'Build the reporting screen',
          'successCriteria': ['Clear plan'],
          'constraints': ['Stay in workspace'],
          'assumptions': ['Flutter app'],
        }),
      ]);

      await chat.send('/refine Build the reporting screen');

      expect(chat.activeTask, isNull);
      expect(chat.messageStore.messages.last.text, contains('Refined task'));
      expect(chat.messageStore.messages.last.text, contains('Goal:'));
    });

    test('supports /plan command without running steps', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Planned task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      expect(chat.activeTask?.title, 'Planned task');
      expect(chat.activeTask?.runs, isEmpty);
      expect(chat.activeTask?.status, TaskStatus.paused);
      expect(chat.taskModelOutputTitle, 'Task Creation Model Output');
      expect(chat.taskModelOutputText, contains('Task Planner'));
    });

    test('supports /task command by creating and running steps', () async {
      serverManager.chatClient = _QueueCompletionClient([
        _finaliseTaskResponse(_planJson(title: 'Runnable task')),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Step complete.',
            'memoryUpdate': 'Work finished.',
          }),
        ),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/task Build the reporting screen');

      expect(chat.activeTask?.status, TaskStatus.completed);
      expect(chat.activeTask?.runs.single.summary, 'Step complete.');
    });

    test(
      'supports /project command by creating tasks until complete',
      () async {
        serverManager.chatClient = _QueueCompletionClient([
          _finaliseProjectResponse({
            'title': 'Build screen',
            'refinedGoal': 'Build the reporting screen',
            'successCriteria': ['Screen is built.'],
            'constraints': ['Stay in workspace.'],
            'knownFacts': [],
            'openQuestions': [],
            'backlog': [_projectTaskJson()],
          }),
          _finaliseTaskResponse(_projectPlanJson(title: 'Project task')),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Project task complete.',
              'memoryUpdate': 'Screen built.',
            }),
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'complete': true,
              'finalSummary': 'Reporting screen is complete.',
              'remainingCriteria': [],
              'openQuestions': [],
            }),
          ),
        ]);
        await chat.attachWorkspace(tempDir.path);

        await chat.send('/project Build the reporting screen');

        expect(chat.activeProject?.status, ProjectStatus.completed);
        expect(chat.activeProject?.tasks.single.status, TaskStatus.completed);
        expect(chat.activeTask, isNull);
        expect(chat.activeProject?.completionSummary, contains('complete'));
      },
    );

    test('supports /continue-project for the active project', () async {
      serverManager.chatClient = _QueueCompletionClient([
        _finaliseProjectResponse({
          'backlog': [
            _projectTaskJson(relevantSuccessCriteria: const ['Finish']),
          ],
          'knownFacts': [],
          'openQuestions': [],
        }),
        ChatCompletionResponse(
          content: jsonEncode({
            'task': _projectTaskJson(relevantSuccessCriteria: const ['Finish']),
          }),
        ),
        _finaliseTaskResponse(_projectPlanJson(title: 'Project task')),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Project task complete.',
            'memoryUpdate': 'Screen built.',
          }),
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'complete': true,
            'finalSummary': 'All done.',
            'remainingCriteria': [],
            'openQuestions': [],
          }),
        ),
      ]);
      await chat.attachWorkspace(tempDir.path);
      chat.activeProject = _projectDocument();
      await ProjectService(
        taskService: _createTaskService(),
      ).storage.saveSnapshot(tempDir.path, chat.activeProject!);

      await chat.send('/continue-project');

      expect(chat.activeProject?.status, ProjectStatus.completed);
      expect(
        chat.messageStore.messages.firstWhere(
          (m) => m.text == '/continue-project',
        ),
        isNotNull,
      );
    });

    test('step finished message omits future planned artifacts', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode({
          'title': 'Artifact task',
          'goal': 'Analyze and report',
          'constraints': ['Stay inside the workspace.'],
          'successCriteria': ['Report is written.'],
          'steps': [
            {
              'id': 'inspect',
              'title': 'Inspect',
              'objective': 'Inspect the codebase.',
              'instructions': ['Read relevant files.'],
              'mayEditFiles': false,
              'artifacts': [
                {'path': '.agent/tasks/{{task_id}}/overview.md'},
              ],
            },
            {
              'id': 'report',
              'title': 'Report',
              'objective': 'Write final report.',
              'instructions': ['Write final report.'],
              'mayEditFiles': false,
              'artifacts': [
                {'path': '.agent/tasks/{{task_id}}/final_report.md'},
              ],
            },
          ],
        }),
      ]);
      await chat.attachWorkspace(tempDir.path);
      await chat.send('/plan Analyze the codebase');

      serverManager.chatClient = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'Inspection complete.',
          'memoryUpdate': 'Inspected the codebase.',
        }),
      ]);

      await chat.runNextTaskPhase();

      final stepMessage = chat.messageStore.messages.last.text;
      expect(stepMessage, contains('Task step finished'));
      expect(stepMessage, isNot(contains('final_report.md')));
      expect(stepMessage, isNot(contains('Artifacts:')));
      expect(chat.activeTask?.status, TaskStatus.paused);
    });

    test(
      'renders task model reasoning and tool calls as chat bubbles',
      () async {
        serverManager.chatClient = _QueueCompletionClient([
          _finaliseTaskResponse(
            _planJson(title: 'Visible task'),
            reasoning: 'Planning rationale.',
            content: jsonEncode(_planJson(title: 'Visible task')),
          ),
          ChatCompletionResponse(
            reasoning: 'Need a calculation.',
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                id: 'call_calc',
                name: 'calculator',
                arguments: jsonEncode({
                  'paramA': 1,
                  'paramB': 2,
                  'operator': '+',
                }),
              ),
            ],
          ),
          ChatCompletionResponse(
            reasoning: 'Finalizing from tool output.',
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Calculated result.',
              'memoryUpdate': 'Calculator returned 3.',
            }),
          ),
        ]);
        await chat.attachWorkspace(tempDir.path);

        await chat.send('/task Build the reporting screen');

        final plannerBubble = chat.messageStore.messages.firstWhere(
          (message) => message.text.contains('Visible task'),
        );
        expect(plannerBubble.reasoning, contains('Planning rationale.'));

        final toolBubble = chat.messageStore.messages.firstWhere(
          (message) =>
              message.tools.values.any((tool) => tool.name == 'calculator'),
        );
        expect(toolBubble.reasoning, contains('Need a calculation.'));
        expect(toolBubble.tools[0]?.name, 'calculator');
        expect(toolBubble.tools[0]?.arguments, contains('"paramA":1'));
        expect(toolBubble.tools[0]?.result, contains('"result":3'));

        final finalBubble = chat.messageStore.messages.firstWhere(
          (message) =>
              message.reasoning.contains('Finalizing from tool output.'),
        );
        expect(finalBubble.text, contains('Calculated result.'));
        expect(chat.activeTask?.runs.single.summary, 'Calculated result.');
      },
    );

    test(
      'uses the active task phase payload for diagnostics context',
      () async {
        final client = _StuckTaskClient(_planJson(title: 'Diagnostic task'));
        serverManager.chatClient = client;
        chat.setCurrentModelSnapshot(
          ModelJson.decode<ModelConfigurationSnapshot>({
            'modelName': 'test',
            'nCtx': 4096,
          }),
        );
        await chat.attachWorkspace(tempDir.path);

        final sendFuture = chat.send('/task Build the reporting screen');
        await client.stepStarted.future.timeout(const Duration(seconds: 2));

        expect(client.requestEstimates, hasLength(2));
        expect(
          serverManager.diagnostics.estimatedContextTokens,
          client.requestEstimates.last,
        );
        expect(serverManager.diagnostics.isStreaming, isTrue);

        await chat.cancelTaskRun();
        await sendFuture.timeout(const Duration(seconds: 2));
      },
    );

    test(
      'cancels a stuck task run and keeps the transcript and task',
      () async {
        final client = _StuckTaskClient(_planJson(title: 'Cancellable task'));
        serverManager.chatClient = client;
        await chat.attachWorkspace(tempDir.path);

        final sendFuture = chat.send('/task Build the reporting screen');
        await client.stepStarted.future.timeout(const Duration(seconds: 2));

        expect(chat.taskBusy, isTrue);
        expect(
          chat.messageStore.messages.any(
            (message) => message.reasoning.contains('Still thinking.'),
          ),
          isTrue,
        );

        await chat.cancelTaskRun();
        await sendFuture.timeout(const Duration(seconds: 2));

        expect(client.stepCancelled.isCompleted, isTrue);
        expect(chat.taskBusy, isFalse);
        expect(chat.taskCancellationRequested, isFalse);
        expect(chat.activeTask?.status, TaskStatus.paused);
        expect(chat.activeTask?.currentStepId, 'build');
        expect(chat.activeTask?.steps.single.status, TaskStepStatus.pending);
        expect(chat.activeTask?.runs.single.status, TaskRunStatus.cancelled);
        expect(chat.activeTask?.runs.single.summary, contains('cancelled'));
        expect(
          chat.messageStore.messages.any(
            (message) => message.reasoning.contains('Still thinking.'),
          ),
          isTrue,
        );
        expect(
          File(
            path.join(
              tempDir.path,
              '.agent',
              'tasks',
              chat.activeTask!.id,
              'task.json',
            ),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('scopes transient tasks and deletes them on new chat', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      final task = chat.activeTask!;
      final taskDir = Directory(
        path.join(tempDir.path, '.agent', 'tasks', task.id),
      );
      expect(chat.currentChatId, isNull);
      expect(task.chatSessionId, isNotNull);
      expect(taskDir.existsSync(), isTrue);

      await chat.newChat();

      expect(taskDir.existsSync(), isFalse);
    });

    test('moves transient task scope when the chat is saved', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Saved scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      final saved = await chat.saveCurrentChat(title: 'Reporting plan');

      expect(chat.activeTask?.chatSessionId, saved.id);
      expect(chat.availableTasks.single.chatSessionId, saved.id);

      await chat.newChat();
      await chat.attachWorkspace(tempDir.path);
      expect(chat.activeTask, isNull);

      await chat.openChat(saved.id);

      expect(chat.activeTask?.title, 'Saved scoped task');
      expect(chat.activeTask?.chatSessionId, saved.id);
    });

    test('scopes transient projects and deletes them on new chat', () async {
      serverManager.chatClient = _QueueChatClient([jsonEncode({})]);
      await chat.attachWorkspace(tempDir.path);
      chat.setExecutionMode(ExecutionMode.project);

      await chat.send('Build the reporting screen');

      final project = chat.activeProject!;
      final projectDir = Directory(
        path.join(tempDir.path, '.agent', 'projects', project.id),
      );
      expect(chat.currentChatId, isNull);
      expect(project.chatSessionId, isNotNull);
      expect(projectDir.existsSync(), isTrue);

      await chat.newChat();

      expect(projectDir.existsSync(), isFalse);
    });

    test('moves transient project scope when the chat is saved', () async {
      serverManager.chatClient = _QueueChatClient([jsonEncode({})]);
      await chat.attachWorkspace(tempDir.path);
      chat.setExecutionMode(ExecutionMode.project);

      await chat.send('Build the reporting screen');

      final saved = await chat.saveCurrentChat(title: 'Reporting project');

      expect(chat.activeProject?.chatSessionId, saved.id);
      expect(chat.availableProjects.single.chatSessionId, saved.id);

      await chat.newChat();
      await chat.attachWorkspace(tempDir.path);
      expect(chat.activeProject, isNull);

      await chat.openChat(saved.id);

      expect(chat.activeProject?.title, 'Build the reporting screen');
      expect(chat.activeProject?.chatSessionId, saved.id);
    });

    test(
      'project mode input updates the active project instead of replacing it',
      () async {
        serverManager.chatClient = _QueueChatClient([jsonEncode({})]);
        await chat.attachWorkspace(tempDir.path);
        chat.setExecutionMode(ExecutionMode.project);

        await chat.send('Build the reporting screen');
        final projectId = chat.activeProject!.id;

        await chat.send('Use SvelteKit for the web framework.');

        expect(chat.activeProject?.id, projectId);
        expect(
          chat.activeProject?.knownFacts.join('\n'),
          contains('SvelteKit'),
        );
        expect(
          (await ProjectService(
            taskService: _createTaskService(),
          ).storage.listProjects(tempDir.path)),
          hasLength(1),
        );
      },
    );

    test('supports /continue command for the active task', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'Continued step.',
          'memoryUpdate': 'Done.',
        }),
      ]);
      await chat.attachWorkspace(tempDir.path);
      chat.activeTask = _taskDocument();
      await TaskStorageService().saveSnapshot(tempDir.path, chat.activeTask!);

      await chat.send('/continue');

      expect(chat.activeTask?.status, TaskStatus.completed);
      expect(
        chat.messageStore.messages.firstWhere((m) => m.text == '/continue'),
        isNotNull,
      );
    });
  });

  group('ChatTabsService task cleanup', () {
    late Directory tempDir;
    late PreferencesService preferences;
    late ChatLibraryService chatLibrary;
    late SystemPromptLibraryService promptLibrary;
    late ChatTabsService tabs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('hermes_chat_tabs_');
      final databasePath = path.join(tempDir.path, 'hermes.db');
      preferences = PreferencesService();
      chatLibrary = ChatLibraryService(
        preferencesService: preferences,
        databasePath: databasePath,
      );
      promptLibrary = SystemPromptLibraryService(
        preferencesService: preferences,
        databasePath: databasePath,
      );
      final sandbox = WorkspaceSandbox();
      final toolService = ToolService(workspaceSandbox: sandbox);
      final taskService = TaskService(
        toolService: toolService,
        sandbox: sandbox,
      );
      tabs = ChatTabsService(
        chatLibrary: chatLibrary,
        systemPromptLibrary: promptLibrary,
        toolService: toolService,
        taskService: taskService,
        projectService: ProjectService(taskService: taskService),
        workspaceService: WorkspaceService(sandbox: sandbox),
        preferencesService: preferences,
      );
    });

    tearDown(() async {
      await tabs.dispose();
      await chatLibrary.dispose();
      await promptLibrary.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads system prompts into the active tab', () async {
      final reviewer = await promptLibrary.createPrompt(
        name: 'Reviewer',
        content: 'Review code carefully.',
      );

      final target = await tabs.loadSystemPromptIntoActiveChat(reviewer);

      expect(target, SystemPromptLoadTarget.currentChat);
      expect(tabs.activeChat?.currentSystemPromptSnapshot?.id, reviewer.id);
      expect(tabs.activeChat?.messageStore.first.text, reviewer.content);
    });

    test('deletes saved chat task folders from the chat list path', () async {
      tabs.serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Deleted tab task')),
      ]);
      await tabs.activeChat?.attachWorkspace(tempDir.path);

      await tabs.activeChat?.send('/plan Build the reporting screen');
      final saved = await tabs.activeChat!.saveCurrentChat(
        title: 'Deleted tab plan',
      );
      final taskId = tabs.activeChat!.activeTask!.id;
      final taskDir = Directory(
        path.join(tempDir.path, '.agent', 'tasks', taskId),
      );

      expect(taskDir.existsSync(), isTrue);

      await tabs.deleteSavedChat(saved.id);

      expect(await chatLibrary.getChat(saved.id), isNull);
      expect(taskDir.existsSync(), isFalse);
      expect(tabs.activeChat?.currentChatId, isNull);
    });

    test(
      'deletes saved chat project folders from the chat list path',
      () async {
        tabs.serverManager.chatClient = _QueueChatClient([jsonEncode({})]);
        await tabs.activeChat?.attachWorkspace(tempDir.path);
        tabs.activeChat?.setExecutionMode(ExecutionMode.project);

        await tabs.activeChat?.send('Build the reporting screen');
        final saved = await tabs.activeChat!.saveCurrentChat(
          title: 'Deleted tab project',
        );
        final projectId = tabs.activeChat!.activeProject!.id;
        final projectDir = Directory(
          path.join(tempDir.path, '.agent', 'projects', projectId),
        );

        expect(projectDir.existsSync(), isTrue);

        await tabs.deleteSavedChat(saved.id);

        expect(await chatLibrary.getChat(saved.id), isNull);
        expect(projectDir.existsSync(), isFalse);
        expect(tabs.activeChat?.currentChatId, isNull);
      },
    );

    test('deletes orphaned chat-scoped tasks when disposed', () async {
      await tabs.activeChat?.attachWorkspace(tempDir.path);
      final orphaned = _taskDocument(
        id: 'task_orphaned',
        chatSessionId: 'deleted_chat',
      );
      await TaskStorageService().saveSnapshot(tempDir.path, orphaned);
      final taskDir = Directory(
        path.join(tempDir.path, '.agent', 'tasks', 'task_orphaned'),
      );

      expect(taskDir.existsSync(), isTrue);

      await tabs.dispose();

      expect(taskDir.existsSync(), isFalse);
    });

    test('deletes orphaned chat-scoped projects when disposed', () async {
      await tabs.activeChat?.attachWorkspace(tempDir.path);
      final orphaned = _projectDocument(
        id: 'project_orphaned',
        chatSessionId: 'deleted_chat',
      );
      await ProjectService(
        taskService: _createTaskService(),
      ).storage.saveSnapshot(tempDir.path, orphaned);
      final projectDir = Directory(
        path.join(tempDir.path, '.agent', 'projects', 'project_orphaned'),
      );

      expect(projectDir.existsSync(), isTrue);

      await tabs.dispose();

      expect(projectDir.existsSync(), isFalse);
    });
  });
}

TaskService _createTaskService() {
  final sandbox = WorkspaceSandbox();
  return TaskService(
    toolService: ToolService(workspaceSandbox: sandbox),
    sandbox: sandbox,
  );
}

Map<String, dynamic> _planJson({required String title}) {
  return {
    'title': title,
    'goal': 'Build the reporting screen',
    'constraints': ['Stay inside the workspace.'],
    'successCriteria': ['The reporting screen is planned.'],
    'steps': [
      {
        'id': 'build',
        'title': 'Build screen',
        'objective': 'Build the reporting screen.',
        'instructions': ['Inspect relevant files.', 'Implement the screen.'],
        'mayEditFiles': false,
      },
    ],
  };
}

Map<String, dynamic> _projectPlanJson({required String title}) {
  return {
    'title': title,
    'goal': 'Build the reporting screen slice',
    'constraints': ['Stay inside the workspace.'],
    'successCriteria': ['The reporting screen slice is complete.'],
    'steps': [
      {
        'id': 'build',
        'title': 'Build screen slice',
        'objective': 'Build the reporting screen slice.',
        'instructions': ['Implement only the bounded screen slice.'],
        'mayEditFiles': false,
      },
    ],
  };
}

Map<String, dynamic> _projectTaskJson({
  List<String> relevantSuccessCriteria = const ['Screen is built.'],
}) {
  return {
    'title': 'Build screen slice',
    'objective': 'Build the reporting screen slice',
    'relevantSuccessCriteria': relevantSuccessCriteria,
    'doneCriteria': ['The reporting screen slice is complete.'],
    'outOfScope': ['Do not perform unrelated project work.'],
    'context': ['Use the attached workspace.'],
    'expectedArtifacts': [],
  };
}

TaskDocument _taskDocument({String id = 'task_test', String? chatSessionId}) {
  final now = DateTime(2026, 1, 1);
  return TaskDocument(
    id: id,
    title: 'Test task',
    originalPrompt: 'Run the task',
    goal: 'Run the task',
    constraints: const [],
    successCriteria: const ['Finish'],
    steps: const [
      TaskStep(
        id: 'step_1',
        title: 'Step 1',
        objective: 'Do the work',
        instructions: ['Work carefully'],
        mayEditFiles: false,
        artifacts: [],
        status: TaskStepStatus.pending,
      ),
    ],
    status: TaskStatus.paused,
    currentStepId: 'step_1',
    memorySummary: '',
    runs: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectDocument _projectDocument({
  String id = 'project_test',
  String? chatSessionId,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: id,
    title: 'Test project',
    originalPrompt: 'Run the project',
    goal: 'Run the project',
    constraints: const [],
    successCriteria: const ['Finish'],
    status: ProjectStatus.paused,
    activeTaskId: null,
    memorySummary: '',
    completionSummary: '',
    tasks: const [],
    decisions: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: now,
  );
}

ChatCompletionResponse _finaliseTaskResponse(
  Map<String, dynamic> arguments, {
  String content = '',
  String reasoning = '',
}) {
  return ChatCompletionResponse(
    content: content,
    reasoning: reasoning,
    toolCalls: [
      ChatCompletionToolCall(
        name: 'finaliseTaskCreation',
        arguments: jsonEncode(arguments),
      ),
    ],
  );
}

ChatCompletionResponse _finaliseProjectResponse(
  Map<String, dynamic> arguments, {
  String content = '',
  String reasoning = '',
}) {
  return ChatCompletionResponse(
    content: content,
    reasoning: reasoning,
    toolCalls: [
      ChatCompletionToolCall(
        name: 'finaliseProjectCreation',
        arguments: jsonEncode(arguments),
      ),
    ],
  );
}

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> _responses;
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    final index = _index >= _responses.length ? _responses.length - 1 : _index;
    _index++;
    return ChatCompletionResponse(content: _responses[index]);
  }

  @override
  void dispose() {}
}

class _QueueCompletionClient extends ChatClient {
  _QueueCompletionClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionResponse> _responses;
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    final index = _index >= _responses.length ? _responses.length - 1 : _index;
    _index++;
    return _responses[index];
  }

  @override
  void dispose() {}
}

class _StuckTaskClient extends ChatClient {
  _StuckTaskClient(this._plan)
    : super(baseUrl: 'http://localhost', model: 'test');

  final Map<String, dynamic> _plan;
  final Completer<void> stepStarted = Completer<void>();
  final Completer<void> stepCancelled = Completer<void>();
  final List<int> requestEstimates = [];
  var _streamCalls = 0;

  @override
  bool get supportsStreamingCancellation => true;

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) {
    requestEstimates.add(
      ContextEstimator.estimateChatCompletionRequest(
        messages: messages,
        extraParams: extraParams ?? const {},
      ),
    );
    _streamCalls++;
    final controller = StreamController<ChatToken>(sync: true);

    if (_streamCalls == 1) {
      controller.onListen = () {
        controller.add(
          ChatToken(
            tool: ToolCallDelta(
              index: 0,
              id: 'call_finalise_task',
              name: 'finaliseTaskCreation',
            ),
          ),
        );
        controller.add(
          ChatToken(
            tool: ToolCallDelta(index: 0, argumentsChunk: jsonEncode(_plan)),
          ),
        );
        unawaited(controller.close());
      };
      return controller.stream;
    }

    controller.onListen = () {
      controller.add(ChatToken(reasoning: 'Still thinking.'));
      controller.add(ChatToken(content: 'partial output'));
      if (!stepStarted.isCompleted) stepStarted.complete();
    };
    controller.onCancel = () {
      if (!stepCancelled.isCompleted) stepCancelled.complete();
    };
    return controller.stream;
  }

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) {
    throw UnsupportedError('This test client only supports streaming.');
  }

  @override
  void dispose() {}
}
