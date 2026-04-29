import 'package:hermes/core/models/workspace.dart';

abstract class Tool {
  abstract final String id;
  abstract final String name;
  abstract final String description;
  abstract final Map<String, dynamic> schema;

  bool get requiresWorkspace => false;

  Future<String> process(String input, {WorkspaceToolContext? context});
}
