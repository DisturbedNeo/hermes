import 'package:hermes/core/model_json.dart';
import 'package:hermes/platform/tools/tool.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';

abstract class JsonTool<T extends Object> extends Tool {
  Future<Map<String, dynamic>> run(T input);

  @override
  Future<ToolResult> execute(ToolRequest request) async {
    try {
      final input = ModelJson.decode<T>(request.arguments.toValues());
      return ToolSuccess(ToolPayload(await run(input)));
    } catch (error) {
      return ToolFailure(
        code: 'tool_execution_failed',
        message: error.toString(),
      );
    }
  }
}
