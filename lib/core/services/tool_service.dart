import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/tools/calculator_tool.dart';
import 'package:hermes/core/tools/tool.dart';

class ToolService {
  final List<Tool> _tools = [
    CalculatorTool(),
  ];

  late final Map<String, Tool> _toolRegistry = {
    for (Tool t in _tools) t.id: t,
  };

  Tool? getTool(String name) {
    return _toolRegistry[name];
  }

  List<ToolDefinition> getToolDefinitions({ List<String> ids = const [] }) {
    return _tools.where((tool) => ids.isEmpty || ids.contains(tool.id)).map((tool) => ToolDefinition(id: tool.id, name: tool.name, description: tool.description, schema: tool.schema)).toList();
  }

  Future<String> execute({ String toolId = '', String argumentsJson = '' }) {
    final tool = _toolRegistry[toolId];

    if (tool == null) {
      return Future.value('');
    }

    return tool.process(argumentsJson);
  }
}
