import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart';

/// Persistence-only representation of a project document.
class ProjectSnapshotDto {
  const ProjectSnapshotDto._(this.document);

  factory ProjectSnapshotDto.fromAggregate(ProjectAggregate project) =>
      ProjectSnapshotDto._(ProjectSnapshotCodec.encode(project));

  factory ProjectSnapshotDto.fromDocument(Map<String, dynamic> document) =>
      ProjectSnapshotDto._(Map.unmodifiable(document));

  final Map<String, dynamic> document;

  ProjectAggregate toAggregate() => ProjectSnapshotCodec.decode(document);
}
