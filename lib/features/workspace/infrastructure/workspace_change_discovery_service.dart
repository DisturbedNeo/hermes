import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_change_discovery.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

/// Reads repository changes through the typed host-command capability.
class WorkspaceChangeDiscoveryService implements WorkspaceChangeDiscoveryPort {
  const WorkspaceChangeDiscoveryService({required this.commands});

  final HostCommandExecutionPort commands;

  @override
  Future<WorkspaceChangeSet> discover(
    WorkspaceAttachment workspace, {
    CancellationToken? cancellationToken,
  }) async {
    final result = await commands.runCommand(
      workspace.rootPath,
      command: 'git',
      arguments: const [
        '-C',
        '.',
        'status',
        '--porcelain=v1',
        '--untracked-files=no',
      ],
      workingDirectory: '.',
      cancellationToken: cancellationToken,
    );
    if (result.exitCode != 0) {
      return const WorkspaceChangeSet(isRepository: false);
    }
    final changedFiles = result.stdout
        .split('\n')
        .map((line) => line.length > 3 ? line.substring(3).trim() : '')
        .where((line) => line.isNotEmpty)
        .take(80)
        .toList(growable: false);
    return WorkspaceChangeSet(isRepository: true, changedFiles: changedFiles);
  }
}
