import 'dart:convert';

import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/tools/tool.dart';

abstract class JsonTool<T> extends Tool {
  T fromJson(Map<String, dynamic> json);
  Future<Map<String, dynamic>> run(T input);

  @override
  Future<String> process(String raw, {WorkspaceToolContext? context}) async {
    final map = jsonDecode(raw);
    final input = fromJson(map);
    final result = await run(input);
    return jsonEncode(result);
  }
}
