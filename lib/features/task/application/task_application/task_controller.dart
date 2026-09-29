import 'package:hermes/features/task/runtime/task_controller.dart';

/// Concrete public task application facade.
class TaskController extends TaskRuntimeController {
  TaskController({
    required dynamic toolService,
    required dynamic sandbox,
    dynamic repository,
    dynamic persistenceStore,
    dynamic recoveryService,
    dynamic planner,
    dynamic planningCoordinator,
    dynamic modelCompletion,
    dynamic toolExecution,
    dynamic structuredOutput,
    dynamic profileService,
  }) : super(
         toolService: toolService,
         sandbox: sandbox,
         repository: repository,
         persistenceStore: persistenceStore,
         recoveryService: recoveryService,
         planner: planner,
         planningCoordinator: planningCoordinator,
         modelCompletion: modelCompletion,
         toolExecution: toolExecution,
         structuredOutput: structuredOutput,
         profileService: profileService,
       );
}
