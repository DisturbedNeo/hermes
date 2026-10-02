part of 'project_execution_state_machine.dart';

/// Execution-only capability surface for project execution use cases.
abstract interface class ProjectExecutionCapabilities {
  TaskPlanningPort get taskPlanning;
  TaskProjectPlanningPort get taskProjectPlanning;
  TaskExecutionPort get taskExecution;
  TaskRecoveryPort get taskRecovery;
  ToolRegistryPort get toolService;
  TaskMaterializerPort get materializer;
  ProjectAggregateReadPort get aggregateRepository;
  ProjectPersistenceCoordinator get persistenceCoordinator;
  ProjectPlanner get planner;
  ProjectCompletionEvaluator get completionEvaluator;
  ProjectCompletionService get completionService;
  ProjectProgressMonitor get progressMonitor;
  ProjectCriterionEvaluator get criterionEvaluator;
  ProjectPlanRevisionCoordinator get planRevisionCoordinator;
  ProjectDecisionEngine get decisionEngine;
  QuestionPolicyService get questionPolicy;
  ProjectRecoveryHandler get recoveryHandler;
  ProjectEvaluationCoordinator Function() get evaluationCoordinator;
  ProjectPlanningHandler get planningHandler;
  ProjectControlStateService get controlStateService;
  ProjectMemoryService get memoryService;
  ProjectRecoveryPolicy get recoveryPolicy;
  ProjectScheduler get scheduler;
  ProjectLifecycleService get lifecycleService;
}

/// Planning-only capability surface for project planning use cases.
abstract interface class ProjectPlanningCapabilities {
  ProjectControlStateService get controlStateService;
  ProjectInitialPlanResult Function(String originalGoal)
  get fallbackInitialPlan;
  List<ProjectPlanValidationIssue> Function({
    required ProjectInitialPlanResult initialPlan,
    required WorkspaceDiscoveryProfile workspaceProfile,
  })
  get validateInitialPlan;
  bool Function(WorkspaceRequiredContextIssue issue)
  get blocksInitialPlanningForContextIssue;
  ProjectFilteredQuestions Function(
    List<PendingProjectQuestion> questions, {
    required QuestionAutonomy autonomy,
  })
  get filterProjectQuestions;
  List<ProjectTaskNode> Function(
    List<ProjectTaskNode> tasks,
    List<String> criterionIds,
  )
  get normaliseInitialBacklog;
  List<ProjectMilestone> Function({
    required List<ProjectMilestone> milestones,
    required String refinedGoal,
    required List<ProjectCriterion>? criteria,
    required DateTime now,
  })
  get initialMilestones;
  List<ProjectMemoryEntry> Function({
    required List<ProjectMemoryEntry> memory,
    required List<String> policyAssumptions,
    required DateTime now,
  })
  get initialMemory;
  String Function(String prompt) get titleFromPrompt;
  String Function(String prompt) get newProjectId;
  int Function(int? value, {required int fallback}) get normaliseOptionalLimit;
  String Function(List<ProjectPlanValidationIssue> issues)
  get initialPlanningBlockerMessage;
  ProjectAggregate Function({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    required String reason,
    ProjectBlocker? blocker,
    required DateTime now,
  })
  get transitionProject;
  Future<ProjectAggregate> Function(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint,
  })
  get persistProject;
  ProjectPlanningHandler get planningHandler;
}

/// Command/recovery capability surface for project user commands.
abstract interface class ProjectCommandCapabilities {
  ProjectTaskNode? Function(ProjectAggregate project) get activeProjectTask;
  List<ProjectPlanRevisionTrigger> Function(
    List<ProjectPlanRevisionTrigger> current,
    ProjectPlanRevisionTrigger trigger,
  )
  get appendTrigger;
  List<String> Function(List<String> current, String value) get appendUnique;
  ProjectDecisionRecord Function(
    ProjectDecisionType type,
    String summary,
    String rationale, {
    ProjectTaskNode? task,
  })
  get decision;
  ProjectLifecycleService get lifecycleService;
  ProjectMemoryService get memoryService;
  Future<ProjectAggregate> Function(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint,
  })
  get persistProject;
  ProjectPlanningHandler get planningHandler;
  ProjectRecoveryPolicy get recoveryPolicy;
  ProjectScheduler get scheduler;
  ProjectAggregate Function({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    required String reason,
    ProjectBlocker? blocker,
    required DateTime now,
  })
  get transitionProject;
}

/// The application context exposed to project use cases.
///
/// This is deliberately a capability bundle rather than a reference to
/// [ProjectExecutionStateMachine]. The stable runtime facade assembles this
/// context at the composition boundary; use cases cannot reach back into the
/// facade or its unrelated state.
class ProjectUseCaseContext
    implements
        ProjectExecutionCapabilities,
        ProjectPlanningCapabilities,
        ProjectCommandCapabilities {
  const ProjectUseCaseContext({
    required this.taskPlanning,
    required this.taskProjectPlanning,
    required this.taskExecution,
    required this.taskRecovery,
    required this.toolService,
    required this.materializer,
    required this.aggregateRepository,
    required this.persistenceCoordinator,
    required this.planner,
    required this.completionEvaluator,
    required this.completionService,
    required this.progressMonitor,
    required this.evidenceService,
    required this.criterionEvaluator,
    required this.planRevisionCoordinator,
    required this.decisionEngine,
    required this.questionPolicy,
    required this.recoveryHandler,
    required this.evaluationCoordinator,
    required this.planningHandler,
    required this.controlStateService,
    required this.memoryService,
    required this.recoveryPolicy,
    required this.scheduler,
    required this.lifecycleService,
    required this.fallbackInitialPlan,
    required this.validateInitialPlan,
    required this.blocksInitialPlanningForContextIssue,
    required this.filterProjectQuestions,
    required this.normaliseInitialBacklog,
    required this.initialMilestones,
    required this.initialMemory,
    required this.titleFromPrompt,
    required this.newProjectId,
    required this.normaliseOptionalLimit,
    required this.initialPlanningBlockerMessage,
    required this.transitionProject,
    required this.persistProject,
    required this.appendTrigger,
    required this.appendUnique,
    required this.decision,
    required this.activeProjectTask,
  });

  final TaskPlanningPort taskPlanning;
  final TaskProjectPlanningPort taskProjectPlanning;
  final TaskExecutionPort taskExecution;
  final TaskRecoveryPort taskRecovery;
  final ToolRegistryPort toolService;
  final TaskMaterializerPort materializer;
  final ProjectAggregateReadPort aggregateRepository;
  final ProjectPersistenceCoordinator persistenceCoordinator;
  final ProjectPlanner planner;
  final ProjectCompletionEvaluator completionEvaluator;
  final ProjectCompletionService completionService;
  final ProjectProgressMonitor progressMonitor;
  final ProjectEvidenceService evidenceService;
  final ProjectCriterionEvaluator criterionEvaluator;
  final ProjectPlanRevisionCoordinator planRevisionCoordinator;
  final ProjectDecisionEngine decisionEngine;
  final QuestionPolicyService questionPolicy;
  final ProjectRecoveryHandler recoveryHandler;
  final ProjectEvaluationCoordinator Function() evaluationCoordinator;

  final ProjectPlanningHandler planningHandler;
  final ProjectControlStateService controlStateService;
  final ProjectMemoryService memoryService;
  final ProjectRecoveryPolicy recoveryPolicy;
  final ProjectScheduler scheduler;
  final ProjectLifecycleService lifecycleService;

  final ProjectInitialPlanResult Function(String originalGoal)
  fallbackInitialPlan;
  final List<ProjectPlanValidationIssue> Function({
    required ProjectInitialPlanResult initialPlan,
    required WorkspaceDiscoveryProfile workspaceProfile,
  })
  validateInitialPlan;
  final bool Function(WorkspaceRequiredContextIssue issue)
  blocksInitialPlanningForContextIssue;
  final ProjectFilteredQuestions Function(
    List<PendingProjectQuestion> questions, {
    required QuestionAutonomy autonomy,
  })
  filterProjectQuestions;
  final List<ProjectTaskNode> Function(
    List<ProjectTaskNode> tasks,
    List<String> criterionIds,
  )
  normaliseInitialBacklog;
  final List<ProjectMilestone> Function({
    required List<ProjectMilestone> milestones,
    required String refinedGoal,
    required List<ProjectCriterion>? criteria,
    required DateTime now,
  })
  initialMilestones;
  final List<ProjectMemoryEntry> Function({
    required List<ProjectMemoryEntry> memory,
    required List<String> policyAssumptions,
    required DateTime now,
  })
  initialMemory;
  final String Function(String prompt) titleFromPrompt;
  final String Function(String prompt) newProjectId;
  final int Function(int? value, {int fallback}) normaliseOptionalLimit;
  final String Function(List<ProjectPlanValidationIssue> issues)
  initialPlanningBlockerMessage;

  final ProjectAggregate Function({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    required String reason,
    ProjectBlocker? blocker,
    required DateTime now,
  })
  transitionProject;
  final Future<ProjectAggregate> Function(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint,
  })
  persistProject;
  final List<ProjectPlanRevisionTrigger> Function(
    List<ProjectPlanRevisionTrigger> current,
    ProjectPlanRevisionTrigger trigger,
  )
  appendTrigger;
  final List<String> Function(List<String> current, String value) appendUnique;
  final ProjectDecisionRecord Function(
    ProjectDecisionType type,
    String summary,
    String rationale, {
    ProjectTaskNode? task,
  })
  decision;
  final ProjectTaskNode? Function(ProjectAggregate project) activeProjectTask;
}
