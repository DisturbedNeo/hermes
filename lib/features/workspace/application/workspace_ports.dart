import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/application/sandbox_policy.dart';

enum WorkspaceEntryKind { file, directory, link }

class WorkspaceDirectoryEntry {
  const WorkspaceDirectoryEntry({
    required this.path,
    required this.name,
    required this.kind,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final WorkspaceEntryKind kind;
  final int size;
  final DateTime modified;
}

class WorkspaceFileReadResult {
  const WorkspaceFileReadResult({
    required this.path,
    required this.content,
    required this.bytes,
  });

  final String path;
  final String content;
  final int bytes;
}

class WorkspaceFileWriteResult {
  const WorkspaceFileWriteResult({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

class WorkspaceFilePatchResult {
  const WorkspaceFilePatchResult({
    required this.path,
    required this.replacements,
  });

  final String path;
  final int replacements;
}

class WorkspacePathResult {
  const WorkspacePathResult({required this.path});

  final String path;
}

class WorkspacePathInspectionResult {
  const WorkspacePathInspectionResult({
    required this.path,
    required this.kind,
    required this.size,
  });

  final String path;
  final WorkspaceEntryKind? kind;
  final int size;

  bool get exists => kind != null;
}

class WorkspaceRenameResult {
  const WorkspaceRenameResult({required this.from, required this.to});

  final String from;
  final String to;
}

class WorkspaceSearchMatch {
  const WorkspaceSearchMatch({
    required this.path,
    required this.line,
    required this.preview,
  });

  final String path;
  final int line;
  final String preview;
}

class WorkspaceCommandResult {
  const WorkspaceCommandResult({
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String command;
  final String workingDirectory;
  final int? exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class PersistencePort {
  String canonicalWorkspacePath(String workspaceRoot);

  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  );
}

/// Resolves workspace-relative paths and applies workspace confinement policy.
abstract interface class WorkspacePathPolicyPort {
  Future<String> canonicalRoot(String rootPath);

  Future<WorkspacePath> resolve(
    String rootPath,
    String relativePath, {
    bool mustExist,
    bool directory,
  });
}

/// Performs workspace-confined file operations. It never executes host
/// processes.
abstract interface class WorkspaceFileOperationsPort {
  Future<WorkspacePathInspectionResult> inspectPath(
    String rootPath,
    String relativePath, {
    CancellationToken? cancellationToken,
  });

  Future<List<WorkspaceDirectoryEntry>> listDirectory(
    String rootPath,
    String relativePath, {
    CancellationToken? cancellationToken,
  });

  Future<WorkspaceFileReadResult> readFile(
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

  Future<WorkspaceFileWriteResult> writeFile(
    String rootPath,
    String relativePath,
    String content, {
    CancellationToken? cancellationToken,
  });

  Future<WorkspaceFilePatchResult> patchFile(
    String rootPath,
    String relativePath,
    String oldText,
    String newText, {
    bool replaceAll,
    CancellationToken? cancellationToken,
  });

  Future<WorkspacePathResult> createDirectory(
    String rootPath,
    String relativePath, {
    CancellationToken? cancellationToken,
  });

  Future<WorkspaceRenameResult> renamePath(
    String rootPath,
    String relativePath,
    String newRelativePath, {
    CancellationToken? cancellationToken,
  });

  Future<WorkspacePathResult> deletePath(
    String rootPath,
    String relativePath, {
    bool recursive = false,
    CancellationToken? cancellationToken,
  });

  Future<List<WorkspaceSearchMatch>> searchFiles(
    String rootPath,
    String query, {
    String relativePath,
    CancellationToken? cancellationToken,
  });
}

/// Executes approved host commands. This capability is intentionally separate
/// from workspace file access.
abstract interface class HostCommandExecutionPort {
  Future<WorkspaceCommandResult> runCommand(
    String rootPath, {
    String? command,
    List<String> arguments,
    String workingDirectory,
    CancellationToken? cancellationToken,
  });
}

/// Combined adapter capability used by existing application services. The
/// focused ports above are the preferred dependencies for new services.
abstract interface class WorkspaceSandboxPort
    implements
        WorkspacePathPolicyPort,
        WorkspaceFileOperationsPort,
        HostCommandExecutionPort {}

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
  Future<List<WorkspaceDirectoryEntry>> listDirectory(
    String rootPath,
    String relativePath,
  );
}
