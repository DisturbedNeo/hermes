import 'package:hermes/features/persistence/infrastructure/dto/project_snapshot_dto.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';

/// Converts between the project domain boundary and its durable DTO.
class ProjectPersistenceAdapter {
  const ProjectPersistenceAdapter();

  ProjectSnapshotDto toDto(ProjectAggregate project) =>
      ProjectSnapshotDto.fromAggregate(project);

  ProjectAggregate fromDto(ProjectSnapshotDto dto) => dto.toAggregate();
}
