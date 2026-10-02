import 'package:hermes/features/persistence/infrastructure/dto/task_snapshot_dto.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Converts between the task domain boundary and its durable DTO.
class TaskPersistenceAdapter {
  const TaskPersistenceAdapter();

  TaskSnapshotDto toDto(TaskAggregate task) =>
      TaskSnapshotDto.fromAggregate(task);

  TaskAggregate fromDto(TaskSnapshotDto dto) => dto.toAggregate();
}
