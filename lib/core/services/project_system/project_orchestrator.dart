import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/project_system/project_lifecycle_service.dart';
import 'package:hermes/core/services/project_system/project_workflow_service.dart';

export 'project_workflow_service.dart' show taskStepLimit;

/// Stable application-facing project boundary.
///
/// The workflow service owns the implementation. This subtype keeps the
/// historical application name and constructor injection surface without
/// wrapping every operation in another forwarding object.
class ProjectOrchestrator extends ProjectWorkflowService {
  ProjectOrchestrator({
    required super.taskService,
    super.repository,
    super.planner,
    super.completionEvaluator,
    super.scheduler,
    super.memoryService,
    super.progressMonitor,
    super.persistenceCoordinator,
    super.aggregateRepository,
    super.stateStore,
    super.commandService,
    super.executionPort,
    super.recoveryPort,
    super.planningRunner = const PlanningToolCallRunner(),
    super.structuredOutput = const StructuredPlanningOutputService(),
    super.lifecycle = const ProjectLifecycleService(),
    super.taskLifecycle,
    super.completion,
    super.recoveryService,
  });
}
