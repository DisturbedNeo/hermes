import 'package:hermes/core/models/task.dart';

class TaskSummary {
  final String id;
  final String title;
  final String? chatSessionId;
  final String? projectId;
  final TaskStatus status;
  final DateTime updatedAt;
  final String? currentPhaseId;

  const TaskSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.currentPhaseId,
    this.chatSessionId,
    this.projectId,
  });
}
