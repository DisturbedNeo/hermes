import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/managed_lazy_database.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/prompt_library_seed_data.dart';

/// Repository layer for the system prompt library.
///
/// Handles all raw data fetching, JSON mapping, and file-system/SQLite
/// interactions.  Contains zero business logic — it is a pure data-access
/// abstraction over the prompt-preset / prompt-module store.
class SystemPromptLibraryRepository {
  final PreferencesService _preferencesService;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;

  late final ManagedLazyDatabase _database;

  SystemPromptLibraryRepository({
    required PreferencesService preferencesService,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _preferencesService = preferencesService,
       _databaseFactory = databaseFactory ?? databaseFactoryFfi,
       _databasePath = databasePath {
    _database = ManagedLazyDatabase(_open);
  }

  Future<Database> get _db => _database.database;

  Future<void> dispose() => _database.dispose();

  // ── Public CRUD / query methods ────────────────────────────────────────

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
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    String? legacyFullPrompt,
    required bool isBuiltIn,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final row = _presetRow(
      id: id,
      name: name,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions.trim(),
      legacyFullPrompt: _blankToNull(legacyFullPrompt),
      isBuiltIn: isBuiltIn,
      createdAt: now,
      updatedAt: now,
      lastUsedAt: null,
    );

    await db.insert('prompt_presets', row);
    return _presetFromRow(row);
  }

  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
    String? legacyFullPrompt,
    required bool isBuiltIn,
    required DateTime createdAt,
    required DateTime? lastUsedAt,
  }) async {
    final db = await _db;
    final row = _presetRow(
      id: id,
      name: name,
      baseModuleIds: baseModuleIds,
      optionalModuleIds: optionalModuleIds,
      customInstructions: customInstructions.trim(),
      legacyFullPrompt: _blankToNull(legacyFullPrompt),
      isBuiltIn: isBuiltIn,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastUsedAt: lastUsedAt,
    );

    await db.update('prompt_presets', row, where: 'id = ?', whereArgs: [id]);
    return _presetFromRow(row);
  }

  Future<void> deletePreset(String id) async {
    final db = await _db;
    await db.delete('prompt_presets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markPresetUsed(String id) async {
    final db = await _db;
    await db.update(
      'prompt_presets',
      {'last_used_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
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
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required bool isBuiltIn,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final row = _moduleRow(
      id: id,
      name: name,
      category: category,
      content: content.trim(),
      priority: priority,
      isBuiltIn: isBuiltIn,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('prompt_modules', row);
    return _moduleFromRow(row);
  }

  Future<PromptModule> updateModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required bool isBuiltIn,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
    required DateTime createdAt,
  }) async {
    final db = await _db;
    final row = _moduleRow(
      id: id,
      name: name,
      category: category,
      content: content.trim(),
      priority: priority,
      isBuiltIn: isBuiltIn,
      requiredModuleIds: requiredModuleIds,
      conflictingModuleIds: conflictingModuleIds,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );

    await db.update('prompt_modules', row, where: 'id = ?', whereArgs: [id]);
    return _moduleFromRow(row);
  }

  Future<void> deleteModule(String id) async {
    final db = await _db;
    await db.delete('prompt_modules', where: 'id = ?', whereArgs: [id]);
  }

  // ── Seeding & migration ────────────────────────────────────────────────

  Future<void> seedBuiltIns() async {
    final db = await _db;
    await _seedBuiltIns(db);
  }

  Future<void> _seedBuiltIns(DatabaseExecutor db) async {
    final now = DateTime.now();
    final modules = [
      _moduleRow(
        id: BuiltInPromptIds.coreDefaultModule,
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
        id: BuiltInPromptIds.workspaceRulesModule,
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
- Host terminal commands require explicit user approval for this session. They run with the application's host permissions and are not confined to the workspace.
'''
                .trim(),
        priority: 80,
        isBuiltIn: true,
        requiredModuleIds: const [],
        conflictingModuleIds: const [BuiltInPromptIds.workspaceMissingModule],
        createdAt: now,
        updatedAt: now,
      ),
      _moduleRow(
        id: BuiltInPromptIds.workspaceMissingModule,
        name: 'Missing workspace notice',
        category: 'Context',
        content:
            'A workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.',
        priority: 80,
        isBuiltIn: true,
        requiredModuleIds: const [],
        conflictingModuleIds: const [BuiltInPromptIds.workspaceRulesModule],
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
      whereArgs: [BuiltInPromptIds.defaultPreset],
      limit: 1,
    );
    final lastUsedAt = existingDefault.isEmpty
        ? null
        : _nullableDate(existingDefault.single['last_used_at'] as int?);
    await db.insert(
      'prompt_presets',
      _presetRow(
        id: BuiltInPromptIds.defaultPreset,
        name: 'Default',
        baseModuleIds: const [BuiltInPromptIds.coreDefaultModule],
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

  Future<void> seedStarterLibrary() async {
    final db = await _db;
    await _seedStarterLibrary(db);
  }

  Future<void> _seedStarterLibrary(DatabaseExecutor db) async {
    if (await _metaValueDb(db, PromptLibrarySeedData.starterSeedMetaKey) ==
        '1') {
      return;
    }

    final now = DateTime.now();
    for (final seed in PromptLibrarySeedData.starterModules) {
      if (await _idExistsDb(db, 'prompt_modules', seed.id)) continue;

      await db.insert(
        'prompt_modules',
        _moduleRow(
          id: seed.id,
          name: await _uniqueNameForDb(db, 'prompt_modules', seed.name),
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
      if (await _idExistsDb(db, 'prompt_presets', seed.id)) continue;

      await db.insert(
        'prompt_presets',
        _presetRow(
          id: seed.id,
          name: await _uniqueNameForDb(db, 'prompt_presets', seed.name),
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

  Future<void> migrateLegacyPrompts() async {
    final db = await _db;
    await _migrateLegacyPrompts(db);
  }

  Future<void> _migrateLegacyPrompts(DatabaseExecutor db) async {
    if (await _metaValueDb(db, 'legacy_system_prompts_migrated') == '1') {
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

      final name = await _uniqueNameForDb(
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

  // ── Internal helpers (database lifecycle, schema, mapping) ─────────────

  Future<Database> _open() async {
    final dbPath =
        _databasePath ?? await _preferencesService.getFullDatabasePath();
    await Directory(path.dirname(dbPath)).create(recursive: true);

    final db = await _databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async => _createSchema(db),
        onOpen: (db) async => _createSchema(db),
      ),
    );

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

  // ── Private helpers for seeding/migration (database-taking variants) ───

  Future<bool> _idExistsDb(DatabaseExecutor db, String table, String id) async {
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String> _uniqueNameForDb(
    DatabaseExecutor db,
    String table,
    String baseName,
  ) async {
    if (!await _nameExistsDb(db, table, baseName)) return baseName;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$baseName $i';
      if (!await _nameExistsDb(db, table, candidate)) return candidate;
    }
    return '$baseName ${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<bool> _nameExistsDb(
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

  Future<String?> _metaValueDb(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'prompt_library_meta',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }

  // ── Name-unique helpers (public) ───────────────────────────────────────

  Future<void> throwIfNameExists(
    String table,
    String name, {
    String? excludingId,
  }) async {
    final db = await _db;
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

  Future<String> copyNameFor(String table, String baseName) async {
    return uniqueNameFor(table, '$baseName copy');
  }

  Future<String> uniqueNameFor(String table, String baseName) async {
    if (!await nameExists(table, baseName)) return baseName;
    for (var i = 2; i < 1000; i++) {
      final candidate = '$baseName $i';
      if (!await nameExists(table, candidate)) return candidate;
    }
    return '$baseName ${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<bool> nameExists(String table, String name) async {
    final db = await _db;
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ── JSON mapping helpers ───────────────────────────────────────────────

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

  List<String> _stringListJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList();
  }

  // ── Utility helpers ────────────────────────────────────────────────────

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  DateTime _date(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

  DateTime? _nullableDate(int? millis) {
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
