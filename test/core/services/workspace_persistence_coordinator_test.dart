import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/shared_kernel/workspace_persistence_coordinator.dart';

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('hermes-lock-');
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  test('serializes concurrent writers and releases the lock', () async {
    final coordinator = WorkspacePersistenceCoordinator(
      pollInterval: const Duration(milliseconds: 1),
    );
    var active = 0;
    var maximum = 0;

    Future<void> write() => coordinator.synchronized(workspace.path, () async {
      active++;
      maximum = maximum < active ? active : maximum;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      active--;
    });

    await Future.wait([write(), write(), write()]);
    expect(maximum, 1);
    expect(await coordinator.lockFileFor(workspace.path).exists(), isFalse);
  });

  test('reports a live foreign owner after timeout', () async {
    final coordinator = WorkspacePersistenceCoordinator(
      lockTimeout: const Duration(milliseconds: 10),
      pollInterval: const Duration(milliseconds: 1),
      staleLockAge: const Duration(hours: 1),
    );
    final lock = coordinator.lockFileFor(workspace.path);
    await lock.parent.create(recursive: true);
    await lock.writeAsString(
      jsonEncode({
        'owner': 'foreign-process',
        'pid': 999,
        'created_at': DateTime.now().toIso8601String(),
      }),
    );

    await expectLater(
      coordinator.synchronized(workspace.path, () async {}),
      throwsA(
        isA<WorkspaceLockException>().having(
          (error) => error.diagnostics.owner,
          'owner',
          'foreign-process',
        ),
      ),
    );
    expect(await lock.exists(), isTrue);
  });

  test(
    'repairs a stale lock and records stale diagnostics internally',
    () async {
      final coordinator = WorkspacePersistenceCoordinator(
        lockTimeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 1),
        staleLockAge: const Duration(seconds: 1),
      );
      final lock = coordinator.lockFileFor(workspace.path);
      await lock.parent.create(recursive: true);
      await lock.writeAsString(
        jsonEncode({
          'owner': 'dead-process',
          'created_at': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
        }),
      );

      var ran = false;
      await coordinator.synchronized(workspace.path, () async => ran = true);
      expect(ran, isTrue);
      expect(await lock.exists(), isFalse);
    },
  );
}
