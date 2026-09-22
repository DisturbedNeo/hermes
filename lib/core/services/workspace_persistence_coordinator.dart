import 'dart:async';

import 'package:path/path.dart' as path;

/// Coordinates all persistence operations for a workspace within this Dart
/// process. It intentionally does not provide cross-process locking.
class WorkspacePersistenceCoordinator {
  final Map<String, Future<void>> _tails = {};
  final Object _zoneKey = Object();

  String canonicalWorkspacePath(String workspaceRoot) =>
      path.normalize(path.absolute(workspaceRoot));

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
        result = await operation();
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
}
