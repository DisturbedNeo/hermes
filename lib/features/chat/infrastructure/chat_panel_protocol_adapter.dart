import 'dart:convert';

import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Encodes panel documents for presentation JSON consumers.
///
/// JSON remains confined to this adapter; chat, task, and project application
/// ports exchange typed aggregates and read models only.
class ChatPanelProtocolAdapter {
  const ChatPanelProtocolAdapter();

  String encodeTask(TaskAggregate task) =>
      '${const JsonEncoder.withIndent('  ').convert(ModelJson.encode(task))}\n';

  String encodeProject(ProjectAggregate project) =>
      '${const JsonEncoder.withIndent('  ').convert(ModelJson.encode(project))}\n';
}
