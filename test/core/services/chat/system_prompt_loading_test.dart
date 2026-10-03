import 'dart:async';
import 'package:hermes/features/persistence/infrastructure/workspace_persistence_coordinator.dart';
import 'package:hermes/app/test_factories.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/chat/application/contracts/stream_state.dart';
import 'package:hermes/features/chat/application/protocol/context_estimator.dart';
import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/chat/application/contracts/chat_workspace_contracts.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/infrastructure/chat_library_repository.dart';
import 'package:hermes/features/chat/application/chat_controller.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';
import 'package:hermes/features/model/infrastructure/llama_server_manager.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/features/chat/infrastructure/system_prompt_library_repository.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/platform/workspace_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatController system prompts and tasks', () {
    late Directory tempDir;
    late ChatLibraryService chatLibrary;
    late PreferencesService preferences;
    late LlamaServerManager serverManager;
    late ChatController chat;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp(
        'hermes_chat_controller_',
      );
      preferences = PreferencesService();
      final chatLibraryRepository = ChatLibraryRepository(
        preferencesService: preferences,
        databasePath: path.join(tempDir.path, 'hermes.db'),
      );
      chatLibrary = ChatLibraryService(repository: chatLibraryRepository);
      serverManager = LlamaServerManager();
      final sandbox = WorkspaceSandbox();
      final toolService = ToolService(workspaceSandbox: sandbox);
      final taskController = createTestTaskController(
        toolService: toolService,
        sandbox: sandbox,
        persistence: TaskRepository(
          coordinator: WorkspacePersistenceCoordinator(),
        ),
      );
      final projectApplication = createTestProjectApplication(
        taskController: taskController,
        repository: ProjectRepository(
          coordinator: WorkspacePersistenceCoordinator(),
        ),
      );
      chat = ChatController(
        serverManager: serverManager,
        toolService: toolService,
        toolProtocol: ToolProtocolAdapter(registry: toolService),
        toolExecution: ChatToolExecutionService(
          protocol: ToolProtocolAdapter(registry: toolService),
        ),
        taskQueries: taskController,
        taskSessions: taskController,
        taskPresentation: taskController,
        panelProtocol: const ChatPanelProtocolAdapter(),
        taskPlanning: createTestTaskWorkflow(taskController),
        taskExecution: createTestTaskWorkflow(taskController),
        taskRecovery: createTestTaskWorkflow(taskController),
        projectQueries: projectApplication,
        projectSessions: projectApplication,
        projectPlanning: createTestProjectWorkflow(projectApplication),
        projectCommands: createTestProjectWorkflow(projectApplication),
        projectExecution: createTestProjectWorkflow(projectApplication),
        projectRecovery: createTestProjectWorkflow(projectApplication),
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
      serverManager.setCompletionProviderForTesting(client);
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
        serverManager.setCompletionProviderForTesting(client);
        chat.updateCurrentModelSnapshot(
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
      serverManager.setCompletionProviderForTesting(client);
      await chat.attachWorkspace(tempDir.path);
      chat.updateCommandExecutionApproval(true);

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
        () => chat.updateSystemPromptSnapshot(
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

      chat.updateSystemPromptSnapshot(
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
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([
          jsonEncode({
            'title': 'Refined task',
            'goal': 'Build the reporting screen',
            'successCriteria': ['Clear plan'],
            'constraints': ['Stay in workspace'],
            'assumptions': ['Flutter app'],
          }),
        ]),
      );

      await chat.send('/refine Build the reporting screen');

      expect(chat.activeTask, isNull);
      expect(chat.messageStore.messages.last.text, contains('Refined task'));
      expect(chat.messageStore.messages.last.text, contains('Goal:'));
    });

    test('supports /plan command without running steps', () async {
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([jsonEncode(_planJson(title: 'Planned task'))]),
      );
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      expect(chat.activeTask?.title, 'Planned task');
      expect(chat.activeTask?.runs, isEmpty);
      expect(chat.activeTask?.status, TaskStatus.paused);
      expect(chat.taskModelOutputTitle, 'Task Creation Model Output');
      expect(chat.taskModelOutputText, contains('Task Planner'));
    });

    test('supports /task command by creating and running steps', () async {
      serverManager.setCompletionProviderForTesting(
        _QueueCompletionClient([
          _commandPlanTaskResponse(_planJson(title: 'Runnable task')),
          ModelCompletion(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Step complete.',
              'memoryUpdate': 'Work finished.',
            }),
          ),
        ]),
      );
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/task Build the reporting screen');

      expect(chat.activeTask?.status, TaskStatus.completed);
      expect(chat.activeTask?.runs.single.summary, 'Step complete.');
    });

    test('run task continues across successful paused checkpoints', () async {
      serverManager.setCompletionProviderForTesting(
        _QueueCompletionClient([
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
          ModelCompletion(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Inspection complete.',
              'memoryUpdate': 'The workspace was inspected.',
            }),
          ),
          ModelCompletion(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Report complete.',
              'memoryUpdate': 'The report was written.',
            }),
          ),
        ]),
      );
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
      serverManager.setCompletionProviderForTesting(
        _QueueCompletionClient([
          _commandPlanProjectResponse({
            'criteria': [
              {'id': 'criterion_1', 'statement': 'Finish'},
            ],
            'milestones': [
              {
                'id': 'milestone_1',
                'title': 'First slice',
                'objective': 'Finish the first bounded slice.',
                'criterionIds': ['criterion_1'],
              },
            ],
            'tasks': [
              {
                'ref': 'build',
                ..._projectTaskJson(relevantSuccessCriteria: const ['Finish']),
                'criterionIds': ['criterion_1'],
                'milestoneId': 'milestone_1',
              },
            ],
            'openQuestions': [],
          }),
          ModelCompletion(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Project task complete.',
              'memoryUpdate': 'Screen built.',
              'evidenceClaims': [
                {
                  'criterionId': 'criterion_1',
                  'claim': 'The bounded project task was completed.',
                  'evidenceType': 'task_claim',
                  'sourceRef': 'task_execution',
                },
              ],
            }),
          ),
          ModelCompletion(
            content: jsonEncode({
              'complete': true,
              'finalSummary': 'All done.',
              'remainingCriteria': [],
              'supportedCriterionIds': ['criterion_1'],
              'openQuestions': [],
            }),
          ),
        ]),
      );
      await chat.attachWorkspace(tempDir.path);
      await preferences.setTaskSystemSettings(
        TaskSystemSettings(
          requireApprovalBeforeExecution: false,
          requireApprovalBeforeFileEdits: false,
          planApprovalPolicy: ProjectPlanApprovalPolicy.never,
        ),
      );
      final seedProject = _projectDocument();
      final seedProjectRepository = ProjectRepository(
        coordinator: WorkspacePersistenceCoordinator(),
      );
      chat.dispatchActiveProject(
        (await seedProjectRepository.saveSnapshot(
          tempDir.path,
          seedProject,
        )).value,
      );

      await chat.send('/continue-project');

      expect(chat.activeProject?.status, ProjectStatus.active);
      expect(
        chat.messageStore.messages.firstWhere(
          (m) => m.text == '/continue-project',
        ),
        isNotNull,
      );
    });

    test('step finished message omits future planned artifacts', () async {
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([
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
        ]),
      );
      await chat.attachWorkspace(tempDir.path);
      await chat.send('/plan Analyze the codebase');

      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'Inspection complete.',
            'memoryUpdate': 'Inspected the codebase.',
          }),
        ]),
      );

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
        serverManager.setCompletionProviderForTesting(
          _QueueCompletionClient([
            _commandPlanTaskResponse(
              _planJson(title: 'Visible task'),
              reasoning: 'Planning rationale.',
              content: jsonEncode(_planJson(title: 'Visible task')),
            ),
            ModelCompletion(
              reasoning: 'Need a calculation.',
              content: '',
              toolCalls: [
                ModelToolCall(
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
            ModelCompletion(
              reasoning: 'Finalizing from tool output.',
              content: jsonEncode({
                'status': 'completed',
                'summary': 'Calculated result.',
                'memoryUpdate': 'Calculator returned 3.',
              }),
            ),
          ]),
        );
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
        serverManager.setCompletionProviderForTesting(client);
        chat.updateCurrentModelSnapshot(
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
        serverManager.setCompletionProviderForTesting(client);
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
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([jsonEncode(_planJson(title: 'Scoped task'))]),
      );
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
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([jsonEncode(_planJson(title: 'Saved scoped task'))]),
      );
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
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([jsonEncode({})]),
      );
      await chat.attachWorkspace(tempDir.path);
      chat.updateExecutionMode(ExecutionMode.project);

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
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([jsonEncode({})]),
      );
      await chat.attachWorkspace(tempDir.path);
      chat.updateExecutionMode(ExecutionMode.project);

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
        serverManager.setCompletionProviderForTesting(
          _QueueChatClient([jsonEncode({})]),
        );
        await chat.attachWorkspace(tempDir.path);
        chat.updateExecutionMode(ExecutionMode.project);

        await chat.send('Build the reporting screen');
        final projectId = chat.activeProject!.id;

        await chat.send('Use SvelteKit for the web framework.');

        expect(chat.activeProject?.id, projectId);
        expect(
          chat.activeProject?.memory.map((item) => item.content).join('\n'),
          contains('SvelteKit'),
        );
        final projectRepository = ProjectRepository(
          coordinator: WorkspacePersistenceCoordinator(),
        );
        expect(
          await projectRepository.listProjects(tempDir.path),
          hasLength(1),
        );
      },
    );

    test('supports /continue command for the active task', () async {
      serverManager.setCompletionProviderForTesting(
        _QueueChatClient([
          jsonEncode({
            'status': 'completed',
            'summary': 'Continued step.',
            'memoryUpdate': 'Done.',
          }),
        ]),
      );
      await chat.attachWorkspace(tempDir.path);
      final task = _taskDocument();
      chat.dispatchActiveTask(task);
      chat.dispatchActiveTask(
        (await TaskRepository(
          coordinator: WorkspacePersistenceCoordinator(),
        ).saveSnapshot(tempDir.path, task)).value,
      );

      await chat.send('/continue');

      expect(chat.activeTask?.status, TaskStatus.completed);
      expect(
        chat.messageStore.messages.firstWhere((m) => m.text == '/continue'),
        isNotNull,
      );
    });
  });

  group('ChatWorkspaceController task cleanup', () {
    late Directory tempDir;
    late PreferencesService preferences;
    late ChatLibraryService chatLibrary;
    late SystemPromptLibraryRepository promptLibraryRepository;
    late SystemPromptLibraryService promptLibrary;
    late ChatWorkspaceController tabs;

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
      final taskController = createTestTaskController(
        toolService: toolService,
        sandbox: sandbox,
        persistence: TaskRepository(
          coordinator: WorkspacePersistenceCoordinator(),
        ),
      );
      final projectApplication = createTestProjectApplication(
        taskController: taskController,
        repository: ProjectRepository(
          coordinator: WorkspacePersistenceCoordinator(),
        ),
      );
      tabs = ChatWorkspaceController(
        serverManager: LlamaServerManager(),
        chatLibrary: chatLibrary,
        systemPromptLibrary: promptLibrary,
        toolService: toolService,
        toolProtocol: ToolProtocolAdapter(registry: toolService),
        toolExecution: ChatToolExecutionService(
          protocol: ToolProtocolAdapter(registry: toolService),
        ),
        taskQueries: taskController,
        taskSessions: taskController,
        taskPresentation: taskController,
        panelProtocol: const ChatPanelProtocolAdapter(),
        taskPlanning: createTestTaskWorkflow(taskController),
        taskExecution: createTestTaskWorkflow(taskController),
        taskRecovery: createTestTaskWorkflow(taskController),
        projectQueries: projectApplication,
        projectSessions: projectApplication,
        projectPlanning: createTestProjectWorkflow(projectApplication),
        projectCommands: createTestProjectWorkflow(projectApplication),
        projectExecution: createTestProjectWorkflow(projectApplication),
        projectRecovery: createTestProjectWorkflow(projectApplication),
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
      (tabs.serverManager as LlamaServerManager)
          .setCompletionProviderForTesting(
            _QueueChatClient([
              jsonEncode(_planJson(title: 'Deleted tab task')),
            ]),
          );
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
        (tabs.serverManager as LlamaServerManager)
            .setCompletionProviderForTesting(
              _QueueChatClient([jsonEncode({})]),
            );
        await tabs.activeChat?.attachWorkspace(tempDir.path);
        tabs.activeChat?.updateExecutionMode(ExecutionMode.project);

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
      await TaskRepository(
        coordinator: WorkspacePersistenceCoordinator(),
      ).saveSnapshot(tempDir.path, orphaned);
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
      final projectRepository = ProjectRepository(
        coordinator: WorkspacePersistenceCoordinator(),
      );
      await projectRepository.saveSnapshot(tempDir.path, orphaned);
      final projectDir = Directory(
        path.join(tempDir.path, '.agent', 'projects', 'project_orphaned'),
      );

      expect(projectDir.existsSync(), isTrue);

      await tabs.dispose();

      expect(projectDir.existsSync(), isFalse);
    });
  });
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

Map<String, dynamic> _projectTaskJson({
  List<String> relevantSuccessCriteria = const ['Screen is built.'],
}) {
  return {
    'title': 'Build screen slice',
    'objective': 'Build the reporting screen slice',
    'relevantSuccessCriteria': relevantSuccessCriteria,
    'criterionIds': ['criterion_1'],
    'doneCriteria': ['The reporting screen slice is complete.'],
    'outOfScope': ['Do not perform unrelated project work.'],
    'context': ['Use the attached workspace.'],
    'expectedArtifacts': [],
    'gates': [
      {'id': 'no_tool_errors', 'required': true, 'scope': 'task'},
    ],
  };
}

TaskAggregate _taskDocument({String id = 'task_test', String? chatSessionId}) {
  final now = DateTime(2026, 1, 1);
  return TaskAggregate(
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

ProjectAggregate _projectDocument({
  String id = 'project_test',
  String? chatSessionId,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
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

ModelCompletion _commandPlanTaskResponse(
  Map<String, dynamic> arguments, {
  String content = '',
  String reasoning = '',
}) {
  final calls = <ModelToolCall>[
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
  return ModelCompletion(
    content: content,
    reasoning: reasoning,
    toolCalls: calls,
  );
}

ModelCompletion _commandPlanProjectResponse(
  Map<String, dynamic> arguments, {
  String content = '',
  String reasoning = '',
}) {
  final calls = <ModelToolCall>[
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
                'verification_mode': 'mixed',
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
    _toolCall('plan_commit', {
      'summary': arguments['summary'] ?? 'Apply the project plan.',
      'rationale': arguments['rationale'] ?? 'Commit the bounded project plan.',
    }),
  ];
  return ModelCompletion(
    content: content,
    reasoning: reasoning,
    toolCalls: calls,
  );
}

ModelToolCall _toolCall(String name, Map<String, dynamic> arguments) =>
    ModelToolCall(
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
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  }) async => 0;

  @override
  Future<ModelCompletion> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
    return ModelCompletion(content: response);
  }

  @override
  void dispose() {}
}

class _RecordingStreamClient extends ChatClient {
  _RecordingStreamClient() : super(baseUrl: 'http://localhost', model: 'test');

  final Completer<ModelRequestOptions> extraParams = Completer();

  @override
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  }) async => 0;

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async* {
    if (!this.extraParams.isCompleted) {
      this.extraParams.complete(
        extraParams ?? const ModelRequestOptions.empty(),
      );
    }
    yield ChatToken(content: 'Done.');
  }

  @override
  Future<ModelCompletion> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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

Set<String> _toolNames(ModelRequestOptions? extraParams) {
  return {for (final tool in extraParams?.tools ?? const []) tool.id};
}

class _QueueCompletionClient extends ChatClient {
  _QueueCompletionClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<ModelCompletion> _responses;
  var _index = 0;

  @override
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  }) async => 0;

  @override
  Future<ModelCompletion> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  }) async => 0;

  @override
  bool get supportsStreamingCancellation => true;

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) {
    requestEstimates.add(
      ContextEstimator.estimateChatCompletionRequest(
        messages: messages,
        extraParams: extraParams ?? const ModelRequestOptions.empty(),
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
  Future<ModelCompletion> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
    ModelRequestOptions? extraParams,
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
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  }) async => 0;

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
