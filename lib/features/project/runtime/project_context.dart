part of 'project_application.dart';

class _ProjectApplicationContext {
  _ProjectApplicationContext({
    required TaskProjectPort taskController,
    ProjectRepositoryPort? repository,
    ProjectPlanner? planner,
    ProjectCompletionEvaluator? completionEvaluator,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
    PersistencePort? persistenceCoordinator,
    ProjectAggregateRepositoryPort? aggregateRepository,
    ProjectStateStore? stateStore,
    ProjectCommandService? commandService,
    ProjectCommandExecutionPort? executionPort,
    ProjectRecoveryPort? recoveryPort,
    PlanningToolCallRunner planningRunner = const PlanningToolCallRunner(),
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    ProjectLifecycleService lifecycle = const ProjectLifecycleService(),
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectRecoveryService? recoveryService,
  }) : _taskController = taskController,
       _repository = repository ?? InMemoryProjectRepository(),
       _persistenceCoordinator =
           persistenceCoordinator ?? taskController.repository.coordinator,
       _providedAggregateRepository = aggregateRepository,
       _providedStateStore = stateStore,
       _providedCommandService = commandService,
       _providedExecutionPort = executionPort,
       _providedRecoveryPort = recoveryPort,
       _planner =
           planner ??
           ProjectModelCalls(
             toolService: taskController.toolService,
             planningRunner: planningRunner,
             structuredOutput: structuredOutput,
           ),
       _completionEvaluator =
           completionEvaluator ??
           ProjectModelCalls(
             toolService: taskController.toolService,
             planningRunner: planningRunner,
             structuredOutput: structuredOutput,
           ),
       _scheduler = scheduler ?? const ProjectScheduler(),
       _memoryService = memoryService ?? const ProjectMemoryService(),
       _progressMonitor = progressMonitor ?? const ProjectProgressMonitor(),
       lifecycleService = lifecycle,
       taskLifecycleService = taskLifecycle ?? const TaskLifecycleService(),
       completionService =
           completion ?? ProjectCompletionService(lifecycle: lifecycle),
       recoveryHandler = ProjectRecoveryHandler(
         recoveryService ?? const ProjectRecoveryService(),
       );

  final TaskProjectPort _taskController;
  final ProjectRepositoryPort _repository;
  final ProjectPlanner _planner;
  final ProjectCompletionEvaluator _completionEvaluator;
  final ProjectScheduler _scheduler;
  final ProjectMemoryService _memoryService;
  final ProjectProgressMonitor _progressMonitor;
  final PersistencePort _persistenceCoordinator;
  final ProjectLifecycleService lifecycleService;
  final TaskLifecycleService taskLifecycleService;
  final ProjectCompletionService completionService;
  final ProjectRecoveryHandler recoveryHandler;
  final ProjectCommandService? _providedCommandService;
  final ProjectCommandExecutionPort? _providedExecutionPort;
  final ProjectRecoveryPort? _providedRecoveryPort;
  final ProjectAggregateRepositoryPort? _providedAggregateRepository;
  final ProjectStateStore? _providedStateStore;

  late final ProjectAggregateRepositoryPort _aggregateRepository =
      _providedAggregateRepository ??
      InMemoryProjectAggregateRepository(
        projectRepository: _repository,
        taskRepository: _taskController.repository,
      );
  late final ProjectAggregateStore _aggregateStore = ProjectAggregateStore(
    aggregateRepository: _aggregateRepository,
    taskRepository: _taskController.repository,
  );
  late final ProjectPersistenceHandler _persistenceHandler =
      ProjectPersistenceHandler(
        aggregateStore: _aggregateStore,
        scheduler: _scheduler,
        controlState: _controlStateService,
      );
  late final ProjectStateStore _stateStore =
      _providedStateStore ??
      ProjectStateStore(
        projectRepository: _repository,
        aggregateRepository: _aggregateRepository,
        taskController: _taskController,
      );
  late final ProjectCommandService _commandService =
      _providedCommandService ??
      ProjectCommandService(
        stateStore: _stateStore,
        persistenceCoordinator: _persistenceCoordinator,
        runLoop: const ProjectRunLoop(),
      );
  late final ProjectCommandExecutionPort _executionPort =
      _providedExecutionPort ??
      CallbackProjectCommandExecutionPort(_runProjectForCommand);
  late final ProjectRecoveryPort _recoveryPort =
      _providedRecoveryPort ?? CallbackProjectRecoveryPort(_recoverForCommand);
  final QuestionPolicyService _questionPolicy = const QuestionPolicyService();
  final ProjectEvidenceService _evidenceService =
      const ProjectEvidenceService();
  final ProjectCriterionEvaluator _criterionEvaluator =
      const ProjectCriterionEvaluator();
  late final ProjectDiscoveryService _discoveryService =
      ProjectDiscoveryService(
        taskController: _taskController,
        memoryService: _memoryService,
      );
  late final ProjectPlanningHandler _planningHandler = ProjectPlanningHandler(
    coordinator: ProjectPlanningCoordinator(
      discovery: _discoveryService,
      planner: _planner,
      maxAutomaticRepairs: _maxAutomaticInitialPlanRepairs,
    ),
    revisionService: const ProjectPlanRevisionService(),
  );
  final ProjectDecisionEngine _decisionEngine = const ProjectDecisionEngine();
  final ProjectControlStateService _controlStateService =
      const ProjectControlStateService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  // A malformed model plan is a recoverable planning failure. Keep the
  // retry bounded so a persistently invalid model response still becomes a
  // durable, actionable blocker rather than an unbounded model-call loop.
  static const _maxAutomaticInitialPlanRepairs = 2;

  static const Set<ProjectPlanRevisionTrigger> _runtimeReplanTriggers = {
    ProjectPlanRevisionTrigger.noReadyTask,
    ProjectPlanRevisionTrigger.taskFailed,
    ProjectPlanRevisionTrigger.evidenceRejected,
    ProjectPlanRevisionTrigger.taskReplanRequested,
    ProjectPlanRevisionTrigger.workspaceChanged,
    ProjectPlanRevisionTrigger.scopeChanged,
    ProjectPlanRevisionTrigger.milestoneRoadmapChanged,
  };
}
