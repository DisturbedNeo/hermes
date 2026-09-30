import 'dart:convert';

import 'package:hermes/platform/tools/calculator_tool.dart';
import 'package:hermes/platform/tools/tool.dart';
import 'package:hermes/platform/tools/workspace_tools.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/subagent_service.dart';

class ToolService implements ToolRegistryPort {
  ToolService({required WorkspaceSandbox workspaceSandbox})
    : _workspaceSandbox = workspaceSandbox;

  final WorkspaceSandbox _workspaceSandbox;
  SubagentService? _subagentService;

  /// Updates the subagent service. Pass null to disable when the LLM server
  /// is unavailable.
  void setSubagentService(SubagentService? service) {
    _subagentService = service;
  }

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
            schema: tool.schema,
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
  /// [execute] remains as the protocol compatibility adapter for model JSON.
  /// New application code should pass [ToolRequest] and receive [ToolResult]
  /// so malformed JSON cannot leak through the feature graph.
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
                  runtimeContext: _subagentService,
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

  Future<String> execute({
    String toolId = '',
    String argumentsJson = '',
    WorkspaceToolContext? context,
  }) {
    final toolContext = context == null
        ? null
        : ToolContext(
            workspace: ToolWorkspace(
              rootPath: context.workspace.rootPath,
              displayName: context.workspace.displayName,
              missing: context.workspace.missing,
              commandExecutionApproved:
                  context.workspace.commandExecutionApproved,
            ),
            permission: _requiredPermission(toolId),
            cancellationToken: context.cancellationToken,
            runtimeContext: _subagentService,
          );
    final arguments = argumentsJson.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(argumentsJson) as Map);
    return executeTyped(
      ToolRequest(toolId: toolId, arguments: arguments, context: toolContext),
    ).then((result) => result.encode());
  }
}
