import 'package:hermes/features/task/runtime/task_controller.dart';

/// Concrete public task application facade.
class TaskController extends TaskRuntimeController {
  TaskController({
    required super.toolService,
    required super.sandbox,
    required super.persistence,
    super.persistenceStore,
    super.recoveryService,
    super.planner,
    super.planningCoordinator,
    super.modelCompletion,
    super.toolExecution,
    super.structuredOutput,
    super.profileService,
  });
}
