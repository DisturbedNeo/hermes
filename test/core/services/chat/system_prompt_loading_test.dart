import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/job_system/job_storage_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatService system prompts and jobs', () {
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
      chat = ChatService(
        serverManager: serverManager,
        toolService: ToolService(),
        chatLibrary: chatLibrary,
        workspaceService: WorkspaceService(),
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

    test('supports /refine without creating a job', () async {
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

      expect(chat.activeJob, isNull);
      expect(chat.messageStore.messages.last.text, contains('Refined task'));
      expect(chat.messageStore.messages.last.text, contains('Goal:'));
    });

    test('supports /plan command without running steps', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Planned task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      expect(chat.activeJob?.title, 'Planned task');
      expect(chat.activeJob?.runs, isEmpty);
      expect(chat.activeJob?.status, JobStatus.paused);
      expect(chat.jobModelOutputTitle, 'Job Creation Model Output');
      expect(chat.jobModelOutputText, contains('Job Planner'));
    });

    test('supports /job command by creating and running steps', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Runnable task')),
        jsonEncode({
          'status': 'completed',
          'summary': 'Step complete.',
          'memoryUpdate': 'Work finished.',
        }),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/job Build the reporting screen');

      expect(chat.activeJob?.status, JobStatus.completed);
      expect(chat.activeJob?.runs.single.summary, 'Step complete.');
    });

    test(
      'renders job model reasoning and tool calls as chat bubbles',
      () async {
        serverManager.chatClient = _QueueCompletionClient([
          ChatCompletionResponse(
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

        await chat.send('/job Build the reporting screen');

        final plannerBubble = chat.messageStore.messages.firstWhere(
          (message) => message.text.contains('Visible task'),
        );
        expect(plannerBubble.reasoning, contains('Planning rationale.'));

        final toolBubble = chat.messageStore.messages.firstWhere(
          (message) => message.tools.isNotEmpty,
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
        expect(chat.activeJob?.runs.single.summary, 'Calculated result.');
      },
    );

    test('cancels a stuck job run and keeps the transcript and job', () async {
      final client = _StuckJobClient(_planJson(title: 'Cancellable task'));
      serverManager.chatClient = client;
      await chat.attachWorkspace(tempDir.path);

      final sendFuture = chat.send('/job Build the reporting screen');
      await client.stepStarted.future.timeout(const Duration(seconds: 2));

      expect(chat.jobBusy, isTrue);
      expect(
        chat.messageStore.messages.any(
          (message) => message.reasoning.contains('Still thinking.'),
        ),
        isTrue,
      );

      await chat.cancelJobRun();
      await sendFuture.timeout(const Duration(seconds: 2));

      expect(client.stepCancelled.isCompleted, isTrue);
      expect(chat.jobBusy, isFalse);
      expect(chat.jobCancellationRequested, isFalse);
      expect(chat.activeJob?.status, JobStatus.paused);
      expect(chat.activeJob?.currentStepId, 'build');
      expect(chat.activeJob?.steps.single.status, JobStepStatus.pending);
      expect(chat.activeJob?.runs.single.status, JobRunStatus.cancelled);
      expect(chat.activeJob?.runs.single.summary, contains('cancelled'));
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
            'jobs',
            chat.activeJob!.id,
            'job.json',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('scopes transient jobs and deletes them on new chat', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      final job = chat.activeJob!;
      final jobDir = Directory(
        path.join(tempDir.path, '.agent', 'jobs', job.id),
      );
      expect(chat.currentChatId, isNull);
      expect(job.chatSessionId, isNotNull);
      expect(jobDir.existsSync(), isTrue);

      await chat.newChat();

      expect(jobDir.existsSync(), isFalse);
    });

    test('moves transient job scope when the chat is saved', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Saved scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      final saved = await chat.saveCurrentChat(title: 'Reporting plan');

      expect(chat.activeJob?.chatSessionId, saved.id);
      expect(chat.availableJobs.single.chatSessionId, saved.id);

      await chat.newChat();
      await chat.attachWorkspace(tempDir.path);
      expect(chat.activeJob, isNull);

      await chat.openChat(saved.id);

      expect(chat.activeJob?.title, 'Saved scoped task');
      expect(chat.activeJob?.chatSessionId, saved.id);
    });

    test('supports /continue command for the active job', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'Continued step.',
          'memoryUpdate': 'Done.',
        }),
      ]);
      await chat.attachWorkspace(tempDir.path);
      chat.activeJob = _jobDocument();
      await JobStorageService().saveSnapshot(tempDir.path, chat.activeJob!);

      await chat.send('/continue');

      expect(chat.activeJob?.status, JobStatus.completed);
      expect(
        chat.messageStore.messages.firstWhere((m) => m.text == '/continue'),
        isNotNull,
      );
    });
  });

  group('ChatTabsService job cleanup', () {
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
      final toolService = ToolService();
      tabs = ChatTabsService(
        chatLibrary: chatLibrary,
        systemPromptLibrary: promptLibrary,
        toolService: toolService,
        jobService: JobService(toolService: toolService),
        workspaceService: WorkspaceService(),
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

    test('deletes saved chat job folders from the chat list path', () async {
      tabs.serverManager.chatClient = _QueueChatClient([
        jsonEncode(_planJson(title: 'Deleted tab task')),
      ]);
      await tabs.activeChat?.attachWorkspace(tempDir.path);

      await tabs.activeChat?.send('/plan Build the reporting screen');
      final saved = await tabs.activeChat!.saveCurrentChat(
        title: 'Deleted tab plan',
      );
      final jobId = tabs.activeChat!.activeJob!.id;
      final jobDir = Directory(
        path.join(tempDir.path, '.agent', 'jobs', jobId),
      );

      expect(jobDir.existsSync(), isTrue);

      await tabs.deleteSavedChat(saved.id);

      expect(await chatLibrary.getChat(saved.id), isNull);
      expect(jobDir.existsSync(), isFalse);
      expect(tabs.activeChat?.currentChatId, isNull);
    });

    test('deletes orphaned chat-scoped jobs when disposed', () async {
      await tabs.activeChat?.attachWorkspace(tempDir.path);
      final orphaned = _jobDocument(
        id: 'job_orphaned',
        chatSessionId: 'deleted_chat',
      );
      await JobStorageService().saveSnapshot(tempDir.path, orphaned);
      final jobDir = Directory(
        path.join(tempDir.path, '.agent', 'jobs', 'job_orphaned'),
      );

      expect(jobDir.existsSync(), isTrue);

      await tabs.dispose();

      expect(jobDir.existsSync(), isFalse);
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

JobDocument _jobDocument({String id = 'job_test', String? chatSessionId}) {
  final now = DateTime(2026, 1, 1);
  return JobDocument(
    id: id,
    title: 'Test job',
    originalPrompt: 'Run the job',
    goal: 'Run the job',
    constraints: const [],
    successCriteria: const ['Finish'],
    steps: const [
      JobStep(
        id: 'step_1',
        title: 'Step 1',
        objective: 'Do the work',
        instructions: ['Work carefully'],
        mayEditFiles: false,
        artifacts: [],
        status: JobStepStatus.pending,
      ),
    ],
    status: JobStatus.paused,
    currentStepId: 'step_1',
    memorySummary: '',
    runs: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: now,
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

class _StuckJobClient extends ChatClient {
  _StuckJobClient(this._plan)
    : super(baseUrl: 'http://localhost', model: 'test');

  final Map<String, dynamic> _plan;
  final Completer<void> stepStarted = Completer<void>();
  final Completer<void> stepCancelled = Completer<void>();
  var _streamCalls = 0;

  @override
  bool get supportsStreamingCancellation => true;

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) {
    _streamCalls++;
    final controller = StreamController<ChatToken>(sync: true);

    if (_streamCalls == 1) {
      controller.onListen = () {
        controller.add(ChatToken(content: jsonEncode(_plan)));
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
