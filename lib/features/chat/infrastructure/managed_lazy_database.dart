import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Owns one lazily opened database and makes opening/disposal races explicit.
class ManagedLazyDatabase {
  ManagedLazyDatabase(this._open);

  final Future<Database> Function() _open;
  Database? _database;
  Future<Database>? _opening;
  bool _disposed = false;

  Future<Database> get database {
    if (_disposed) throw StateError('Database repository is disposed.');
    final database = _database;
    if (database != null) return Future.value(database);
    return _opening ??= _openAndAdopt();
  }

  Future<Database> _openAndAdopt() async {
    try {
      final database = await _open();
      if (_disposed) {
        await database.close();
        throw StateError('Database repository was disposed while opening.');
      }
      _database = database;
      return database;
    } finally {
      _opening = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // Failed opens and disposal-during-open are already fully cleaned up.
      }
    }

    final database = _database;
    _database = null;
    if (database != null) await database.close();
  }
}
