part of 'task_runtime_engine.dart';

class _TaskApplicationContext {
  _TaskApplicationContext({
    required ToolRegistryPort toolService,
    required WorkspaceSandboxPort sandbox,
    TaskPersistencePort? persistence,
    TaskPersistenceStore? persistenceStore,
    TaskRecoveryService recoveryService = const TaskRecoveryService(),
    TaskPlanner planner = const TaskPlanningService(),
    TaskPlanningCoordinatorPort? planningCoordinator,
    TaskModelCompletionPort? modelCompletion,
    TaskToolExecutionPort? toolExecution,
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    WorkspaceDiscoveryProfileService profileService =
        const WorkspaceDiscoveryProfileService(),
  }) : _toolService = toolService,
       _planningCoordinator =
           planningCoordinator ?? TaskPlanningCoordinator(planner: planner),
       _persistenceStore =
           persistenceStore ??
           TaskPersistenceStore(
             persistence: persistence ?? InMemoryTaskRepository(),
           ),
       _sandbox = sandbox,
       _profileService = profileService,
       _gateEvaluator = TaskGateEvaluator(sandbox: sandbox),
       _recoveryService = recoveryService,
       _modelCompletion =
           modelCompletion ??
           TaskModelCompletionService(structuredOutput: structuredOutput),
       _toolExecution =
           toolExecution ??
           TaskToolExecutionService(toolService: toolService, sandbox: sandbox);

  final ToolRegistryPort _toolService;
  final TaskPlanningCoordinatorPort _planningCoordinator;
  final TaskPersistenceStore _persistenceStore;
  final WorkspaceSandboxPort _sandbox;
  final WorkspaceDiscoveryProfileService _profileService;
  final TaskGateEvaluator _gateEvaluator;
  final TaskRecoveryService _recoveryService;
  final TaskModelCompletionPort _modelCompletion;
  final TaskToolExecutionPort _toolExecution;
  final TaskViewService _taskViewService = const TaskViewService();
  late final TaskCommandService _commandService = TaskCommandService(
    persistence: _persistenceStore,
  );
  late final TaskStepRunner _stepRunner = TaskStepRunner(
    persistence: _persistenceStore,
    recovery: _recoveryService,
  );
  final QuestionPolicyService _questionPolicy = const QuestionPolicyService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  TaskPersistencePort get persistence => _persistenceStore.persistence;
  ToolRegistryPort get tools => _toolService;
  TaskMaterializerPort get materializer => const TaskPlanMaterializer();
}
