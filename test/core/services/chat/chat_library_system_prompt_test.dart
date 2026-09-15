import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String databasePath;
  late ChatLibraryService chatLibrary;
  late SystemPromptLibraryRepository promptLibraryRepository;
  late SystemPromptLibraryService promptLibrary;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'hermes_chat_prompts_test_',
    );
    databasePath = path.join(tempDir.path, 'hermes.db');
    final preferences = PreferencesService();
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
  });

  tearDown(() async {
    await chatLibrary.dispose();
    await promptLibrary.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saved chats keep a snapshot of the selected system prompt', () async {
    final module = await promptLibrary.createModule(
      name: 'Reviewer rules',
      category: 'Task',
      content: 'Review code carefully.',
      priority: 10,
    );
    final prompt = await promptLibrary.createPreset(
      name: 'Reviewer',
      baseModuleIds: [module.id],
    );
    final snapshot = await promptLibrary.snapshotForPreset(prompt);

    final saved = await chatLibrary.saveChatSnapshot(
      title: 'Prompted chat',
      messages: [
        Bubble(
          id: 'system',
          role: MessageRole.system,
          text: snapshot.text,
          reasoning: '',
        ),
        const Bubble(
          id: 'user',
          role: MessageRole.user,
          text: 'Check this diff',
          reasoning: '',
        ),
      ],
      modelSnapshot: null,
      workspace: null,
      systemPromptSnapshot: snapshot,
    );

    await promptLibrary.updatePreset(
      id: prompt.id,
      name: 'Reviewer',
      baseModuleIds: [module.id],
      optionalModuleIds: const [],
      customInstructions: 'A later prompt edit.',
    );
    await promptLibrary.deletePreset(prompt.id);

    final restored = await chatLibrary.getChat(saved.id);
    expect(restored?.chat.systemPromptSnapshot?.id, prompt.id);
    expect(restored?.chat.systemPromptSnapshot?.name, 'Reviewer');
    expect(restored?.chat.systemPromptSnapshot?.text, 'Review code carefully.');
  });

  test(
    'creates only canonical saved-chat prompt and session columns',
    () async {
      await chatLibrary.saveChatSnapshot(
        title: 'Canonical columns chat',
        messages: const [],
        modelSnapshot: null,
        workspace: null,
        systemPromptSnapshot: null,
      );
      final db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final columns = await db.rawQuery('PRAGMA table_info(saved_chats)');
      await db.close();

      final names = columns.map((row) => row['name']).toSet();
      expect(names, contains('system_prompt_snapshot_json'));
      expect(names, isNot(contains('system_prompt_id')));
      expect(names, isNot(contains('system_prompt_name')));
      expect(names, isNot(contains('system_prompt_text')));
      expect(names, isNot(contains('workspace_command_approved')));
    },
  );

  test(
    'preserves message creation timestamps when saving and loading',
    () async {
      final createdAt = DateTime(2026, 5, 9, 4, 7);

      final saved = await chatLibrary.saveChatSnapshot(
        title: 'Timestamped chat',
        messages: [
          Bubble(
            id: 'user',
            role: MessageRole.user,
            text: 'Timed message',
            reasoning: '',
            createdAt: createdAt,
          ),
        ],
        modelSnapshot: null,
        workspace: null,
        systemPromptSnapshot: null,
      );

      final restored = await chatLibrary.getChat(saved.id);
      expect(restored?.messages.single.createdAt, createdAt);
    },
  );

  test('saves only changed message rows and keeps FTS in sync', () async {
    final firstCreated = DateTime(2026, 1, 2, 3, 4);
    final secondCreated = DateTime(2026, 2, 3, 4, 5);
    final first = Bubble(
      id: 'first',
      role: MessageRole.user,
      text: 'obsolete-needle',
      reasoning: '',
      createdAt: firstCreated,
    );
    final second = Bubble(
      id: 'second',
      role: MessageRole.assistant,
      text: 'original response',
      reasoning: '',
      createdAt: secondCreated,
    );
    final saved = await chatLibrary.saveChatSnapshot(
      title: 'ZebraTitleToken',
      messages: [first, second],
      modelSnapshot: null,
      workspace: null,
      systemPromptSnapshot: null,
    );
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    final before = await db.query(
      'saved_chat_messages',
      where: 'chat_id = ?',
      whereArgs: [saved.id],
      orderBy: 'position ASC',
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await chatLibrary.saveChatSnapshot(
      chatId: saved.id,
      messages: [first, second],
      modelSnapshot: null,
      workspace: null,
      systemPromptSnapshot: null,
    );
    final unchanged = await db.query(
      'saved_chat_messages',
      where: 'chat_id = ?',
      whereArgs: [saved.id],
      orderBy: 'position ASC',
    );
    expect(
      unchanged.map((row) => row['updated_at']),
      before.map((row) => row['updated_at']),
    );

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await chatLibrary.saveChatSnapshot(
      chatId: saved.id,
      title: 'QuartzTitleToken',
      messages: [
        Bubble(
          id: 'second',
          role: MessageRole.assistant,
          text: 'updated-response-needle',
          reasoning: '',
          createdAt: DateTime(2030),
        ),
        const Bubble(
          id: 'third',
          role: MessageRole.user,
          text: 'new-message-needle',
          reasoning: '',
        ),
      ],
      modelSnapshot: null,
      workspace: null,
      systemPromptSnapshot: null,
    );

    final restored = await chatLibrary.getChat(saved.id);
    expect(restored?.messages.map((message) => message.id), [
      'second',
      'third',
    ]);
    expect(restored?.messages.first.createdAt, secondCreated);
    expect(await chatLibrary.searchChats('obsolete-needle'), isEmpty);
    expect(
      (await chatLibrary.searchChats('updated-response-needle')).single.id,
      saved.id,
    );
    expect(await chatLibrary.searchChats('ZebraTitleToken'), isEmpty);
    expect(
      (await chatLibrary.searchChats('QuartzTitleToken')).single.id,
      saved.id,
    );
  });

  test('rejects duplicate message ids before creating a chat', () async {
    await expectLater(
      chatLibrary.saveChatSnapshot(
        title: 'Invalid chat',
        messages: const [
          Bubble(
            id: 'duplicate',
            role: MessageRole.user,
            text: 'one',
            reasoning: '',
          ),
          Bubble(
            id: 'duplicate',
            role: MessageRole.assistant,
            text: 'two',
            reasoning: '',
          ),
        ],
        modelSnapshot: null,
        workspace: null,
        systemPromptSnapshot: null,
      ),
      throwsArgumentError,
    );
    expect(await chatLibrary.countChats(), 0);
  });
}
