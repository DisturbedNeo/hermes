import 'dart:convert';

import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/tools/calculator_tool.dart';
import 'package:hermes/core/tools/tool.dart';
import 'package:hermes/core/tools/workspace_tools.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

class ToolService {
  ToolService({WorkspaceSandbox? workspaceSandbox})
    : _workspaceSandbox = workspaceSandbox ?? WorkspaceSandbox();

  final WorkspaceSandbox _workspaceSandbox;

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
      return Future.value(jsonEncode({'error': 'Unknown tool: $toolId'}));
    }

    if (tool.requiresWorkspace && context == null) {
      return Future.value(
        jsonEncode({'error': 'This tool requires an active workspace.'}),
      );
    }

    return tool.process(argumentsJson, context: context);
  }
}
