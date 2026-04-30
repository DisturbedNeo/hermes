import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String databasePath;
  late ChatLibraryService chatLibrary;
  late SystemPromptLibraryService promptLibrary;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'hermes_chat_prompts_test_',
    );
    databasePath = path.join(tempDir.path, 'hermes.db');
    final preferences = PreferencesService();
    chatLibrary = ChatLibraryService(
      preferencesService: preferences,
      databasePath: databasePath,
    );
    promptLibrary = SystemPromptLibraryService(
      preferencesService: preferences,
      databasePath: databasePath,
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
    final prompt = await promptLibrary.createPrompt(
      name: 'Reviewer',
      content: 'Review code carefully.',
    );
    final snapshot = prompt.toSnapshot();

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

    await promptLibrary.updatePrompt(
      id: prompt.id,
      name: 'Reviewer',
      content: 'A later prompt edit.',
    );
    await promptLibrary.deletePrompt(prompt.id);

    final restored = await chatLibrary.getChat(saved.id);
    expect(restored?.chat.systemPromptSnapshot?.id, prompt.id);
    expect(restored?.chat.systemPromptSnapshot?.name, 'Reviewer');
    expect(restored?.chat.systemPromptSnapshot?.text, 'Review code carefully.');
  });

  test('falls back to legacy saved-chat prompt columns', () async {
    final saved = await chatLibrary.saveChatSnapshot(
      title: 'Legacy columns chat',
      messages: const [
        Bubble(
          id: 'system',
          role: MessageRole.system,
          text: 'Legacy prompt text.',
          reasoning: '',
        ),
      ],
      modelSnapshot: null,
      workspace: null,
      systemPromptSnapshot: null,
    );

    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.update(
      'saved_chats',
      {
        'system_prompt_snapshot_json': null,
        'system_prompt_id': 'legacy-prompt',
        'system_prompt_name': 'Legacy prompt',
        'system_prompt_text': 'Legacy prompt text.',
      },
      where: 'id = ?',
      whereArgs: [saved.id],
    );
    await db.close();

    final restored = await chatLibrary.getChat(saved.id);
    expect(restored?.chat.systemPromptSnapshot?.id, 'legacy-prompt');
    expect(restored?.chat.systemPromptSnapshot?.name, 'Legacy prompt');
    expect(restored?.chat.systemPromptSnapshot?.text, 'Legacy prompt text.');
  });
}
