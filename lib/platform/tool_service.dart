import 'package:hermes/platform/tools/calculator_tool.dart';
import 'package:hermes/platform/tools/tool.dart';
import 'package:hermes/platform/tools/workspace_tools.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/tools/application/subagent_service.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

class ToolService implements ToolRegistryPort {
  ToolService({
    required WorkspaceSandboxPort workspaceSandbox,
    SubagentService? subagentService,
  }) : _workspaceSandbox = workspaceSandbox,
       _subagentService = subagentService;

  final WorkspaceSandboxPort _workspaceSandbox;
  final SubagentService? _subagentService;
  late final List<Tool> _globalTools = [CalculatorTool()];

  late final List<Tool> _workspaceTools = [
    ListDirectoryTool(_workspaceSandbox),
    ReadFileTool(_workspaceSandbox),
    WriteFileTool(_workspaceSandbox),
    PatchFileTool(_workspaceSandbox),
    SearchFilesTool(_workspaceSandbox),
    CreateDirectoryTool(_workspaceSandbox),
    RenamePathTool(_workspaceSandbox),
    DeletePathTool(_workspaceSandbox),
    RunCommandTool(_workspaceSandbox),
  ];

  late final Map<String, Tool> _toolRegistry = {
    for (Tool t in [..._globalTools, ..._workspaceTools]) t.id: t,
  };

  Tool? getTool(String name) {
    return _toolRegistry[name];
  }

  @override
  List<ToolDefinition> getToolDefinitions({
    List<String> ids = const [],
    bool includeWorkspaceTools = false,
  }) {
    final tools = [
      ..._globalTools,
      if (includeWorkspaceTools) ..._workspaceTools,
    ];
    return tools
        .where((tool) => ids.isEmpty || ids.contains(tool.id))
        .map(
          (tool) => ToolDefinition(
            id: tool.id,
            name: tool.name,
            description: tool.description,
            schema: ToolSchema(tool.schema),
          ),
        )
        .toList();
  }

  List<String> defaultToolIds({required bool includeWorkspaceTools}) {
    return getToolDefinitions(
      includeWorkspaceTools: includeWorkspaceTools,
    ).map((tool) => tool.id).toList();
  }

  /// Typed application boundary for tool execution.
  ///
  /// Executes a validated typed request. Wire JSON is decoded by
  /// [ToolProtocolAdapter] before it reaches this service.
  @override
  Future<ToolResult> executeTyped(ToolRequest request) async {
    final context = request.context;
    final requiredPermission = _requiredPermission(request.toolId);
    if (requiredPermission != ToolPermission.none && context == null) {
      return const ToolFailure(
        code: 'permission_denied',
        message: 'This tool requires an active workspace context.',
      );
    }
    if (context != null && !context.allows(requiredPermission)) {
      return ToolFailure(
        code: 'permission_denied',
        message:
            'Permission ${requiredPermission.name} is required for ${request.toolId}.',
      );
    }
    if (requiredPermission != ToolPermission.none &&
        context?.workspace == null) {
      return const ToolFailure(
        code: 'workspace_required',
        message: 'A workspace is required for this tool.',
      );
    }
    try {
      context?.cancellationToken?.throwIfCancelled();
      final tool = _toolRegistry[request.toolId];
      if (tool == null) {
        return ToolFailure(
          code: 'unknown_tool',
          message: 'Unknown tool: ${request.toolId}',
        );
      }
      final result = await tool.execute(
        request.copyWith(
          context: context == null
              ? null
              : ToolContext(
                  workspace: context.workspace,
                  permission: context.permission,
                  cancellationToken: context.cancellationToken,
                  subagentService: context.subagentService ?? _subagentService,
                ),
        ),
      );
      context?.cancellationToken?.throwIfCancelled();
      return result;
    } on OperationCancelledException {
      return const ToolFailure(
        code: 'cancelled',
        message: 'Tool execution was cancelled.',
      );
    } catch (error) {
      return ToolFailure(
        code: 'tool_execution_failed',
        message: error.toString(),
      );
    }
  }

  ToolPermission _requiredPermission(String toolId) => switch (toolId) {
    'run_command' => ToolPermission.executeCommand,
    'write_file' ||
    'patch_file' ||
    'create_directory' ||
    'rename_path' ||
    'delete_path' => ToolPermission.writeWorkspace,
    'list_directory' ||
    'read_file' ||
    'search_files' => ToolPermission.readWorkspace,
    _ => ToolPermission.none,
  };

  @override
  ToolPermission permissionFor(String toolId) => _requiredPermission(toolId);
}
