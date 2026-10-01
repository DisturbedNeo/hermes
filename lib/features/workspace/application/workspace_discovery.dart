import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';

/// Application capability for collecting bounded, read-only workspace facts.
///
/// Filesystem traversal, manifest parsing, and discovery budgets are owned by
/// infrastructure. Application and runtime services depend only on this
/// typed result-producing port.
abstract interface class WorkspaceDiscoveryPort {
  Future<WorkspaceDiscoveryProfile> collect({
    required WorkspaceAttachment workspace,
    Iterable<String> priorityPaths,
    String goalContext,
    CancellationToken? cancellationToken,
  });
}
