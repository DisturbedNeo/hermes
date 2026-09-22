import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
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
      final chatLibraryRepository = ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      );
      chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
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

    test('uses workspace tools attached after chat construction', () async {
      final client = _RecordingStreamClient();
      serverManager.chatClient = client;
      await chat.attachWorkspace(tempDir.path);

      await chat.send('Inspect the workspace');
      final extraParams = await client.extraParams.future.timeout(
        const Duration(seconds: 2),
      );

      expect(_toolNames(extraParams), contains('list_directory'));
      expect(_toolNames(extraParams), contains('read_file'));
    });

    test(
      'cancels during pre-stream context accounting without a stale bubble',
      () async {
        final client = _BlockingCountClient();
        serverManager.chatClient = client;
        chat.setCurrentModelSnapshot(
          ModelJson.decode<ModelConfigurationSnapshot>({
            'modelName': 'test',
            'nCtx': 4096,
          }),
        );

        final send = chat.send('Cancel before streaming');
        await client.countStarted.future.timeout(const Duration(seconds: 2));
        await chat.cancelGeneration();
        await send.timeout(const Duration(seconds: 2));

        expect(client.streamCalls, 0);
        expect(
          chat.messageStore.messages.where(
            (message) => message.role == MessageRole.assistant,
          ),
          isEmpty,
        );
        expect(chat.chatStream.isStreaming, isFalse);
      },
    );

    test('persists each tool result and cancels remaining tool work', () async {
      final client = _TwoToolClient();
      serverManager.chatClient = client;
      await chat.attachWorkspace(tempDir.path);
      chat.setCommandExecutionApproved(true);

      await chat.send('Run two tools');
      Bubble? toolBubble;
      for (var i = 0; i < 100; i++) {
        toolBubble = chat.messageStore.messages
            .where((message) => message.tools.length == 2)
            .firstOrNull;
        if (toolBubble?.tools[0]?.result != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(toolBubble?.tools[0]?.result, contains('"result":3'));
      expect(toolBubble?.tools[1]?.result, isNull);
      expect(chat.chatStream.isStreaming, isTrue);

      await chat.cancelGeneration();

      final cancelledBubble = chat.messageStore.messages.firstWhere(
        (message) => message.id == toolBubble!.id,
      );
      expect(cancelledBubble.tools[0]?.result, contains('"result":3'));
      expect(cancelledBubble.tools[1]?.result, contains('operation_cancelled'));
      expect(client.streamCalls, 1);
      expect(chat.chatStream.isStreaming, isFalse);
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
        _commandPlanTaskResponse(_planJson(title: 'Runnable task')),
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

    test('run task continues across successful paused checkpoints', () async {
      serverManager.chatClient = _QueueCompletionClient([
        _commandPlanTaskResponse({
          ..._planJson(title: 'Multi-step task'),
          'steps': [
            {
              'id': 'inspect',
              'title': 'Inspect',
              'objective': 'Inspect the workspace.',
              'instructions': ['Read the relevant files.'],
              'mayEditFiles': false,
            },
            {
              'id': 'report',
              'title': 'Report',
              'objective': 'Write the report.',
              'instructions': ['Summarise the findings.'],
              'mayEditFiles': false,
            },
          ],
        }),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Inspection complete.',
            'memoryUpdate': 'The workspace was inspected.',
          }),
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Report complete.',
            'memoryUpdate': 'The report was written.',
          }),
        ),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/task Inspect and report');

      expect(chat.activeTask?.status, TaskStatus.completed);
      expect(chat.activeTask?.runs, hasLength(2));
      expect(chat.activeTask?.runs.map((run) => run.summary), [
        'Inspection complete.',
        'Report complete.',
      ]);
    });

    test('supports /continue-project for the active project', () async {
      serverManager.chatClient = _QueueCompletionClient([
        _commandPlanProjectResponse({
          'tasks': [
            _projectTaskJson(relevantSuccessCriteria: const ['Finish']),
          ],
          'openQuestions': [],
        }),
        ChatCompletionResponse(
          content: jsonEncode({
            'task': _projectTaskJson(relevantSuccessCriteria: const ['Finish']),
          }),
        ),
        _commandPlanTaskResponse(_projectPlanJson(title: 'Project task')),
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
      final seedProject = _projectDocument();
      final seedProjectService = ProjectService(
        taskService: _createTaskService(),
      );
      chat.activeProject = (await seedProjectService.repository.saveSnapshot(
        tempDir.path,
        seedProject,
      )).value;

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
      expect(stepMessage, contains('Inspection complete.'));
      expect(stepMessage, isNot(contains('Model transport was interrupted')));
      expect(stepMessage, isNot(contains('final_report.md')));
      expect(stepMessage, isNot(contains('Artifacts:')));
      expect(chat.activeTask?.status, TaskStatus.paused);
    });

    test(
      'renders task model reasoning and tool calls as chat bubbles',
      () async {
        serverManager.chatClient = _QueueCompletionClient([
          _commandPlanTaskResponse(
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
          serverManager.diagnostics.displayContextTokens,
          client.requestEstimates.last,
        );

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
        await Future<void>.delayed(const Duration(milliseconds: 60));

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
        expect(chat.activeTask?.currentStepId, startsWith('step_'));
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
          chat.activeProject?.memory.map((item) => item.content).join('\n'),
          contains('SvelteKit'),
        );
        expect(
          (await ProjectService(
            taskService: _createTaskService(),
          ).repository.listProjects(tempDir.path)),
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
      chat.activeTask = (await TaskRepository().saveSnapshot(
        tempDir.path,
        chat.activeTask!,
      )).value;

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
    late SystemPromptLibraryRepository promptLibraryRepository;
    late SystemPromptLibraryService promptLibrary;
    late ChatTabsService tabs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('hermes_chat_tabs_');
      final databasePath = path.join(tempDir.path, 'hermes.db');
      preferences = PreferencesService();
      final chatLibraryRepository = ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: databasePath,
      );
      chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
      promptLibraryRepository = SystemPromptLibraryRepository(
        preferencesService: preferences,
        databasePath: databasePath,
      );
      promptLibrary = SystemPromptLibraryService(
        repository: promptLibraryRepository,
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
      final module = await promptLibrary.createModule(
        name: 'Reviewer rules',
        category: 'Task',
        content: 'Review code carefully.',
        priority: 10,
      );
      final reviewer = await promptLibrary.createPreset(
        name: 'Reviewer',
        baseModuleIds: [module.id],
      );

      final target = await tabs.loadPromptPresetIntoActiveChat(reviewer);

      expect(target, SystemPromptLoadTarget.currentChat);
      expect(tabs.activeChat?.currentSystemPromptSnapshot?.id, reviewer.id);
      expect(
        tabs.activeChat?.messageStore.first.text,
        contains('Review code carefully.'),
      );
    });

    test('does not relay per-message or stream events through all tabs', () {
      var notifications = 0;
      void listener() => notifications++;
      tabs.addListener(listener);
      addTearDown(() => tabs.removeListener(listener));
      final chat = tabs.activeChat!;

      chat.messageStore.upsert(
        const Bubble(
          id: 'assistant-token',
          role: MessageRole.assistant,
          text: 'token',
          reasoning: '',
        ),
      );
      chat.chatStream.setState(StreamState.streaming);

      expect(notifications, 0);
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
      await TaskRepository().saveSnapshot(tempDir.path, orphaned);
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
      ).repository.saveSnapshot(tempDir.path, orphaned);
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
    'gates': [
      {'id': 'no_tool_errors', 'required': true, 'scope': 'task'},
    ],
  };
}

Task _taskDocument({String id = 'task_test', String? chatSessionId}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: 'Test task',
    originalPrompt: 'Run the task',
    objective: 'Run the task',
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
    originalGoal: 'Run the project',
    refinedGoal: 'Run the project',
    constraints: const [],
    criteria: const [],
    status: ProjectStatus.paused,
    activeTaskId: null,
    completionSummary: '',
    tasks: const [],
    decisions: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: now,
  );
}

ChatCompletionResponse _commandPlanTaskResponse(
  Map<String, dynamic> arguments, {
  String content = '',
  String reasoning = '',
}) {
  final calls = <ChatCompletionToolCall>[
    _toolCall('task_set_brief', {
      'title': arguments['title'] ?? 'Task',
      'objective': arguments['objective'] ?? arguments['goal'] ?? '',
      'constraints': arguments['constraints'] ?? const [],
      'success_criteria':
          arguments['successCriteria'] ??
          arguments['success_criteria'] ??
          const [],
    }),
    for (final raw in (arguments['steps'] as List? ?? const []))
      if (raw is Map)
        _toolCall('task_add_step', {
          'ref': raw['id'] ?? raw['ref'] ?? '',
          'title': raw['title'] ?? '',
          'objective': raw['objective'] ?? '',
          'instructions': raw['instructions'] ?? const [],
          'may_edit_files':
              raw['mayEditFiles'] ?? raw['may_edit_files'] ?? false,
        }),
    _toolCall('task_commit_plan', const {}),
  ];
  return ChatCompletionResponse(
    content: content,
    reasoning: reasoning,
    toolCalls: calls,
  );
}

ChatCompletionResponse _commandPlanProjectResponse(
  Map<String, dynamic> arguments, {
  String content = '',
  String reasoning = '',
}) {
  final calls = <ChatCompletionToolCall>[
    if (arguments['title'] != null || arguments['refinedGoal'] != null)
      _toolCall('plan_set_project_details', {
        'title': arguments['title'] ?? 'Project',
        'refined_goal':
            arguments['refinedGoal'] ?? arguments['refined_goal'] ?? '',
        'constraints': arguments['constraints'] ?? const [],
      }),
    if (arguments['criteria'] is List &&
        (arguments['criteria'] as List).isNotEmpty)
      _toolCall('plan_add_criteria', {
        'criteria': [
          for (final raw in arguments['criteria'] as List)
            if (raw is Map)
              {
                'ref': raw['id'] ?? raw['ref'] ?? '',
                'statement': raw['statement'] ?? '',
                'required': raw['required'] ?? true,
                'verification_mode': 'deterministic',
              },
        ],
      }),
    if (arguments['milestones'] is List &&
        (arguments['milestones'] as List).isNotEmpty)
      _toolCall('plan_add_milestones', {
        'milestones': [
          for (final raw in arguments['milestones'] as List)
            if (raw is Map)
              {
                'ref': raw['id'] ?? raw['ref'] ?? '',
                'title': raw['title'] ?? '',
                'objective': raw['objective'] ?? '',
                'criterion_refs': raw['criterionIds'] ?? const [],
                'exit_conditions': raw['exitConditions'] ?? const [],
                'order': raw['order'] ?? 1,
              },
        ],
      }),
    if (arguments['tasks'] is List && (arguments['tasks'] as List).isNotEmpty)
      _toolCall('plan_add_tasks', {
        'tasks': [
          for (final raw in arguments['tasks'] as List)
            if (raw is Map)
              {
                'ref': raw['id'] ?? raw['ref'] ?? '',
                'title': raw['title'] ?? '',
                'objective': raw['objective'] ?? '',
                'criterion_refs': raw['criterionIds'] ?? const [],
                'dependency_refs': raw['dependsOnTaskIds'] ?? const [],
                'milestone_ref': raw['milestoneId'],
                'constraints': raw['constraints'] ?? const [],
                'read_paths': raw['readPaths'] ?? const [],
                'write_paths': raw['writePaths'] ?? const [],
                'done_criteria': raw['doneCriteria'] ?? const [],
                'out_of_scope': raw['outOfScope'] ?? const [],
                'context': raw['context'] ?? const [],
                'expected_artifacts': raw['expectedArtifacts'] ?? const [],
              },
        ],
      }),
    for (final raw in (arguments['tasks'] as List? ?? const []))
      if (raw is Map)
        _toolCall('plan_add_check', {
          'task': raw['id'] ?? raw['ref'] ?? '',
          'kind': 'command',
          'command': 'true',
          'criterion_refs': raw['criterionIds'] ?? const [],
          'required': true,
        }),
    _toolCall('plan_commit', {
      'summary': arguments['summary'] ?? 'Apply the project plan.',
      'rationale': arguments['rationale'] ?? 'Commit the bounded project plan.',
    }),
  ];
  return ChatCompletionResponse(
    content: content,
    reasoning: reasoning,
    toolCalls: calls,
  );
}

ChatCompletionToolCall _toolCall(String name, Map<String, dynamic> arguments) =>
    ChatCompletionToolCall(
      id: 'call_${name}_${arguments.hashCode}',
      name: name,
      arguments: jsonEncode(arguments),
    );

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> _responses;
  final Set<String> _convertedPlans = {};
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final index = _index >= _responses.length ? _responses.length - 1 : _index;
    _index++;
    final response = _responses[index];
    try {
      final decoded = jsonDecode(response);
      if (decoded is Map &&
          decoded['steps'] is List &&
          _convertedPlans.add(response)) {
        return _commandPlanTaskResponse(Map<String, dynamic>.from(decoded));
      }
    } on FormatException {
      // Preserve non-JSON responses for tests that exercise transport errors.
    }
    return ChatCompletionResponse(content: response);
  }

  @override
  void dispose() {}
}

class _RecordingStreamClient extends ChatClient {
  _RecordingStreamClient() : super(baseUrl: 'http://localhost', model: 'test');

  final Completer<Map<String, dynamic>> extraParams = Completer();

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async* {
    if (!this.extraParams.isCompleted) {
      this.extraParams.complete(extraParams ?? const {});
    }
    yield ChatToken(content: 'Done.');
  }

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) {
    throw UnsupportedError('This test client only supports streaming.');
  }

  @override
  void dispose() {}
}

Set<String> _toolNames(Map<String, dynamic>? extraParams) {
  final tools = extraParams?['tools'];
  if (tools is! List) return const {};
  return {
    for (final tool in tools.whereType<Map>())
      if (tool['function'] is Map)
        ((tool['function'] as Map)['name'] ?? '').toString(),
  }..remove('');
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
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
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
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
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
        final commands = [
          (
            'call_task_set_brief',
            'task_set_brief',
            {
              'title': _plan['title'] ?? 'Task',
              'objective': _plan['goal'] ?? '',
              'constraints': _plan['constraints'] ?? const [],
              'success_criteria': _plan['successCriteria'] ?? const [],
            },
          ),
          (
            'call_task_add_step',
            'task_add_step',
            {
              'ref': 'step',
              'title': 'Step',
              'objective': 'Do the bounded work.',
              'instructions': ['Do the bounded work.'],
              'may_edit_files': false,
            },
          ),
          ('call_task_commit', 'task_commit_plan', <String, dynamic>{}),
        ];
        for (var index = 0; index < commands.length; index++) {
          final (id, name, arguments) = commands[index];
          controller.add(
            ChatToken(
              tool: ToolCallDelta(index: index, id: id, name: name),
            ),
          );
          controller.add(
            ChatToken(
              tool: ToolCallDelta(
                index: index,
                argumentsChunk: jsonEncode(arguments),
              ),
            ),
          );
        }
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
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) {
    throw UnsupportedError('This test client only supports streaming.');
  }

  @override
  void dispose() {}
}

class _BlockingCountClient extends ChatClient {
  _BlockingCountClient() : super(baseUrl: 'http://localhost', model: 'test');

  final Completer<void> countStarted = Completer<void>();
  var streamCalls = 0;

  @override
  Future<int?> countInputTokens({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CancellationToken? cancellationToken,
  }) async {
    if (!countStarted.isCompleted) countStarted.complete();
    final cancelled = Completer<void>();
    final unregister = cancellationToken?.onCancel(cancelled.complete);
    try {
      await cancelled.future;
      cancellationToken?.throwIfCancelled();
      return 1;
    } finally {
      unregister?.call();
    }
  }

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) {
    streamCalls++;
    return const Stream.empty();
  }

  @override
  void dispose() {}
}

class _TwoToolClient extends ChatClient {
  _TwoToolClient() : super(baseUrl: 'http://localhost', model: 'test');

  var streamCalls = 0;

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async* {
    streamCalls++;
    yield ChatToken(
      tool: ToolCallDelta(
        index: 0,
        id: 'calculator_call',
        name: 'calculator',
        argumentsChunk: '{"paramA":1,"paramB":2,"operator":"+"}',
      ),
    );
    yield ChatToken(
      tool: ToolCallDelta(
        index: 1,
        id: 'command_call',
        name: 'run_command',
        argumentsChunk: '{"command":"sleep 30"}',
      ),
    );
  }

  @override
  void dispose() {}
}
