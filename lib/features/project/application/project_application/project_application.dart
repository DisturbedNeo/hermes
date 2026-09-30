import 'package:hermes/features/project/runtime/project_application.dart';

/// Concrete public project application facade.
class ProjectApplication extends ProjectRuntimeApplication {
  ProjectApplication({
    required super.taskController,
    required super.taskPersistence,
    required super.toolService,
    required super.sandbox,
    required super.materializer,
    required super.repository,
    required super.aggregateRepository,
    super.planner,
    super.completionEvaluator,
    super.scheduler,
    super.memoryService,
    super.progressMonitor,
    super.persistenceCoordinator,
    super.commandService,
    super.executionPort,
    super.recoveryPort,
    super.planningRunner,
    super.structuredOutput,
    super.lifecycle,
    super.taskLifecycle,
    super.completion,
    super.recoveryService,
  });
}
