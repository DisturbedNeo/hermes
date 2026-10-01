import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';

export 'package:hermes/features/workspace/domain/workspace.dart'
    show WorkspaceAttachment;

/// Capability supplied to workspace tools without coupling workspace
/// contracts to the concrete model/subagent implementation.
abstract interface class WorkspaceSubagentCapability {
  Future<String> extract({
    required String fileContent,
    required String extractionRequest,
    String filePath = '',
    int maxTokens = 2048,
  });
}

class WorkspaceToolContext {
  final WorkspaceAttachment workspace;
  final WorkspaceSubagentCapability? subagentService;
  final CancellationToken? cancellationToken;

  const WorkspaceToolContext({
    required this.workspace,
    this.subagentService,
    this.cancellationToken,
  });
}
