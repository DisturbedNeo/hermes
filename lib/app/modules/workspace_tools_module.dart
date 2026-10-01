import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/platform/workspace_service.dart';
import 'package:hermes/features/workspace/application/workspace_change_discovery.dart';
import 'package:hermes/features/workspace/application/workspace_discovery.dart';
import 'package:hermes/features/workspace/infrastructure/workspace_change_discovery_service.dart';
import 'package:hermes/features/workspace/infrastructure/workspace_discovery_service.dart';

/// Workspace and tool capabilities. Host process execution is kept behind
/// the platform-owned sandbox and is not exposed as a model or domain detail.
class WorkspaceToolsModule {
  WorkspaceToolsModule._({
    required this.sandbox,
    required this.workspace,
    required this.tools,
    required this.toolProtocol,
    required this.changeDiscovery,
    required this.discovery,
  });

  factory WorkspaceToolsModule.create() {
    final sandbox = WorkspaceSandbox();
    final tools = ToolService(workspaceSandbox: sandbox);
    return WorkspaceToolsModule._(
      sandbox: sandbox,
      workspace: WorkspaceService(sandbox: sandbox),
      tools: tools,
      toolProtocol: ToolProtocolAdapter(registry: tools),
      changeDiscovery: WorkspaceChangeDiscoveryService(commands: sandbox),
      discovery: const WorkspaceDiscoveryProfileService(),
    );
  }

  final WorkspaceSandbox sandbox;
  final WorkspaceService workspace;
  final ToolService tools;
  final ToolProtocolAdapter toolProtocol;
  final WorkspaceChangeDiscoveryPort changeDiscovery;
  final WorkspaceDiscoveryPort discovery;
}
