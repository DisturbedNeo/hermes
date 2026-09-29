import 'package:hermes/features/task/runtime/task_controller.dart';
import 'package:hermes/shared_kernel/task_persistence_ports.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/shared_kernel/planning_structured_output.dart';
import 'package:hermes/shared_kernel/workspace_discovery_service.dart';

/// Concrete public task application facade.
class TaskController extends TaskRuntimeController {
  TaskController({
    required ToolRegistryPort toolService,
    required WorkspaceSandboxPort sandbox,
    TaskPersistencePort? persistence,
    TaskPersistenceStore? persistenceStore,
    TaskRecoveryService? recoveryService,
    TaskPlanner? planner,
    TaskPlanningCoordinatorPort? planningCoordinator,
    TaskModelCompletionPort? modelCompletion,
    TaskToolExecutionPort? toolExecution,
    StructuredPlanningOutputService? structuredOutput,
    WorkspaceDiscoveryProfileService? profileService,
  }) : super(
         toolService: toolService,
         sandbox: sandbox,
         persistence: persistence,
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
