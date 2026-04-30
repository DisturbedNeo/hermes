import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
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
      tabs = ChatTabsService(
        chatLibrary: chatLibrary,
        systemPromptLibrary: promptLibrary,
        toolService: ToolService(),
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
        name: 'Coding',
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
  });
}
