import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/project/domain/project.dart';

/// Persistence-only representation of a project document.
class ProjectSnapshotDto {
  const ProjectSnapshotDto._(this.document);

  factory ProjectSnapshotDto.fromAggregate(ProjectAggregate project) =>
      ProjectSnapshotDto._(
        ModelJson.encode(project.copyWith(persistenceRevision: 0))
          ..remove('persistenceRevision'),
      );

  factory ProjectSnapshotDto.fromDocument(Map<String, dynamic> document) =>
      ProjectSnapshotDto._(Map.unmodifiable(document));

  final Map<String, dynamic> document;

  ProjectAggregate toAggregate() =>
      ModelJson.decode<ProjectAggregate>(document);
}
