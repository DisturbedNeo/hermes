import 'dart:convert';

import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/tools/calculator_tool.dart';
import 'package:hermes/core/tools/tool.dart';
import 'package:hermes/core/tools/tool_error.dart';
import 'package:hermes/core/tools/workspace_tools.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/subagent_service.dart';

class ToolService {
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

  Future<String> execute({
    String toolId = '',
    String argumentsJson = '',
    WorkspaceToolContext? context,
  }) {
    final tool = _toolRegistry[toolId];

    if (tool == null) {
      return Future.value(
        jsonEncode(
          toolErrorPayload(
            code: 'unknown_tool',
            message: 'Unknown tool: $toolId',
            disposition: TaskToolErrorDisposition.advisory,
          ),
        ),
      );
    }

    if (tool.requiresWorkspace && context == null) {
      return Future.value(
        jsonEncode(
          toolErrorPayload(
            code: 'workspace_required',
            message: 'This tool requires an active workspace.',
            disposition: TaskToolErrorDisposition.retryable,
          ),
        ),
      );
    }

    // Ensure subagent service is available in context if we have one
    final effectiveContext = context != null && _subagentService != null
        ? WorkspaceToolContext(
            workspace: context.workspace,
            subagentService: _subagentService,
            cancellationToken: context.cancellationToken,
          )
        : context;

    effectiveContext?.cancellationToken?.throwIfCancelled();
    return tool.process(argumentsJson, context: effectiveContext);
  }
}
