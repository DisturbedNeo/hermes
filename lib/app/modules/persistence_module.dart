import 'package:hermes/features/persistence/infrastructure/workspace_persistence_coordinator.dart';
import 'package:hermes/features/project/infrastructure/project_aggregate_repository.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';

/// Persistence-owned capabilities for one application graph.
///
/// The coordinator is created exactly once here and is passed to every
/// repository. Nothing below this composition boundary creates a fallback
/// coordinator.
class PersistenceModule {
  PersistenceModule._({
    required this.coordinator,
    required this.tasks,
    required this.projects,
    required this.projectAggregates,
  });

  factory PersistenceModule.create() {
    final coordinator = WorkspacePersistenceCoordinator();
    final tasks = TaskRepository(coordinator: coordinator);
    final projects = ProjectRepository(coordinator: coordinator);
    final projectAggregates = ProjectAggregateRepository(
      projectRepository: projects,
      taskRepository: tasks,
      coordinator: coordinator,
    );
    return PersistenceModule._(
      coordinator: coordinator,
      tasks: tasks,
      projects: projects,
      projectAggregates: projectAggregates,
    );
  }

  final WorkspacePersistenceCoordinator coordinator;
  final TaskRepository tasks;
  final ProjectRepository projects;
  final ProjectAggregateRepository projectAggregates;
}
