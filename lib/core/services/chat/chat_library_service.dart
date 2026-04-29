import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ChatLibraryService extends ChangeNotifier {
  final PreferencesService _preferencesService;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;

  Database? _database;
  Future<Database>? _opening;
  bool _disposed = false;

  ChatLibraryService({
    required PreferencesService preferencesService,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _preferencesService = preferencesService,
       _databaseFactory = databaseFactory ?? databaseFactoryFfi,
       _databasePath = databasePath {
    sqfliteFfiInit();
  }

  Future<List<SavedChat>> listChats() async {
    final db = await _db;
    final rows = await db.query('saved_chats', orderBy: 'updated_at DESC');

    return rows.map(_savedChatFromRow).toList();
  }

  Future<List<SavedChat>> searchChats(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return listChats();

    final db = await _db;
    final match = _ftsQuery(trimmed);
    if (match != null) {
      try {
        final rows = await db.rawQuery(
          '''
          SELECT DISTINCT c.*
          FROM saved_chats c
          JOIN saved_chat_search s ON s.chat_id = c.id
          WHERE saved_chat_search MATCH ?
          ORDER BY c.updated_at DESC
          ''',
          [match],
        );
        return rows.map(_savedChatFromRow).toList();
      } catch (_) {
        // Fall through to LIKE search if the platform SQLite build rejects FTS.
      }
    }

    final like = '%${trimmed.toLowerCase()}%';
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT c.*
      FROM saved_chats c
      LEFT JOIN saved_chat_messages m ON m.chat_id = c.id
      WHERE lower(c.title) LIKE ?
         OR lower(m.text) LIKE ?
         OR lower(m.reasoning) LIKE ?
      ORDER BY c.updated_at DESC
      ''',
      [like, like, like],
    );

    return rows.map(_savedChatFromRow).toList();
  }

  Future<SavedChatSnapshot?> getChat(String chatId) async {
    final db = await _db;
    final chatRows = await db.query(
      'saved_chats',
      where: 'id = ?',
      whereArgs: [chatId],
      limit: 1,
    );

    if (chatRows.isEmpty) return null;

    final messageRows = await db.query(
      'saved_chat_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'position ASC',
    );

    return SavedChatSnapshot(
      chat: _savedChatFromRow(chatRows.single),
      messages: messageRows.map(_bubbleFromRow).toList(),
    );
  }

  Future<SavedChat> saveChatSnapshot({
    required List<Bubble> messages,
    required ModelConfigurationSnapshot? modelSnapshot,
    required WorkspaceAttachment? workspace,
    String? chatId,
    String? title,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    late SavedChat saved;

    await db.transaction((txn) async {
      final existing = chatId == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'saved_chats',
              where: 'id = ?',
              whereArgs: [chatId],
              limit: 1,
            );

      final id = chatId ?? uuid.v7();
      final createdAt = existing.isEmpty
          ? now
          : _date(existing.single['created_at'] as int);
      final lastOpenedAt = existing.isEmpty
          ? null
          : _nullableDate(existing.single['last_opened_at'] as int?);
      final resolvedTitle = (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : existing.isEmpty
          ? _deriveTitle(messages)
          : existing.single['title'] as String;
      final modelJson = modelSnapshot == null
          ? null
          : jsonEncode(modelSnapshot.toJson());
      final workspaceLastOpenedAt =
          workspace?.lastOpenedAt.millisecondsSinceEpoch;

      await txn.insert('saved_chats', {
        'id': id,
        'title': resolvedTitle,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'last_opened_at': lastOpenedAt?.millisecondsSinceEpoch,
        'model_snapshot_json': modelJson,
        'workspace_root_path': workspace?.rootPath,
        'workspace_display_name': workspace?.displayName,
        'workspace_last_opened_at': workspaceLastOpenedAt,
        'workspace_command_approved':
            workspace?.commandExecutionApproved == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        'saved_chat_messages',
        where: 'chat_id = ?',
        whereArgs: [id],
      );

      final batch = txn.batch();
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        batch.insert('saved_chat_messages', {
          'chat_id': id,
          'message_id': message.id,
          'role': message.role.wire,
          'text': message.text,
          'reasoning': message.reasoning,
          'tools_json': _toolsToJson(message.tools),
          'position': i,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);

      await _refreshSearchIndex(txn, id, resolvedTitle, messages);

      saved = SavedChat(
        id: id,
        title: resolvedTitle,
        createdAt: createdAt,
        updatedAt: now,
        lastOpenedAt: lastOpenedAt,
        modelSnapshot: modelSnapshot,
        workspace: workspace,
      );
    });

    notifyListeners();
    return saved;
  }

  Future<void> renameChat(String chatId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'saved_chats',
        {'title': trimmed, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [chatId],
      );

      final messageRows = await txn.query(
        'saved_chat_messages',
        where: 'chat_id = ?',
        whereArgs: [chatId],
        orderBy: 'position ASC',
      );
      await _refreshSearchIndex(
        txn,
        chatId,
        trimmed,
        messageRows.map(_bubbleFromRow).toList(),
      );
    });

    notifyListeners();
  }

  Future<void> deleteChat(String chatId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('saved_chats', where: 'id = ?', whereArgs: [chatId]);
      await txn.delete(
        'saved_chat_search',
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );
    });

    notifyListeners();
  }

  Future<void> markOpened(String chatId) async {
    final db = await _db;
    await db.update(
      'saved_chats',
      {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [chatId],
    );
    notifyListeners();
  }

  Future<int> countChats() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM saved_chats');
    return rows.first['count'] as int? ?? 0;
  }

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
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onOpen: (db) async {
          await _createSchema(db);
        },
      ),
    );

    _database = db;
    _opening = null;
    return db;
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_chats (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_opened_at INTEGER,
        model_snapshot_json TEXT,
        workspace_root_path TEXT,
        workspace_display_name TEXT,
        workspace_last_opened_at INTEGER,
        workspace_command_approved INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _ensureColumn(db, 'saved_chats', 'workspace_root_path', 'TEXT');
    await _ensureColumn(db, 'saved_chats', 'workspace_display_name', 'TEXT');
    await _ensureColumn(
      db,
      'saved_chats',
      'workspace_last_opened_at',
      'INTEGER',
    );
    await _ensureColumn(
      db,
      'saved_chats',
      'workspace_command_approved',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_chat_messages (
        chat_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        reasoning TEXT NOT NULL,
        tools_json TEXT NOT NULL,
        position INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (chat_id, message_id),
        FOREIGN KEY (chat_id) REFERENCES saved_chats(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_chat_messages_chat_position '
      'ON saved_chat_messages(chat_id, position)',
    );

    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS saved_chat_search USING fts5(
        chat_id UNINDEXED,
        message_id UNINDEXED,
        title,
        body
      )
    ''');
  }

  Future<void> _refreshSearchIndex(
    Transaction txn,
    String chatId,
    String title,
    List<Bubble> messages,
  ) async {
    await txn.delete(
      'saved_chat_search',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );

    final batch = txn.batch();
    batch.insert('saved_chat_search', {
      'chat_id': chatId,
      'message_id': '',
      'title': title,
      'body': title,
    });

    for (final message in messages) {
      batch.insert('saved_chat_search', {
        'chat_id': chatId,
        'message_id': message.id,
        'title': title,
        'body': '${message.text}\n${message.reasoning}',
      });
    }

    await batch.commit(noResult: true);
  }

  SavedChat _savedChatFromRow(Map<String, Object?> row) {
    final modelJson = row['model_snapshot_json'] as String?;
    final workspaceRoot = row['workspace_root_path'] as String?;
    final workspaceLastOpenedAt = row['workspace_last_opened_at'] as int?;
    return SavedChat(
      id: row['id'] as String,
      title: row['title'] as String,
      createdAt: _date(row['created_at'] as int),
      updatedAt: _date(row['updated_at'] as int),
      lastOpenedAt: _nullableDate(row['last_opened_at'] as int?),
      modelSnapshot: modelJson == null || modelJson.isEmpty
          ? null
          : ModelConfigurationSnapshot.fromJson(
              jsonDecode(modelJson) as Map<String, dynamic>,
            ),
      workspace: workspaceRoot == null || workspaceRoot.isEmpty
          ? null
          : WorkspaceAttachment(
              rootPath: workspaceRoot,
              displayName:
                  row['workspace_display_name'] as String? ??
                  path.basename(workspaceRoot),
              lastOpenedAt:
                  _nullableDate(workspaceLastOpenedAt) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              commandExecutionApproved:
                  (row['workspace_command_approved'] as int? ?? 0) == 1,
            ),
    );
  }

  Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Bubble _bubbleFromRow(Map<String, Object?> row) {
    return Bubble(
      id: row['message_id'] as String,
      role: _roleFromWire(row['role'] as String),
      text: row['text'] as String? ?? '',
      reasoning: row['reasoning'] as String? ?? '',
      tools: _toolsFromJson(row['tools_json'] as String? ?? '{}'),
    );
  }

  String _deriveTitle(List<Bubble> messages) {
    final first = messages
        .where((m) => m.role != MessageRole.system && m.text.trim().isNotEmpty)
        .map((m) => m.text.trim().replaceAll(RegExp(r'\s+'), ' '))
        .firstOrNull;

    if (first == null) return 'Untitled chat';
    return first.length <= 64 ? first : '${first.substring(0, 61)}...';
  }

  String _toolsToJson(Map<int, BubbleToolCall> tools) {
    return jsonEncode(
      tools.map(
        (index, tool) => MapEntry('$index', {
          'id': tool.id,
          'name': tool.name,
          'arguments': tool.arguments,
          'result': tool.result,
        }),
      ),
    );
  }

  Map<int, BubbleToolCall> _toolsFromJson(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map((index, value) {
      final map = value as Map<String, dynamic>;
      return MapEntry(
        int.parse(index),
        BubbleToolCall(
          id: map['id'] as String?,
          name: map['name'] as String?,
          arguments: map['arguments'] as String?,
          result: map['result'] as String?,
        ),
      );
    });
  }

  String? _ftsQuery(String raw) {
    final terms = RegExp(
      r'[A-Za-z0-9_]+',
    ).allMatches(raw).map((m) => m.group(0)).whereType<String>().toList();
    if (terms.isEmpty) return null;
    return terms.map((term) => '$term*').join(' ');
  }

  MessageRole _roleFromWire(String wire) {
    return switch (wire) {
      'user' => MessageRole.user,
      'assistant' => MessageRole.assistant,
      'system' => MessageRole.system,
      'tool' => MessageRole.tool,
      _ => MessageRole.user,
    };
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
