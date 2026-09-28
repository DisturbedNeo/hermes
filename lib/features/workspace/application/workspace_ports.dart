import 'package:hermes/features/workspace/domain/workspace.dart';

/// Persistence coordination port shared by project and task adapters.
abstract interface class PersistencePort {
  String canonicalWorkspacePath(String workspaceRoot);

  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  );
}

/// Application port for selecting and remembering a workspace.
abstract interface class WorkspacePort {
  Future<WorkspaceAttachment> attach(String folderPath);

  Future<WorkspaceAttachment> restore({
    required String rootPath,
    required String displayName,
    required DateTime lastOpenedAt,
  });

  Future<List<WorkspaceAttachment>> recentWorkspaces();

  Future<void> remember(WorkspaceAttachment workspace);
}
