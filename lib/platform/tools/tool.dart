import 'package:hermes/features/tools/application/tool_contracts.dart';

abstract class Tool {
  abstract final String id;
  abstract final String name;
  abstract final String description;
  abstract final Map<String, dynamic> schema;

  bool get requiresWorkspace => false;

  Future<ToolResult> execute(ToolRequest request);
}
