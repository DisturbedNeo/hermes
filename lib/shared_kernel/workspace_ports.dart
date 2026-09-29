import 'package:hermes/shared_kernel/workspace.dart';

abstract interface class PersistencePort {
  String canonicalWorkspacePath(String workspaceRoot);

  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  );
}

abstract interface class WorkspacePort {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);

  Future<WorkspaceAttachment> attach(String folderPath);

  Future<WorkspaceAttachment> restore({
    required String rootPath,
    required String displayName,
    required DateTime lastOpenedAt,
  });

  Future<List<WorkspaceAttachment>> recentWorkspaces();

  Future<void> remember(WorkspaceAttachment workspace);
}

/// Presentation needs only the observable workspace list and a safe directory
/// listing; the concrete sandbox remains owned by the platform adapter.
abstract interface class WorkspacePresentationPort implements WorkspacePort {
  Future<List<Map<String, dynamic>>> listDirectory(
    String rootPath,
    String relativePath,
  );
}
