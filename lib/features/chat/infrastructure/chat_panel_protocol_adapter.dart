import 'dart:convert';

import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';

/// Encodes panel documents for legacy UI/protocol consumers.
///
/// JSON remains confined to this adapter; chat, task, and project application
/// ports exchange typed aggregates and read models only.
class ChatPanelProtocolAdapter {
  const ChatPanelProtocolAdapter();

  String encodeTask(Task task) =>
      '${const JsonEncoder.withIndent('  ').convert(ModelJson.encode(task))}\n';

  String encodeProject(ProjectAggregate project) =>
      '${const JsonEncoder.withIndent('  ').convert(ModelJson.encode(project))}\n';
}
