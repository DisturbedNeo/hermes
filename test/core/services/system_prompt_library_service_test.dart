import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late String databasePath;
  late SystemPromptLibraryService library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('hermes_prompts_test_');
    databasePath = path.join(tempDir.path, 'hermes.db');
    library = SystemPromptLibraryService(
      preferencesService: PreferencesService(),
      databasePath: databasePath,
    );
  });

  tearDown(() async {
    await library.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('seeds built-in modules and the default preset', () async {
    final modules = await library.listModules();
    final presets = await library.listPresets();

    expect(
      modules.map((module) => module.id),
      contains(SystemPromptLibraryService.coreDefaultModuleId),
    );
    expect(presets.map((preset) => preset.id), [
      SystemPromptLibraryService.defaultPresetId,
    ]);
    expect(presets.single.baseModuleIds, [
      SystemPromptLibraryService.coreDefaultModuleId,
    ]);
  });

  test(
    'creates, searches, updates, marks used, duplicates, and deletes presets and modules',
    () async {
      final module = await library.createModule(
        name: 'Reviewer rules',
        category: 'Task',
        content: 'Review code carefully.',
        priority: 40,
      );

      expect((await library.searchModules('review')).map((m) => m.id), [
        module.id,
      ]);

      final updatedModule = await library.updateModule(
        id: module.id,
        name: 'Strict reviewer rules',
        category: 'Task',
        content: 'Review code very carefully.',
        priority: 35,
        requiredModuleIds: const [
          SystemPromptLibraryService.coreDefaultModuleId,
        ],
        conflictingModuleIds: const [],
      );
      expect(updatedModule.requiredModuleIds, [
        SystemPromptLibraryService.coreDefaultModuleId,
      ]);

      final preset = await library.createPreset(
        name: 'Reviewer',
        baseModuleIds: [updatedModule.id],
        customInstructions: 'Use bullets.',
      );

      final assembled = await library.assemblePreset(preset);
      expect(assembled.text, contains('Review code very carefully.'));
      expect(assembled.text, contains('Use bullets.'));

      await library.markPresetUsed(preset.id);
      final used = await library.getPreset(preset.id);
      expect(used?.lastUsedAt, isNotNull);

      final copy = await library.duplicatePreset(preset.id);
      expect(copy.name, 'Reviewer copy');

      await library.deletePreset(preset.id);
      await library.deleteModule(updatedModule.id);

      expect(await library.getPreset(preset.id), isNull);
      expect(await library.getModule(updatedModule.id), isNull);
    },
  );

  test('assembles preset optional modules only when selected', () async {
    final base = await library.createModule(
      name: 'Coding base',
      category: 'Core',
      content: 'You are a senior engineer.',
      priority: 10,
    );
    final csharp = await library.createModule(
      name: 'C# specialist',
      category: 'Capability',
      content: 'You specialise in C#.',
      priority: 20,
    );
    final rust = await library.createModule(
      name: 'Rust specialist',
      category: 'Capability',
      content: 'You specialise in Rust.',
      priority: 20,
    );
    final preset = await library.createPreset(
      name: 'Coding',
      baseModuleIds: [base.id],
      optionalModuleIds: [csharp.id, rust.id],
    );

    final baseOnly = await library.assemblePreset(preset);
    expect(baseOnly.text, contains('You are a senior engineer.'));
    expect(baseOnly.text, isNot(contains('You specialise in C#.')));
    expect(baseOnly.text, isNot(contains('You specialise in Rust.')));

    final withCSharp = await library.assemblePreset(
      preset,
      selectedOptionalModuleIds: [csharp.id],
    );
    expect(withCSharp.text, contains('You specialise in C#.'));
    expect(withCSharp.text, isNot(contains('You specialise in Rust.')));

    final snapshot = await library.snapshotForPreset(
      preset,
      selectedOptionalModuleIds: [csharp.id],
    );
    expect(snapshot.selectedModuleIds, [csharp.id]);
  });

  test(
    'rejects duplicate preset and module names case-insensitively',
    () async {
      await library.createModule(
        name: 'Reviewer rules',
        category: 'Task',
        content: 'Review code.',
        priority: 40,
      );
      await library.createPreset(name: 'Reviewer');

      expect(
        () => library.createModule(
          name: 'reviewer rules',
          category: 'Task',
          content: 'Other prompt.',
          priority: 50,
        ),
        throwsArgumentError,
      );
      expect(() => library.createPreset(name: 'reviewer'), throwsArgumentError);
    },
  );

  test('migrates legacy whole prompts into legacy presets', () async {
    await library.dispose();

    final db = await databaseFactoryFfi.openDatabase(databasePath);
    await db.execute('''
      CREATE TABLE system_prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_used_at INTEGER
      )
    ''');
    await db.insert('system_prompts', {
      'id': 'legacy-1',
      'name': 'Old prompt',
      'content': 'Legacy instructions.',
      'created_at': 1,
      'updated_at': 2,
      'last_used_at': 3,
    });
    await db.close();

    library = SystemPromptLibraryService(
      preferencesService: PreferencesService(),
      databasePath: databasePath,
    );

    final migrated = await library.getPreset('legacy-1');
    expect(migrated?.name, 'Old prompt');
    expect(migrated?.legacyFullPrompt, 'Legacy instructions.');
    expect(
      (await library.assemblePreset(migrated!)).text,
      'Legacy instructions.',
    );
  });
}
