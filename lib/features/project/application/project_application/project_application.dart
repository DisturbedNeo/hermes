import 'package:hermes/features/project/runtime/project_application.dart';

/// Concrete public project application facade.
class ProjectApplication extends ProjectRuntimeApplication {
  ProjectApplication({
    required super.taskQueries,
    required super.taskPlanning,
    required super.taskProjectPlanning,
    required super.taskExecution,
    required super.taskRecovery,
    required super.toolService,
    required super.materializer,
    required super.aggregateRepository,
    required super.dependencies,
  });
}
