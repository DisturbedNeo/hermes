part of 'task_execution_coordinator.dart';

/// Planning-only capability surface supplied to task planning use cases.
abstract interface class TaskPlanningCapabilities {
  TaskPlanningCoordinatorPort get planningCoordinator;
  TaskPersistenceStore get persistenceStore;
  WorkspaceReadPort get sandbox;
  TaskToolExecutionPort get toolExecution;
  JsonEncoder get encoder;
  Future<Task> Function(String workspaceRoot, Task task) get persistTask;
  String Function(String prompt) get newTaskId;
  Future<WorkspaceMetadata> Function(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  })
  get collectWorkspaceMetadata;
  Future<TaskIncrementalPlanAttempt> Function({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required String baseSystemPrompt,
    required String taskId,
    required String userPrompt,
    required WorkspaceMetadata metadata,
    required TaskPlanningContext? planningContext,
    required DateTime now,
    required String? chatSessionId,
    required String? projectId,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  })
  get completeTaskPlanWithCommands;
  Task Function({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  })
  get fallbackTask;
  Task Function({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    required DateTime now,
  })
  get fallbackProjectBoundedTask;
  Task Function(Task candidate, Task original, DateTime now)
  get normaliseEditedTask;
}

/// Step-execution capability surface supplied to task execution use cases.
abstract interface class TaskExecutionCapabilities {
  TaskPersistenceStore get persistenceStore;
  WorkspaceReadPort get sandbox;
  WorkspaceDiscoveryPort get profileService;
  TaskGateEvaluator get gateEvaluator;
  TaskToolExecutionPort get toolExecution;
  TaskPlanningCoordinatorPort get planningCoordinator;
  TaskStepExecutionLoop get stepLoop;
  TaskStepRunner get stepRunner;
  TaskViewService get taskViewService;
  QuestionPolicyService get questionPolicy;
  JsonEncoder get encoder;
  TaskRecoveryService get recoveryService;
  Future<Task> Function(String workspaceRoot, Task task) get persistTask;
  Task Function(Task snapshot) get markCompleted;
  Task Function(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  )
  get completeStep;
  Task Function(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  )
  get blockStep;
  Task Function(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  )
  get failStep;
  Task Function(Task snapshot, String stepId, TaskStep step) get replaceStep;
  Task Function(Task snapshot, TaskRun run) get replaceLastRun;
  String Function(String current, String update) get appendMemory;
  Task Function(
    Task snapshot,
    String reason, {
    required PlanningMetrics planningMetrics,
  })
  get fallbackReplannedTask;
  int Function(Task task) get taskPlanningStepLimit;
  TaskStepExecutionStatus? Function(String raw) get parseStepExecutionStatus;
  List<TaskEvidenceClaim> Function(
    Object? value,
    List<String> allowedCriterionIds, {
    List<TaskProjectEvidenceExpectation> expectedEvidence,
  })
  get evidenceClaimsFromJson;
  String Function({
    required String code,
    required String message,
    required TaskToolErrorDisposition disposition,
    Map<String, dynamic> details,
  })
  get taskToolErrorJson;
}

/// User-directed command capability surface supplied to task command use cases.
abstract interface class TaskCommandCapabilities {
  TaskCommandService get commandService;
}

/// Persistence/recovery capability surface supplied to task persistence use cases.
abstract interface class TaskPersistenceCapabilities {
  TaskPersistenceStore get persistenceStore;
  WorkspaceReadPort get sandbox;
  TaskRecoveryService get recoveryService;
  TaskModelCompletionPort get modelCompletion;
  JsonEncoder get encoder;
  RefinedTaskBrief Function(RefinedTaskBrief brief, String prompt)
  get normaliseBrief;
  RefinedTaskBrief Function(String prompt) get fallbackBrief;
  Future<WorkspaceMetadata> Function(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  })
  get collectWorkspaceMetadata;
}

/// Capability context supplied to task use cases by the composition facade.
///
/// Task use cases own their workflows and receive only the services and
/// policies required to run them. They do not depend on the concrete task
/// coordinator or on its mutable runtime object.
class TaskUseCaseContext
    implements
        TaskPlanningCapabilities,
        TaskExecutionCapabilities,
        TaskCommandCapabilities,
        TaskPersistenceCapabilities {
  const TaskUseCaseContext({
    required this.toolService,
    required this.planningCoordinator,
    required this.persistenceStore,
    required this.sandbox,
    required this.profileService,
    required this.recoveryService,
    required this.gateEvaluator,
    required this.modelCompletion,
    required this.toolExecution,
    required this.stepLoop,
    required this.stepRunner,
    required this.commandService,
    required this.taskViewService,
    required this.questionPolicy,
    required this.encoder,
    required this.persistTask,
    required this.newTaskId,
    required this.collectWorkspaceMetadata,
    required this.completeTaskPlanWithCommands,
    required this.fallbackTask,
    required this.fallbackProjectBoundedTask,
    required this.normaliseEditedTask,
    required this.markCompleted,
    required this.completeStep,
    required this.blockStep,
    required this.failStep,
    required this.replaceStep,
    required this.replaceLastRun,
    required this.appendMemory,
    required this.fallbackReplannedTask,
    required this.taskPlanningStepLimit,
    required this.parseStepExecutionStatus,
    required this.evidenceClaimsFromJson,
    required this.taskToolErrorJson,
    required this.normaliseBrief,
    required this.fallbackBrief,
  });

  final ToolRegistryPort toolService;
  final TaskPlanningCoordinatorPort planningCoordinator;
  final TaskPersistenceStore persistenceStore;
  final WorkspaceReadPort sandbox;
  final WorkspaceDiscoveryPort profileService;
  final TaskRecoveryService recoveryService;
  final TaskGateEvaluator gateEvaluator;
  final TaskModelCompletionPort modelCompletion;
  final TaskToolExecutionPort toolExecution;
  final TaskStepExecutionLoop stepLoop;
  final TaskStepRunner stepRunner;
  final TaskCommandService commandService;
  final TaskViewService taskViewService;
  final QuestionPolicyService questionPolicy;
  final JsonEncoder encoder;

  final Future<Task> Function(String workspaceRoot, Task task) persistTask;
  final String Function(String prompt) newTaskId;
  final Future<WorkspaceMetadata> Function(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  })
  collectWorkspaceMetadata;
  final Future<TaskIncrementalPlanAttempt> Function({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required String baseSystemPrompt,
    required String taskId,
    required String userPrompt,
    required WorkspaceMetadata metadata,
    required TaskPlanningContext? planningContext,
    required DateTime now,
    required String? chatSessionId,
    required String? projectId,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  })
  completeTaskPlanWithCommands;
  final Task Function({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  })
  fallbackTask;
  final Task Function({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    required DateTime now,
  })
  fallbackProjectBoundedTask;
  final Task Function(Task candidate, Task original, DateTime now)
  normaliseEditedTask;
  final Task Function(Task snapshot) markCompleted;
  final Task Function(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  )
  completeStep;
  final Task Function(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  )
  blockStep;
  final Task Function(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  )
  failStep;
  final Task Function(Task snapshot, String stepId, TaskStep step) replaceStep;
  final Task Function(Task snapshot, TaskRun run) replaceLastRun;
  final String Function(String current, String update) appendMemory;
  final Task Function(
    Task snapshot,
    String reason, {
    required PlanningMetrics planningMetrics,
  })
  fallbackReplannedTask;
  final int Function(Task task) taskPlanningStepLimit;
  final TaskStepExecutionStatus? Function(String raw) parseStepExecutionStatus;
  final List<TaskEvidenceClaim> Function(
    Object? value,
    List<String> allowedCriterionIds, {
    List<TaskProjectEvidenceExpectation> expectedEvidence,
  })
  evidenceClaimsFromJson;
  final String Function({
    required String code,
    required String message,
    required TaskToolErrorDisposition disposition,
    Map<String, dynamic> details,
  })
  taskToolErrorJson;
  final RefinedTaskBrief Function(RefinedTaskBrief brief, String prompt)
  normaliseBrief;
  final RefinedTaskBrief Function(String prompt) fallbackBrief;
}
