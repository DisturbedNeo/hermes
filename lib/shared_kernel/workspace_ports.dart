import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/sandbox_policy.dart';

abstract interface class PersistencePort {
  String canonicalWorkspacePath(String workspaceRoot);

  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  );
}

/// Typed capability boundary for workspace-confined I/O.
abstract interface class WorkspaceSandboxPort {
  Future<String> canonicalRoot(String rootPath);

  Future<WorkspacePath> resolve(
    String rootPath,
    String relativePath, {
    bool mustExist,
    bool directory,
  });

  Future<List<Map<String, dynamic>>> listDirectory(
    String rootPath,
    String relativePath, {
    CancellationToken? cancellationToken,
  });

  Future<Map<String, dynamic>> readFile(
    String rootPath,
    String relativePath, {
    CancellationToken? cancellationToken,
  });

  Future<String> readFilePreview(
    String rootPath,
    String relativePath, {
    required int maxChars,
    CancellationToken? cancellationToken,
  });

  Future<Map<String, dynamic>> writeFile(
    String rootPath,
    String relativePath,
    String content, {
    CancellationToken? cancellationToken,
  });

  Future<Map<String, dynamic>> runCommand(
    String rootPath, {
    String? command,
    List<String> arguments,
    String workingDirectory,
    CancellationToken? cancellationToken,
  });
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
