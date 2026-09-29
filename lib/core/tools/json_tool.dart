import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/tools/tool.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';

abstract class JsonTool<T extends Object> extends Tool {
  Future<Map<String, dynamic>> run(T input);

  @override
  Future<ToolResult> execute(ToolRequest request) async {
    try {
      final input = ModelJson.decode<T>(request.arguments);
      return ToolSuccess(await run(input));
    } catch (error) {
      return ToolFailure(
        code: 'tool_execution_failed',
        message: error.toString(),
      );
    }
  }
}
