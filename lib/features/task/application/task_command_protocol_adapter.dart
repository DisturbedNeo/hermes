import 'dart:convert';

import 'package:hermes/features/task/application/contracts/task_commands.dart';

/// Decodes the editor/model JSON protocol into a typed task command.
abstract final class TaskCommandProtocolAdapter {
  static TaskPlanUpdateCommand decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const FormatException('Task plan update must be an object.');
    }
    return TaskPlanUpdateCommand.fromWire(Map<String, Object?>.from(value));
  }
}
