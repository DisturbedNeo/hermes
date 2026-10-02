part of 'project_execution_state_machine.dart';

/// Owns the project execution workflow behind the stable runtime facade.
///
/// The state machine remains a composition and compatibility boundary. This
/// use case receives the project capabilities it needs through
/// [ProjectUseCaseContext] and does not retain a reference to the facade.
class ProjectExecutionUseCase {
  ProjectExecutionUseCase(ProjectExecutionCapabilities context)
    : _context = context;

  final ProjectExecutionCapabilities _context;

  TaskPlanningPort get _taskPlanning => _context.taskPlanning;
  TaskProjectPlanningPort get _taskProjectPlanning =>
      _context.taskProjectPlanning;
  TaskExecutionPort get _taskExecution => _context.taskExecution;
  TaskRecoveryPort get _taskRecovery => _context.taskRecovery;
  ToolRegistryPort get toolService => _context.toolService;
  TaskMaterializerPort get materializer => _context.materializer;
  ProjectAggregateReadPort get _aggregateRepository =>
      _context.aggregateRepository;
  ProjectPersistenceCoordinator get _persistenceCoordinator =>
      _context.persistenceCoordinator;
  ProjectPlanner get _planner => _context.planner;
  ProjectCompletionEvaluator get _completionEvaluator =>
      _context.completionEvaluator;
  ProjectProgressMonitor get _progressMonitor => _context.progressMonitor;
  ProjectCriterionEvaluator get _criterionEvaluator =>
      _context.criterionEvaluator;
  ProjectPlanRevisionCoordinator get _planRevisionCoordinator =>
      _context.planRevisionCoordinator;
  ProjectDecisionEngine get _decisionEngine => _context.decisionEngine;
  QuestionPolicyService get _questionPolicy => _context.questionPolicy;
  ProjectRecoveryHandler get recoveryHandler => _context.recoveryHandler;
  ProjectEvaluationCoordinator get _evaluationCoordinator =>
      _context.evaluationCoordinator();
  ProjectMemoryService get _memoryService => _context.memoryService;
  ProjectScheduler get _scheduler => _context.scheduler;
  ProjectLifecycleService get lifecycleService => _context.lifecycleService;
  ProjectCompletionService get completionService => _context.completionService;
  ProjectControlStateService get _controlStateService =>
      _context.controlStateService;
  ProjectPlanningHandler get _planningHandler => _context.planningHandler;
  ProjectRecoveryPolicy get _recoveryPolicy => _context.recoveryPolicy;

  Future<ProjectCommandResult> runProjectForCommand(
    ProjectExecutionRequest request,
  ) => _runProjectCore(
    client: request.client,
    workspace: request.workspace,
    snapshot: request.snapshot,
    baseSystemPrompt: request.baseSystemPrompt,
    maxNewTasks: request.maxNewTasks,
    maxIterations: request.maxIterations,
    requirePhaseApproval: request.requirePhaseApproval,
    compactionSettings: request.compactionSettings,
    contextLimitTokens: request.contextLimitTokens,
    onCompactionStatus: request.onCompactionStatus,
    onModelOutput: request.onModelOutput,
    onTaskUpdated: request.onTaskUpdated,
    cancellationToken: request.cancellationToken,
    questionAutonomy: request.questionAutonomy,
    planApprovalPolicy: request.planApprovalPolicy,
  );

  Future<ProjectCommandResult> recoverProjectForCommand(
    ProjectRecoveryRequest request,
  ) => _recoverProjectCore(
    workspace: request.workspace,
    snapshot: request.snapshot,
    onTaskUpdated: request.onTaskUpdated,
  );
}
