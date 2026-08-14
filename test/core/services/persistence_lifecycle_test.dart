import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/managed_lazy_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('AtomicJsonSnapshotStore write queue', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('hermes_snapshot_');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('commits same-path writes in invocation order', () async {
      const store = AtomicJsonSnapshotStore();
      final file = File('${directory.path}/state.json');
      final first = store.writeMap(file, {
        'version': 1,
        'payload': List.filled(20000, 'first'),
      });
      final second = store.writeMap(file, {'version': 2});

      await Future.wait([first, second]);

      expect((await store.readMap(file))?['version'], 2);
      expect((await store.readMap(store.backupFor(file)))?['version'], 1);
    });

    test('a failed write does not poison the path queue', () async {
      const store = AtomicJsonSnapshotStore();
      final file = File('${directory.path}/state.json');

      await expectLater(
        store.writeMap(file, {'invalid': Object()}),
        throwsA(anything),
      );
      await store.writeMap(file, {'version': 2});

      expect((await store.readMap(file))?['version'], 2);
    });
  });

  group('ManagedLazyDatabase', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('hermes_db_');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    Future<Database> openDatabase() => databaseFactoryFfi.openDatabase(
      '${directory.path}/test.db',
      options: OpenDatabaseOptions(singleInstance: false),
    );

    test('shares concurrent opens and retries after an open failure', () async {
      var attempts = 0;
      final release = Completer<void>();
      final managed = ManagedLazyDatabase(() async {
        attempts++;
        if (attempts == 1) throw StateError('first open failed');
        await release.future;
        return openDatabase();
      });

      await expectLater(managed.database, throwsStateError);
      final first = managed.database;
      final second = managed.database;
      expect(attempts, 2);
      release.complete();

      expect(identical(await first, await second), isTrue);
      await managed.dispose();
    });

    test('closes a database that finishes opening during disposal', () async {
      final opened = await openDatabase();
      final release = Completer<void>();
      final managed = ManagedLazyDatabase(() async {
        await release.future;
        return opened;
      });

      final opening = managed.database;
      final disposing = managed.dispose();
      release.complete();

      await expectLater(opening, throwsStateError);
      await disposing;
      expect(opened.isOpen, isFalse);
      await managed.dispose();
      expect(() => managed.database, throwsStateError);
    });
  });
}
