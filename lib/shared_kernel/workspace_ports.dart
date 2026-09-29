import 'package:hermes/shared_kernel/workspace.dart';

abstract interface class PersistencePort {
  String canonicalWorkspacePath(String workspaceRoot);

  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  );
}

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
