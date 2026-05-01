import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/prompt_library_seed_data.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SystemPromptLibraryService extends ChangeNotifier {
  static const String coreDefaultModuleId = BuiltInPromptIds.coreDefaultModule;
  static const String workspaceRulesModuleId =
      BuiltInPromptIds.workspaceRulesModule;
  static const String workspaceMissingModuleId =
      BuiltInPromptIds.workspaceMissingModule;
  static const String defaultPresetId = BuiltInPromptIds.defaultPreset;

  final PreferencesService _preferencesService;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  final PromptAssembler _assembler;

  Database? _database;
  Future<Database>? _opening;
  bool _disposed = false;

  SystemPromptLibraryService({
    required PreferencesService preferencesService,
    DatabaseFactory? databaseFactory,
    String? databasePath,
    PromptAssembler assembler = const PromptAssembler(),
  }) : _preferencesService = preferencesService,
       _databaseFactory = databaseFactory ?? databaseFactoryFfi,
       _databasePath = databasePath,
       _assembler = assembler {
    sqfliteFfiInit();
  }

  Future<List<PromptPreset>> listPresets() async {
    final db = await _db;
    final rows = await db.query(
      'prompt_presets',
      orderBy: 'COALESCE(last_used_at, updated_at) DESC, name COLLATE NOCASE',
    );
    return rows.map(_presetFromRow).toList();
  }

  Future<List<PromptPreset>> searchPresets(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return listPresets();

    final db = await _db;
    final like = '%${trimmed.toLowerCase()}%';
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM prompt_presets
      WHERE lower(name) LIKE ?
         OR lower(custom_instructions) LIKE ?
         OR lower(legacy_full_prompt) LIKE ?
      ORDER BY COALESCE(last_used_at, updated_at) DESC, name COLLATE NOCASE
      ''',
      [like, like, like],
    );
    return rows.map(_presetFromRow).toList();
  }

  Future<PromptPreset?> getPreset(String id) async {
    final db = await _db;
    final rows = await db.query(
      'prompt_presets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _presetFromRow(rows.single);
  }

  Future<PromptPreset> createPreset({
    required String name,
    List<String> baseModuleIds = const [],
    List<String> optionalModuleIds = const [],
    String customInstructions = '',
    String? legacyFullPrompt,
  }) async {
    final trimmedName = _validatedName(name);
    final db = await _db;
    await _throwIfNameExists(db, 'prompt_presets', trimmedName);

    final now = DateTime.now();
    final row = _presetRow(
      id: uuid.v7(),
      name: trimmedName,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions.trim(),
      legacyFullPrompt: _blankToNull(legacyFullPrompt),
      isBuiltIn: false,
      createdAt: now,
      updatedAt: now,
      lastUsedAt: null,
    );

    await db.insert('prompt_presets', row);
    notifyListeners();
    return _presetFromRow(row);
  }

  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    String? legacyFullPrompt,
  }) async {
    final existing = await getPreset(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'Prompt preset not found');
    }
    if (existing.isBuiltIn) {
      throw StateError('Built-in presets cannot be edited');
    }

    final trimmedName = _validatedName(name);
    final db = await _db;
    await _throwIfNameExists(
      db,
      'prompt_presets',
      trimmedName,
      excludingId: id,
    );

    final now = DateTime.now();
    final row = _presetRow(
      id: id,
      name: trimmedName,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions.trim(),
      legacyFullPrompt: _blankToNull(legacyFullPrompt),
      isBuiltIn: existing.isBuiltIn,
      createdAt: existing.createdAt,
      updatedAt: now,
      lastUsedAt: existing.lastUsedAt,
    );

    await db.update('prompt_presets', row, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
    return _presetFromRow(row);
  }

  Future<PromptPreset> duplicatePreset(String id) async {
    final source = await getPreset(id);
    if (source == null) {
      throw ArgumentError.value(id, 'id', 'Prompt preset not found');
    }

    final db = await _db;
    final name = await _copyNameFor(db, 'prompt_presets', source.name);
    return createPreset(
      name: name,
      baseModuleIds: source.baseModuleIds,
      optionalModuleIds: source.optionalModuleIds,
      customInstructions: source.customInstructions,
      legacyFullPrompt: source.legacyFullPrompt,
    );
  }

  Future<void> deletePreset(String id) async {
    final preset = await getPreset(id);
    if (preset?.isBuiltIn == true) {
      throw StateError('Built-in presets cannot be deleted');
    }

    final db = await _db;
    await db.delete('prompt_presets', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> markPresetUsed(String id) async {
    final db = await _db;
    final updated = await db.update(
      'prompt_presets',
      {'last_used_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated > 0) notifyListeners();
  }

  Future<List<PromptModule>> listModules() async {
    final db = await _db;
    final rows = await db.query(
      'prompt_modules',
      orderBy: 'priority ASC, category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(_moduleFromRow).toList();
  }

  Future<List<PromptModule>> searchModules(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return listModules();

    final db = await _db;
    final like = '%${trimmed.toLowerCase()}%';
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM prompt_modules
      WHERE lower(name) LIKE ?
         OR lower(category) LIKE ?
         OR lower(content) LIKE ?
      ORDER BY priority ASC, category COLLATE NOCASE, name COLLATE NOCASE
      ''',
      [like, like, like],
    );
    return rows.map(_moduleFromRow).toList();
  }

  Future<PromptModule?> getModule(String id) async {
    final db = await _db;
    final rows = await db.query(
      'prompt_modules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _moduleFromRow(rows.single);
  }

  Future<PromptModule> createModule({
    required String name,
    required String category,
    required String content,
    required int priority,
    List<String> requiredModuleIds = const [],
    List<String> conflictingModuleIds = const [],
  }) async {
    final trimmedName = _validatedName(name);
    final trimmedCategory = _validatedName(category);
    final trimmedContent = _validatedContent(content);
    final db = await _db;
    await _throwIfNameExists(db, 'prompt_modules', trimmedName);

    final now = DateTime.now();
    final row = _moduleRow(
      id: uuid.v7(),
      name: trimmedName,
      category: trimmedCategory,
      content: trimmedContent,
      priority: priority,
      isBuiltIn: false,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('prompt_modules', row);
    notifyListeners();
    return _moduleFromRow(row);
  }

  Future<PromptModule> updateModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  }) async {
    final existing = await getModule(id);
    if (existing == null) {
      throw ArgumentError.value(id, 'id', 'Prompt module not found');
    }
    if (existing.isBuiltIn) {
      throw StateError('Built-in modules cannot be edited');
    }

    final trimmedName = _validatedName(name);
    final trimmedCategory = _validatedName(category);
    final trimmedContent = _validatedContent(content);
    final db = await _db;
    await _throwIfNameExists(
      db,
      'prompt_modules',
      trimmedName,
      excludingId: id,
    );

    final row = _moduleRow(
      id: id,
      name: trimmedName,
      category: trimmedCategory,
      content: trimmedContent,
      priority: priority,
      isBuiltIn: false,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );

    await db.update('prompt_modules', row, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
    return _moduleFromRow(row);
  }

  Future<PromptModule> duplicateModule(String id) async {
    final source = await getModule(id);
    if (source == null) {
      throw ArgumentError.value(id, 'id', 'Prompt module not found');
    }

    final db = await _db;
    final name = await _copyNameFor(db, 'prompt_modules', source.name);
    return createModule(
      name: name,
      category: source.category,
      content: source.content,
      priority: source.priority,
      requiredModuleIds: source.requiredModuleIds,
      conflictingModuleIds: source.conflictingModuleIds,
    );
  }

  Future<void> deleteModule(String id) async {
    final module = await getModule(id);
    if (module?.isBuiltIn == true) {
      throw StateError('Built-in modules cannot be deleted');
    }

    final db = await _db;
    await db.delete('prompt_modules', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<PromptAssemblyResult> assemblePreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
    WorkspaceAttachment? workspace,
    String? currentUserRequest,
  }) async {
    final modules = await listModules();
    final selectedModuleIds = _selectedOptionalIdsFor(
      preset,
      selectedOptionalModuleIds,
    );
    return _assembler.assemble(
      PromptAssemblyRequest(
        preset: preset,
        availableModules: modules,
        selectedModuleIds: selectedModuleIds,
        autoModuleIds: _autoModuleIdsFor(workspace),
        workspaceRootPath: workspace?.rootPath,
        workspaceMissing: workspace?.missing ?? false,
        commandExecutionApproved: workspace?.commandExecutionApproved == true,
        currentUserRequest: currentUserRequest,
      ),
    );
  }

  Future<SystemPromptSnapshot> snapshotForPreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds = const [],
    WorkspaceAttachment? workspace,
    String? currentUserRequest,
  }) async {
    final modules = await listModules();
    final selectedModuleIds = _selectedOptionalIdsFor(
      preset,
      selectedOptionalModuleIds,
    );
    final result = _assembler.assemble(
      PromptAssemblyRequest(
        preset: preset,
        availableModules: modules,
        selectedModuleIds: selectedModuleIds,
        autoModuleIds: _autoModuleIdsFor(workspace),
        workspaceRootPath: workspace?.rootPath,
        workspaceMissing: workspace?.missing ?? false,
        commandExecutionApproved: workspace?.commandExecutionApproved == true,
        currentUserRequest: currentUserRequest,
      ),
    );

    return SystemPromptSnapshot(
      id: preset.id,
      name: preset.name,
      text: result.text,
      preset: preset,
      modules: modules,
      selectedModuleIds: selectedModuleIds,
      diagnostics: result.diagnostics,
    );
  }

  Future<List<SavedSystemPrompt>> listPrompts() async {
    final presets = await listPresets();
    return Future.wait(presets.map(_savedPromptForPreset));
  }

  Future<List<SavedSystemPrompt>> searchPrompts(String query) async {
    final presets = await searchPresets(query);
    return Future.wait(presets.map(_savedPromptForPreset));
  }

  Future<SavedSystemPrompt?> getPrompt(String id) async {
    final preset = await getPreset(id);
    return preset == null ? null : _savedPromptForPreset(preset);
  }

  Future<SavedSystemPrompt> createPrompt({
    required String name,
    required String content,
  }) async {
    final preset = await createPreset(name: name, legacyFullPrompt: content);
    return _savedPromptForPreset(preset);
  }

  Future<SavedSystemPrompt> updatePrompt({
    required String id,
    required String name,
    required String content,
  }) async {
    final preset = await getPreset(id);
    if (preset == null) {
      throw ArgumentError.value(id, 'id', 'System prompt not found');
    }
    final updated = await updatePreset(
      id: id,
      name: name,
      baseModuleIds: preset.baseModuleIds,
      optionalModuleIds: preset.optionalModuleIds,
      customInstructions: preset.customInstructions,
      legacyFullPrompt: content,
    );
    return _savedPromptForPreset(updated);
  }

  Future<SavedSystemPrompt> duplicatePrompt(String id) async {
    final preset = await duplicatePreset(id);
    return _savedPromptForPreset(preset);
  }

  Future<void> markUsed(String id) => markPresetUsed(id);

  Future<void> deletePrompt(String id) => deletePreset(id);

  Future<Database> get _db {
    if (_database != null) return Future.value(_database);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final dbPath =
        _databasePath ?? await _preferencesService.getFullDatabasePath();
    await Directory(path.dirname(dbPath)).create(recursive: true);

    final db = await _databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, version) async => _createSchema(db),
        onOpen: (db) async => _createSchema(db),
      ),
    );

    _database = db;
    _opening = null;
    return db;
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_used_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS prompt_library_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS prompt_modules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        category TEXT NOT NULL,
        content TEXT NOT NULL,
        priority INTEGER NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        required_module_ids_json TEXT NOT NULL,
        conflicting_module_ids_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS prompt_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        base_module_ids_json TEXT NOT NULL,
        optional_module_ids_json TEXT NOT NULL,
        custom_instructions TEXT NOT NULL,
        legacy_full_prompt TEXT,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_used_at INTEGER
      )
    ''');

    await _seedBuiltIns(db);
    await _migrateLegacyPrompts(db);
    await _seedStarterLibrary(db);
  }

  Future<void> _seedBuiltIns(DatabaseExecutor db) async {
    final now = DateTime.now();
    final modules = [
      _moduleRow(
        id: coreDefaultModuleId,
        name: 'Helpful assistant',
        category: 'Core',
        content: 'You are a helpful assistant.',
        priority: 0,
        isBuiltIn: true,
        requiredModuleIds: const [],
        conflictingModuleIds: const [],
        createdAt: now,
        updatedAt: now,
      ),
      _moduleRow(
        id: workspaceRulesModuleId,
        name: 'Workspace rules',
        category: 'Context',
        content:
            '''
This chat has an attached workspace. The workspace root is:
{{workspaceRoot}}

Workspace rules:
- Use workspace tools for file and folder operations.
- Only operate inside the attached workspace and use workspace-relative paths.
- Inspect relevant files before editing them.
- Prefer small, precise changes.
- Explain destructive file operations before performing them.
- Terminal commands are guarded and may be unavailable unless the user enables them for this chat.
'''
                .trim(),
        priority: 80,
        isBuiltIn: true,
        requiredModuleIds: const [],
        conflictingModuleIds: const [workspaceMissingModuleId],
        createdAt: now,
        updatedAt: now,
      ),
      _moduleRow(
        id: workspaceMissingModuleId,
        name: 'Missing workspace notice',
        category: 'Context',
        content:
            'A workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.',
        priority: 80,
        isBuiltIn: true,
        requiredModuleIds: const [],
        conflictingModuleIds: const [workspaceRulesModuleId],
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final module in modules) {
      await db.insert(
        'prompt_modules',
        module,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final existingDefault = await db.query(
      'prompt_presets',
      where: 'id = ?',
      whereArgs: [defaultPresetId],
      limit: 1,
    );
    final lastUsedAt = existingDefault.isEmpty
        ? null
        : _nullableDate(existingDefault.single['last_used_at'] as int?);
    await db.insert(
      'prompt_presets',
      _presetRow(
        id: defaultPresetId,
        name: 'Default',
        baseModuleIds: const [coreDefaultModuleId],
        optionalModuleIds: const [],
        customInstructions: '',
        legacyFullPrompt: null,
        isBuiltIn: true,
        createdAt: existingDefault.isEmpty
            ? now
            : _date(existingDefault.single['created_at'] as int),
        updatedAt: now,
        lastUsedAt: lastUsedAt,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _seedStarterLibrary(DatabaseExecutor db) async {
    if (await _metaValue(db, PromptLibrarySeedData.starterSeedMetaKey) == '1') {
      return;
    }

    final now = DateTime.now();
    for (final seed in PromptLibrarySeedData.starterModules) {
      if (await _idExists(db, 'prompt_modules', seed.id)) continue;

      await db.insert(
        'prompt_modules',
        _moduleRow(
          id: seed.id,
          name: await _uniqueNameFor(db, 'prompt_modules', seed.name),
          category: seed.category,
          content: seed.content.trim(),
          priority: seed.priority,
          isBuiltIn: false,
          requiredModuleIds: seed.requiredModuleIds,
          conflictingModuleIds: seed.conflictingModuleIds,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    for (final seed in PromptLibrarySeedData.starterPresets) {
      if (await _idExists(db, 'prompt_presets', seed.id)) continue;

      await db.insert(
        'prompt_presets',
        _presetRow(
          id: seed.id,
          name: await _uniqueNameFor(db, 'prompt_presets', seed.name),
          baseModuleIds: seed.baseModuleIds,
          optionalModuleIds: seed.optionalModuleIds,
          customInstructions: seed.customInstructions.trim(),
          legacyFullPrompt: null,
          isBuiltIn: false,
          createdAt: now,
          updatedAt: now,
          lastUsedAt: null,
        ),
      );
    }

    await db.insert('prompt_library_meta', {
      'key': PromptLibrarySeedData.starterSeedMetaKey,
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _migrateLegacyPrompts(DatabaseExecutor db) async {
    if (await _metaValue(db, 'legacy_system_prompts_migrated') == '1') {
      return;
    }

    final rows = await db.query('system_prompts', orderBy: 'created_at ASC');
    for (final row in rows) {
      final id = row['id'] as String;
      final exists = await db.query(
        'prompt_presets',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (exists.isNotEmpty) continue;

      final name = await _uniqueNameFor(
        db,
        'prompt_presets',
        row['name'] as String,
      );
      await db.insert(
        'prompt_presets',
        _presetRow(
          id: id,
          name: name,
          baseModuleIds: const [],
          optionalModuleIds: const [],
          customInstructions: '',
          legacyFullPrompt: row['content'] as String,
          isBuiltIn: false,
          createdAt: _date(row['created_at'] as int),
          updatedAt: _date(row['updated_at'] as int),
          lastUsedAt: _nullableDate(row['last_used_at'] as int?),
        ),
      );
    }

    await db.insert('prompt_library_meta', {
      'key': 'legacy_system_prompts_migrated',
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SavedSystemPrompt> _savedPromptForPreset(PromptPreset preset) async {
    final content = preset.isLegacy
        ? preset.legacyFullPrompt!.trim()
        : (await assemblePreset(preset)).text;
    return SavedSystemPrompt(
      id: preset.id,
      name: preset.name,
      content: content,
      createdAt: preset.createdAt,
      updatedAt: preset.updatedAt,
      lastUsedAt: preset.lastUsedAt,
    );
  }

  List<String> _autoModuleIdsFor(WorkspaceAttachment? workspace) {
    if (workspace == null) return const [];
    return workspace.missing
        ? const [workspaceMissingModuleId]
        : const [workspaceRulesModuleId];
  }

  List<String> _selectedOptionalIdsFor(
    PromptPreset preset,
    List<String> selectedOptionalModuleIds,
  ) {
    final optionalIds = preset.optionalModuleIds.toSet();
    final seen = <String>{};
    return [
      for (final id in selectedOptionalModuleIds)
        if (optionalIds.contains(id) && seen.add(id)) id,
    ];
  }

  Map<String, Object?> _moduleRow({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required bool isBuiltIn,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return {
      'id': id,
      'name': name,
      'category': category,
      'content': content,
      'priority': priority,
      'is_builtin': isBuiltIn ? 1 : 0,
      'required_module_ids_json': jsonEncode(requiredModuleIds),
      'conflicting_module_ids_json': jsonEncode(conflictingModuleIds),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  Map<String, Object?> _presetRow({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    required String? legacyFullPrompt,
    required bool isBuiltIn,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? lastUsedAt,
  }) {
    return {
      'id': id,
      'name': name,
      'base_module_ids_json': jsonEncode(baseModuleIds),
      'optional_module_ids_json': jsonEncode(optionalModuleIds),
      'custom_instructions': customInstructions,
      'legacy_full_prompt': legacyFullPrompt,
      'is_builtin': isBuiltIn ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'last_used_at': lastUsedAt?.millisecondsSinceEpoch,
    };
  }

  PromptModule _moduleFromRow(Map<String, Object?> row) {
    return PromptModule(
      id: row['id'] as String,
      name: row['name'] as String,
      category: row['category'] as String,
      content: row['content'] as String,
      priority: row['priority'] as int,
      isBuiltIn: (row['is_builtin'] as int? ?? 0) == 1,
      requiredModuleIds: _stringListJson(
        row['required_module_ids_json'] as String? ?? '[]',
      ),
      conflictingModuleIds: _stringListJson(
        row['conflicting_module_ids_json'] as String? ?? '[]',
      ),
      createdAt: _date(row['created_at'] as int),
      updatedAt: _date(row['updated_at'] as int),
    );
  }

  PromptPreset _presetFromRow(Map<String, Object?> row) {
    return PromptPreset(
      id: row['id'] as String,
      name: row['name'] as String,
      baseModuleIds: _stringListJson(
        row['base_module_ids_json'] as String? ?? '[]',
      ),
      optionalModuleIds: _stringListJson(
        row['optional_module_ids_json'] as String? ?? '[]',
      ),
      customInstructions: row['custom_instructions'] as String? ?? '',
      legacyFullPrompt: row['legacy_full_prompt'] as String?,
      isBuiltIn: (row['is_builtin'] as int? ?? 0) == 1,
      createdAt: _date(row['created_at'] as int),
      updatedAt: _date(row['updated_at'] as int),
      lastUsedAt: _nullableDate(row['last_used_at'] as int?),
    );
  }

  Future<void> _throwIfNameExists(
    DatabaseExecutor db,
    String table,
    String name, {
    String? excludingId,
  }) async {
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: excludingId == null
          ? 'name = ? COLLATE NOCASE'
          : 'name = ? COLLATE NOCASE AND id <> ?',
      whereArgs: excludingId == null ? [name] : [name, excludingId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw ArgumentError.value(name, 'name', 'Name already exists');
    }
  }

  Future<String> _copyNameFor(
    DatabaseExecutor db,
    String table,
    String baseName,
  ) async {
    return _uniqueNameFor(db, table, '$baseName copy');
  }

  Future<String> _uniqueNameFor(
    DatabaseExecutor db,
    String table,
    String baseName,
  ) async {
    if (!await _nameExists(db, table, baseName)) return baseName;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$baseName $i';
      if (!await _nameExists(db, table, candidate)) return candidate;
    }
    return '$baseName ${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<bool> _nameExists(
    DatabaseExecutor db,
    String table,
    String name,
  ) async {
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _idExists(DatabaseExecutor db, String table, String id) async {
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String?> _metaValue(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'prompt_library_meta',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  List<String> _stringListJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList();
  }

  String _validatedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name cannot be empty');
    }
    return trimmed;
  }

  String _validatedContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(content, 'content', 'Content cannot be empty');
    }
    return trimmed;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  DateTime _date(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

  DateTime? _nullableDate(int? millis) {
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final db = _database;
    _database = null;
    if (db != null) {
      await db.close();
    }
    super.dispose();
  }
}
