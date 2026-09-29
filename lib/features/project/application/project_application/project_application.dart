import 'package:hermes/features/project/runtime/project_application.dart';
import '../../../task/application/task_application/task_ports.dart';
import 'package:hermes/shared_kernel/task_persistence_ports.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/shared_kernel/project_scheduler.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/shared_kernel/planning_runtime.dart';
import 'package:hermes/shared_kernel/planning_structured_output.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/shared_kernel/task_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';

/// Concrete public project application facade.
class ProjectApplication extends ProjectRuntimeApplication {
  ProjectApplication({
    required TaskProjectPort taskController,
    TaskPersistencePort? taskPersistence,
    ToolRegistryPort? toolService,
    ProjectRepositoryPort? repository,
    ProjectPlanner? planner,
    ProjectCompletionEvaluator? completionEvaluator,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
    PersistencePort? persistenceCoordinator,
    ProjectAggregateRepositoryPort? aggregateRepository,
    ProjectCommandService? commandService,
    ProjectCommandExecutionPort? executionPort,
    ProjectRecoveryPort? recoveryPort,
    PlanningToolCallRunner? planningRunner,
    StructuredPlanningOutputService? structuredOutput,
    ProjectLifecycleService? lifecycle,
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectRecoveryService? recoveryService,
  }) : super(
         taskController: taskController,
         taskPersistence: taskPersistence,
         toolService: toolService,
         repository: repository,
         planner: planner,
         completionEvaluator: completionEvaluator,
         scheduler: scheduler,
         memoryService: memoryService,
         progressMonitor: progressMonitor,
         persistenceCoordinator: persistenceCoordinator,
         aggregateRepository: aggregateRepository,
         commandService: commandService,
         executionPort: executionPort,
         recoveryPort: recoveryPort,
         planningRunner: planningRunner,
         structuredOutput: structuredOutput,
         lifecycle: lifecycle,
         taskLifecycle: taskLifecycle,
         completion: completion,
       recoveryService: recoveryService,
       );
}
