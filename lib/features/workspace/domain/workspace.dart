import 'package:path/path.dart' as path;

/// Stable workspace identity shared by application, runtime, and adapters.
/// Filesystem operations are intentionally absent from this value object.
class WorkspaceAttachment {
  final String rootPath;
  final String displayName;
  final DateTime lastOpenedAt;
  final bool missing;
  final bool commandExecutionApproved;

  const WorkspaceAttachment({
    required this.rootPath,
    required this.displayName,
    required this.lastOpenedAt,
    this.missing = false,
    this.commandExecutionApproved = false,
  });

  factory WorkspaceAttachment.fromPath(
    String rootPath, {
    DateTime? lastOpenedAt,
    bool commandExecutionApproved = false,
  }) => WorkspaceAttachment(
    rootPath: rootPath,
    displayName: path.basename(rootPath),
    lastOpenedAt: lastOpenedAt ?? DateTime.now(),
    commandExecutionApproved: commandExecutionApproved,
  );

  WorkspaceAttachment copyWith({
    String? rootPath,
    String? displayName,
    DateTime? lastOpenedAt,
    bool? missing,
    bool? commandExecutionApproved,
  }) => WorkspaceAttachment(
    rootPath: rootPath ?? this.rootPath,
    displayName: displayName ?? this.displayName,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    missing: missing ?? this.missing,
    commandExecutionApproved:
        commandExecutionApproved ?? this.commandExecutionApproved,
  );
}
