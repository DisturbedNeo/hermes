import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Persistence-only representation of a task document.
class TaskSnapshotDto {
  const TaskSnapshotDto._(this.document);

  factory TaskSnapshotDto.fromAggregate(Task task) => TaskSnapshotDto._(
    ModelJson.encode(task.copyWith(persistenceRevision: 0))
      ..remove('persistenceRevision'),
  );

  factory TaskSnapshotDto.fromDocument(Map<String, dynamic> document) =>
      TaskSnapshotDto._(Map.unmodifiable(document));

  final Map<String, dynamic> document;

  Task toAggregate() => ModelJson.decode<Task>(document);
}
