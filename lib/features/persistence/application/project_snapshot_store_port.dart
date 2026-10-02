import 'package:hermes/features/project/project_repository_port.dart';

/// Infrastructure-facing extension for project snapshot storage.
///
/// File layout and path calculation are intentionally absent from
/// [ProjectRepositoryPort]. Only persistence coordinators and adapters should
/// depend on this lower-level capability.
abstract interface class ProjectSnapshotStorePort
    implements ProjectRepositoryPort {
  static const String projectsRoot = '.agent/projects';
  static const String documentFileName = 'project.json';

  String projectRelativePath(String projectId, String fileName);
}
