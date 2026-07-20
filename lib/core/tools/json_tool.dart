import 'dart:convert';

import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/tools/tool.dart';

abstract class JsonTool<T extends Object> extends Tool {
  Future<Map<String, dynamic>> run(T input);

  @override
  Future<String> process(String raw, {WorkspaceToolContext? context}) async {
    final map = jsonDecode(raw);
    final input = ModelJson.decode<T>(map);
    final result = await run(input);
    return jsonEncode(result);
  }
}
