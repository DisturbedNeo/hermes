import 'dart:convert';

import 'package:hermes/features/project/application/contracts/project_commands.dart';

/// Decodes the editor/model JSON protocol into a typed project command.
abstract final class ProjectCommandProtocolAdapter {
  static ProjectUpdateCommand decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const FormatException('Project update must be an object.');
    }
    return ProjectUpdateCommand.fromWire(Map<String, Object?>.from(value));
  }
}
