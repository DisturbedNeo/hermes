import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/job_service.dart';
import 'package:hermes/core/services/job_storage_service.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatService system prompts', () {
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

    test('locks prompt changes after saving an empty chat', () async {
      expect(chat.isSystemPromptLocked, isFalse);

      await chat.saveCurrentChat(title: 'Empty saved chat');

      expect(chat.isSystemPromptLocked, isTrue);
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

    test('adds job and phase prompt modules to assembled prompts', () {
      final now = DateTime(2026);
      PromptModule module(String id, String content) {
        return PromptModule(
          id: id,
          name: id,
          category: 'Job',
          content: content,
          priority: 10,
          isBuiltIn: false,
          requiredModuleIds: const [],
          conflictingModuleIds: const [],
          createdAt: now,
          updatedAt: now,
        );
      }

      final preset = PromptPreset(
        id: 'preset',
        name: 'Job preset',
        baseModuleIds: const ['base'],
        optionalModuleIds: const ['selected', 'job', 'phase', 'unused'],
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
          modules: [
            module('base', 'Base behavior.'),
            module('selected', 'Selected chat module.'),
            module('job', 'Job-wide module.'),
            module('phase', 'Phase-specific module.'),
            module('unused', 'Unused module.'),
          ],
          selectedModuleIds: const ['selected'],
        ),
      );

      final systemPrompt = chat.buildSystemPromptForTesting(
        additionalModuleIds: const ['job', 'phase'],
      );

      expect(systemPrompt, contains('Base behavior.'));
      expect(systemPrompt, contains('Selected chat module.'));
      expect(systemPrompt, contains('Job-wide module.'));
      expect(systemPrompt, contains('Phase-specific module.'));
      expect(systemPrompt, isNot(contains('Unused module.')));
    });

    test('uses job and phase prompt modules when running a phase', () async {
      final now = DateTime(2026);
      PromptModule module(String id, String content) {
        return PromptModule(
          id: id,
          name: id,
          category: 'Job',
          content: content,
          priority: 10,
          isBuiltIn: false,
          requiredModuleIds: const [],
          conflictingModuleIds: const [],
          createdAt: now,
          updatedAt: now,
        );
      }

      final preset = PromptPreset(
        id: 'preset',
        name: 'Job preset',
        baseModuleIds: const ['base'],
        optionalModuleIds: const ['job', 'phase'],
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
          modules: [
            module('base', 'Base behavior.'),
            module('job', 'Job-wide module.'),
            module('phase', 'Phase-specific module.'),
          ],
        ),
      );

      final client = _CapturingChatClient();
      serverManager.chatClient = client;

      await chat.attachWorkspace(tempDir.path);
      chat.activeJob = _jobSnapshot(
        jobPromptModules: const ['job'],
        phasePromptModules: const ['phase'],
      );

      await chat.runNextJobPhase();

      expect(client.sawJobModules, isTrue);
      expect(chat.activeJob?.state.status, JobStatus.completed);
      expect(chat.jobModelOutputTitle, 'Job Phase Model Output');
      expect(chat.jobModelOutputText, contains('Phase Executor'));
      expect(chat.jobModelOutputText, contains('phase output'));
    });

    test('supports /refine without creating a job', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_taskBriefJson(title: 'Refined task')),
      ]);

      await chat.send('/refine Build the reporting screen');

      expect(chat.activeJob, isNull);
      expect(chat.messageStore.messages.last.text, contains('Refined task'));
      expect(
        chat.messageStore.messages.last.text,
        contains('Recommended mode: `refine`'),
      );
    });

    test('supports /plan command without running phases', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_taskBriefJson(title: 'Planned task')),
        jsonEncode(_jobSpecJson(title: 'Planned task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      expect(chat.activeJob?.spec.title, 'Planned task');
      expect(chat.activeJob?.state.phaseRuns, isEmpty);
      expect(chat.activeJob?.state.status, JobStatus.planned);
      expect(chat.jobModelOutputTitle, 'Job Creation Model Output');
      expect(chat.jobModelOutputText, contains('Prompt Refiner'));
      expect(chat.jobModelOutputText, contains('Job Planner'));
      expect(chat.jobModelOutputText, contains('Planned task'));
    });

    test('scopes workspace jobs without implicitly saving the chat', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_taskBriefJson(title: 'Scoped task')),
        jsonEncode(_jobSpecJson(title: 'Scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      final transientScopeId = chat.activeJob?.state.chatSessionId;
      final transientJobDir = Directory(
        path.join(tempDir.path, '.agent', 'jobs', chat.activeJob!.spec.id),
      );
      expect(chat.currentChatId, isNull);
      expect(transientScopeId, isNotNull);
      expect(chat.availableJobs, isNotEmpty);
      expect(transientJobDir.existsSync(), isTrue);

      await chat.newChat();

      expect(transientJobDir.existsSync(), isFalse);
      await chat.attachWorkspace(tempDir.path);

      expect(chat.currentChatId, isNull);
      expect(chat.activeJob, isNull);
      expect(chat.availableJobs, isEmpty);
    });

    test('moves transient job scope when the user explicitly saves', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_taskBriefJson(title: 'Saved scoped task')),
        jsonEncode(_jobSpecJson(title: 'Saved scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');

      final transientScopeId = chat.activeJob?.state.chatSessionId;
      expect(chat.currentChatId, isNull);
      expect(transientScopeId, isNotNull);

      final saved = await chat.saveCurrentChat(title: 'Reporting plan');

      expect(chat.currentChatId, saved.id);
      expect(chat.activeJob?.state.chatSessionId, saved.id);
      expect(chat.availableJobs.single.chatSessionId, saved.id);

      await chat.newChat();
      await chat.attachWorkspace(tempDir.path);
      expect(chat.activeJob, isNull);

      await chat.openChat(saved.id);

      expect(chat.activeJob?.spec.title, 'Saved scoped task');
      expect(chat.activeJob?.state.chatSessionId, saved.id);
    });

    test('deletes job folders when a saved chat is deleted', () async {
      serverManager.chatClient = _QueueChatClient([
        jsonEncode(_taskBriefJson(title: 'Deleted scoped task')),
        jsonEncode(_jobSpecJson(title: 'Deleted scoped task')),
      ]);
      await chat.attachWorkspace(tempDir.path);

      await chat.send('/plan Build the reporting screen');
      final saved = await chat.saveCurrentChat(title: 'Deleted plan');
      final jobDir = Directory(
        path.join(tempDir.path, '.agent', 'jobs', chat.activeJob!.spec.id),
      );

      expect(jobDir.existsSync(), isTrue);

      await chat.deleteSavedChat(saved.id);

      expect(await chatLibrary.getChat(saved.id), isNull);
      expect(jobDir.existsSync(), isFalse);
      expect(chat.currentChatId, isNull);
    });

    test(
      'deletes transient job folders when the chat service is disposed',
      () async {
        serverManager.chatClient = _QueueChatClient([
          jsonEncode(_taskBriefJson(title: 'Disposed scoped task')),
          jsonEncode(_jobSpecJson(title: 'Disposed scoped task')),
        ]);
        await chat.attachWorkspace(tempDir.path);

        await chat.send('/plan Build the reporting screen');
        final jobDir = Directory(
          path.join(tempDir.path, '.agent', 'jobs', chat.activeJob!.spec.id),
        );

        expect(chat.currentChatId, isNull);
        expect(jobDir.existsSync(), isTrue);

        await chat.dispose();

        expect(jobDir.existsSync(), isFalse);
      },
    );

    test('supports /continue command for the active job', () async {
      serverManager.chatClient = _CapturingChatClient();
      await chat.attachWorkspace(tempDir.path);
      chat.activeJob = _jobSnapshot();

      await chat.send('/continue');

      expect(chat.activeJob?.state.status, JobStatus.completed);
      expect(
        chat.messageStore.messages.firstWhere((m) => m.text == '/continue'),
        isNotNull,
      );
    });
  });

  group('ChatTabsService system prompt loading', () {
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

    test('loads into unlocked tab and opens a new tab when locked', () async {
      final reviewer = await promptLibrary.createPrompt(
        name: 'Reviewer',
        content: 'Review code carefully.',
      );

      final firstTarget = await tabs.loadSystemPromptIntoActiveChat(reviewer);

      expect(firstTarget, SystemPromptLoadTarget.currentChat);
      expect(tabs.tabs, hasLength(1));
      expect(tabs.activeChat?.currentSystemPromptSnapshot?.id, reviewer.id);
      expect(tabs.activeChat?.messageStore.first.text, reviewer.content);

      tabs.activeChat?.insertMessage('Please review this.', MessageRole.user);

      final architect = await promptLibrary.createPrompt(
        name: 'Architect',
        content: 'Design APIs carefully.',
      );

      final secondTarget = await tabs.loadSystemPromptIntoActiveChat(architect);

      expect(secondTarget, SystemPromptLoadTarget.newTab);
      expect(tabs.tabs, hasLength(2));
      expect(tabs.activeChat?.currentSystemPromptSnapshot?.id, architect.id);
      expect(tabs.activeChat?.messageStore.messages, hasLength(1));
      expect(tabs.activeChat?.messageStore.first.text, architect.content);
    });

    test('loads default preset with workspace rules when attached', () async {
      await tabs.activeChat?.attachWorkspace(tempDir.path);
      final defaultPreset = await promptLibrary.getPreset(
        SystemPromptLibraryService.defaultPresetId,
      );

      final target = await tabs.loadPromptPresetIntoActiveChat(defaultPreset!);

      expect(target, SystemPromptLoadTarget.currentChat);
      final systemText = tabs.activeChat!.messageStore.first.text;
      expect(systemText, contains('You are a helpful assistant.'));
      expect(systemText, contains('This chat has an attached workspace.'));
      expect(systemText, contains(tempDir.path));
    });

    test('loads only selected optional modules for a preset', () async {
      final base = await promptLibrary.createModule(
        name: 'Coding base',
        category: 'Core',
        content: 'You are a senior software engineer.',
        priority: 10,
      );
      final csharp = await promptLibrary.createModule(
        name: 'C# specialist',
        category: 'Capability',
        content: 'You specialise in C#.',
        priority: 20,
      );
      final rust = await promptLibrary.createModule(
        name: 'Rust specialist',
        category: 'Capability',
        content: 'You specialise in Rust.',
        priority: 20,
      );
      final preset = await promptLibrary.createPreset(
        name: 'Coding optional module test',
        baseModuleIds: [base.id],
        optionalModuleIds: [csharp.id, rust.id],
      );

      await tabs.loadPromptPresetIntoActiveChat(
        preset,
        selectedOptionalModuleIds: [csharp.id],
      );

      final systemText = tabs.activeChat!.messageStore.first.text;
      expect(systemText, contains('You are a senior software engineer.'));
      expect(systemText, contains('You specialise in C#.'));
      expect(systemText, isNot(contains('You specialise in Rust.')));
      expect(tabs.activeChat!.currentSystemPromptSnapshot!.selectedModuleIds, [
        csharp.id,
      ]);
    });

    test('deletes saved chat job folders from the chat list path', () async {
      tabs.serverManager.chatClient = _QueueChatClient([
        jsonEncode(_taskBriefJson(title: 'Deleted tab task')),
        jsonEncode(_jobSpecJson(title: 'Deleted tab task')),
      ]);
      await tabs.activeChat?.attachWorkspace(tempDir.path);

      await tabs.activeChat?.send('/plan Build the reporting screen');
      final saved = await tabs.activeChat!.saveCurrentChat(
        title: 'Deleted tab plan',
      );
      final jobId = tabs.activeChat!.activeJob!.spec.id;
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
      final orphaned = _jobSnapshot().copyWith(
        spec: _jobSnapshot().spec.copyWith(id: 'job_orphaned'),
        state: _jobSnapshot().state.copyWith(
          jobId: 'job_orphaned',
          chatSessionId: 'deleted_chat',
        ),
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

JobSnapshot _jobSnapshot({
  List<String> jobPromptModules = const [],
  List<String> phasePromptModules = const [],
}) {
  final now = DateTime(2026, 1, 1);
  const phase = JobPhase(
    id: 'phase_1',
    title: 'Phase 1',
    objective: 'Produce output',
    status: PhaseStatus.pending,
    inputs: [],
    expectedOutputs: [PhaseOutput(path: 'job-output.md', required: true)],
    allowedTools: ['read_file'],
    terminalPolicy: TerminalPolicy.none,
    promptModules: [],
    completionCriteria: ['Output exists'],
    review: ReviewPolicy(required: true, reviewer: ReviewerType.deterministic),
    humanCheckpoint: false,
    retryPolicy: RetryPolicy(maxRetries: 0),
  );
  final resolvedPhase = phase.copyWith(promptModules: phasePromptModules);
  final brief = TaskBrief(
    id: 'task_test',
    createdAt: now,
    updatedAt: now,
    title: 'Test job',
    originalPrompt: 'Run the job',
    objective: 'Run the job',
    successCriteria: const ['Output exists'],
    constraints: const [],
    nonGoals: const [],
    assumptions: const [],
    clarifyingQuestions: const [],
    recommendedMode: ExecutionMode.job,
    recommendedAutonomy: AutonomyLevel.checkpointed,
    requiredOutputs: const [
      RequiredOutput(path: 'job-output.md', required: true),
    ],
    domain: JobDomain.general,
    riskLevel: RiskLevel.low,
  );

  return JobSnapshot(
    taskBrief: brief,
    spec: JobSpec(
      version: 1,
      id: 'job_test',
      title: 'Test job',
      createdAt: now,
      updatedAt: now,
      taskBriefId: brief.id,
      status: JobStatus.planned,
      domain: JobDomain.general,
      autonomy: AutonomyLevel.checkpointed,
      promptModules: jobPromptModules,
      globalConstraints: const [],
      globalSuccessCriteria: const ['Output exists'],
      toolPolicy: const ToolPolicy(defaultAllowed: ['read_file']),
      stopPolicy: const StopPolicy(),
      phases: [resolvedPhase],
    ),
    state: JobState(
      jobId: 'job_test',
      status: JobStatus.planned,
      updatedAt: now,
      completedPhases: const [],
      failedPhases: const [],
      skippedPhases: const [],
      artifacts: const [],
      openQuestions: const [],
      assumptions: const [],
      risks: const [],
      phaseRuns: const [],
      latestSummary: 'Planned',
    ),
  );
}

Map<String, dynamic> _taskBriefJson({required String title}) {
  return {
    'id': 'task_test',
    'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
    'title': title,
    'originalPrompt': 'Build the reporting screen',
    'objective': 'Build the reporting screen',
    'successCriteria': ['Produces a clear implementation brief.'],
    'constraints': ['Stay inside the workspace.'],
    'nonGoals': [],
    'assumptions': ['The current workspace is relevant.'],
    'clarifyingQuestions': [],
    'recommendedMode': 'refine',
    'recommendedAutonomy': 'checkpointed',
    'requiredOutputs': [
      {'path': 'reporting-plan.md', 'required': true},
    ],
    'domain': 'development',
    'riskLevel': 'medium',
  };
}

Map<String, dynamic> _jobSpecJson({required String title}) {
  return {
    'version': 1,
    'id': 'job_model',
    'title': title,
    'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
    'taskBriefId': 'task_test',
    'status': 'planned',
    'domain': 'development',
    'autonomy': 'checkpointed',
    'globalConstraints': ['Stay inside the workspace.'],
    'globalSuccessCriteria': ['Produces a clear implementation brief.'],
    'toolPolicy': {
      'defaultAllowed': ['read_file'],
      'defaultDisallowed': [],
      'terminal': {'allowed': true, 'policy': 'none'},
    },
    'stopPolicy': {'maxPhaseToolCalls': 2},
    'phases': [
      {
        'id': 'plan',
        'title': 'Plan work',
        'objective': 'Create implementation plan.',
        'status': 'pending',
        'inputs': [],
        'expectedOutputs': [
          {'path': 'reporting-plan.md', 'required': true},
        ],
        'allowedTools': ['read_file'],
        'terminalPolicy': 'none',
        'completionCriteria': ['Output exists.'],
        'review': {'required': true, 'reviewer': 'deterministic'},
        'humanCheckpoint': false,
      },
    ],
  };
}

class _CapturingChatClient extends ChatClient {
  _CapturingChatClient() : super(baseUrl: 'http://localhost', model: 'test');

  bool sawJobModules = false;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    final systemText = messages.first.content;
    sawJobModules =
        systemText.contains('Job-wide module.') &&
        systemText.contains('Phase-specific module.');
    return const ChatCompletionResponse(content: 'phase output');
  }

  @override
  void dispose() {}
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
