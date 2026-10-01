import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:hermes/features/workspace/application/workspace_ports.dart';

class WorkspaceLockDiagnostics {
  const WorkspaceLockDiagnostics({
    required this.lockPath,
    required this.workspaceRoot,
    required this.owner,
    required this.waited,
    this.stale = false,
  });

  final String lockPath;
  final String workspaceRoot;
  final String? owner;
  final Duration waited;
  final bool stale;

  Map<String, Object?> toMap() => {
    'lock_path': lockPath,
    'workspace_root': workspaceRoot,
    'owner': owner,
    'waited_ms': waited.inMilliseconds,
    'stale': stale,
  };
}

class WorkspaceLockException implements Exception {
  const WorkspaceLockException(this.diagnostics);

  final WorkspaceLockDiagnostics diagnostics;

  @override
  String toString() =>
      'Workspace is locked: ${diagnostics.workspaceRoot} '
      '(owner=${diagnostics.owner ?? 'unknown'}, '
      'waited=${diagnostics.waited.inMilliseconds}ms)';
}

class _WorkspaceLockHandle {
  _WorkspaceLockHandle(this.file, this.owner, {required this.removeParent});

  final File file;
  final String owner;
  final bool removeParent;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map && raw['owner'] == owner) {
        await file.delete();
        if (removeParent) {
          try {
            await file.parent.delete();
          } on FileSystemException {
            // Another operation may have left durable metadata in the
            // directory; never remove that content as part of lock cleanup.
          }
        }
      }
    } on FileSystemException {
      // The workspace may have been removed or another recovery path may
      // already have removed the lock.
    } on FormatException {
      // Do not delete an unreadable lock owned by an unknown process.
    }
  }
}

/// Serialises workspace persistence within this process and across processes.
///
/// The lock file is deliberately a second line of defence: repositories still
/// perform optimistic revision checks, so a writer that bypasses this class
/// cannot silently overwrite a newer snapshot.
class WorkspacePersistenceCoordinator implements PersistencePort {
  WorkspacePersistenceCoordinator({
    this.lockTimeout = const Duration(seconds: 10),
    this.pollInterval = const Duration(milliseconds: 25),
    this.staleLockAge = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration lockTimeout;
  final Duration pollInterval;
  final Duration staleLockAge;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _tails = {};
  final Object _zoneKey = Object();

  @override
  String canonicalWorkspacePath(String workspaceRoot) =>
      path.normalize(path.absolute(workspaceRoot));

  File lockFileFor(String workspaceRoot) => File(
    path.join(
      canonicalWorkspacePath(workspaceRoot),
      '.agent',
      'workspace.lock',
    ),
  );

  @override
  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  ) async {
    final key = canonicalWorkspacePath(workspaceRoot);
    if (Zone.current[_zoneKey] == true) return operation();
    final previous = _tails[key] ?? Future<void>.value();
    final ready = previous.then<void>((_) {}, onError: (_, _) {});
    late final T result;
    final completion = ready.then<void>(
      (_) => runZoned(() async {
        final lock = await _acquire(key);
        try {
          result = await operation();
        } finally {
          await lock.release();
        }
      }, zoneValues: {_zoneKey: true}),
    );
    _tails[key] = completion;
    try {
      await completion;
      return result;
    } finally {
      if (identical(_tails[key], completion)) _tails.remove(key);
    }
  }

  Future<_WorkspaceLockHandle> _acquire(String workspaceRoot) async {
    final lockFile = lockFileFor(workspaceRoot);
    final parentExisted = await lockFile.parent.exists();
    await lockFile.parent.create(recursive: true);
    final started = _clock();
    final owner =
        '${pid}_${started.microsecondsSinceEpoch}_${identityHashCode(this)}';
    String? observedOwner;
    var staleObserved = false;

    while (true) {
      try {
        await lockFile.create(exclusive: true);
        await lockFile.writeAsString(
          jsonEncode({
            'owner': owner,
            'pid': pid,
            'created_at': started.toIso8601String(),
            'workspace_root': workspaceRoot,
          }),
          flush: true,
        );
        return _WorkspaceLockHandle(
          lockFile,
          owner,
          removeParent: !parentExisted,
        );
      } on PathExistsException {
        final state = await _readLock(lockFile);
        observedOwner = state?.owner;
        if (_isStale(lockFile, state)) {
          staleObserved = true;
          try {
            await lockFile.delete();
          } on FileSystemException {
            // Another process may have repaired it; retry the claim.
          }
          continue;
        }

        final waited = _clock().difference(started);
        if (waited >= lockTimeout) {
          throw WorkspaceLockException(
            WorkspaceLockDiagnostics(
              lockPath: lockFile.path,
              workspaceRoot: workspaceRoot,
              owner: observedOwner,
              waited: waited,
              stale: staleObserved,
            ),
          );
        }
        await Future<void>.delayed(pollInterval);
      }
    }
  }

  Future<({String? owner, DateTime? createdAt})?> _readLock(File file) async {
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      return (
        owner: raw['owner']?.toString(),
        createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  bool _isStale(File file, ({String? owner, DateTime? createdAt})? state) {
    final createdAt = state?.createdAt;
    if (createdAt != null) {
      return _clock().difference(createdAt) > staleLockAge;
    }
    try {
      return _clock().difference(file.statSync().modified) > staleLockAge;
    } on FileSystemException {
      return false;
    }
  }
}
