import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Typed result of optional repository-change discovery.
class WorkspaceChangeSet {
  const WorkspaceChangeSet({
    required this.isRepository,
    this.changedFiles = const [],
  });

  final bool isRepository;
  final List<String> changedFiles;
}

/// Application capability for bounded, read-only workspace change discovery.
/// Process and filesystem details belong to the infrastructure implementation.
abstract interface class WorkspaceChangeDiscoveryPort {
  Future<WorkspaceChangeSet> discover(
    WorkspaceAttachment workspace, {
    CancellationToken? cancellationToken,
  });
}
