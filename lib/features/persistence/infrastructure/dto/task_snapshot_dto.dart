import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart';

/// Persistence-only representation of a task document.
class TaskSnapshotDto {
  const TaskSnapshotDto._(this.document);

  factory TaskSnapshotDto.fromAggregate(TaskAggregate task) =>
      TaskSnapshotDto._(TaskSnapshotCodec.encode(task));

  factory TaskSnapshotDto.fromDocument(Map<String, dynamic> document) =>
      TaskSnapshotDto._(Map.unmodifiable(document));

  final Map<String, dynamic> document;

  TaskAggregate toAggregate() => TaskSnapshotCodec.decode(document);
}
