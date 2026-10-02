part of 'task_execution_coordinator.dart';

/// Owns task-step execution and explicit unfinished-work replanning commands.
class TaskExecutionUseCase {
  TaskExecutionUseCase(TaskExecutionCapabilities context) : _context = context;

  final TaskExecutionCapabilities _context;

  TaskPlanningCoordinatorPort get _planningCoordinator =>
      _context.planningCoordinator;
  TaskPersistenceStore get _persistenceStore => _context.persistenceStore;
  WorkspaceReadPort get _sandbox => _context.sandbox;
  WorkspaceDiscoveryPort get _profileService => _context.profileService;
  TaskGateEvaluator get _gateEvaluator => _context.gateEvaluator;
  TaskToolExecutionPort get _toolExecution => _context.toolExecution;
  TaskStepExecutionLoop get _stepLoop => _context.stepLoop;
  TaskViewService get _taskViewService => _context.taskViewService;
  QuestionPolicyService get _questionPolicy => _context.questionPolicy;
  JsonEncoder get _encoder => _context.encoder;
  TaskExecutionPolicy get _executionPolicy => const TaskExecutionPolicy();

  Future<Task> _persistTask(String workspaceRoot, Task task) =>
      _context.persistTask(workspaceRoot, task);

  Future<Task> _recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required bool persist,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final recovered = _context.recoveryService.recover(
      snapshot,
      now: DateTime.now(),
    );
    return persist ? _persistTask(workspace.rootPath, recovered) : recovered;
  }

  Task _markCompleted(Task snapshot) => _context.markCompleted(snapshot);
  Task _completeStep(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  ) => _context.completeStep(snapshot, step, output, now);
  Task _blockStep(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  ) => _context.blockStep(snapshot, step, output, now);
  Task _failStep(
    Task snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  ) => _context.failStep(snapshot, step, output, now);
  Task _replaceStep(Task snapshot, String stepId, TaskStep step) =>
      _context.replaceStep(snapshot, stepId, step);
  Task _replaceLastRun(Task snapshot, TaskRun run) =>
      _context.replaceLastRun(snapshot, run);
  String _appendMemory(String current, String update) =>
      _context.appendMemory(current, update);
  Task _fallbackReplannedTask(
    Task snapshot,
    String reason, {
    required PlanningMetrics planningMetrics,
  }) => _context.fallbackReplannedTask(
    snapshot,
    reason,
    planningMetrics: planningMetrics,
  );
  int _taskPlanningStepLimit(Task task) => _context.taskPlanningStepLimit(task);
  TaskStepExecutionStatus? _parseStepExecutionStatusStrict(String raw) =>
      _context.parseStepExecutionStatus(raw);
  List<TaskEvidenceClaim> _evidenceClaimsFromJson(
    Object? value,
    List<String> allowedCriterionIds, {
    List<TaskProjectEvidenceExpectation> expectedEvidence = const [],
  }) => _context.evidenceClaimsFromJson(
    value,
    allowedCriterionIds,
    expectedEvidence: expectedEvidence,
  );
  String _taskToolErrorJson({
    required String code,
    required String message,
    required TaskToolErrorDisposition disposition,
    Map<String, dynamic> details = const {},
  }) => _context.taskToolErrorJson(
    code: code,
    message: message,
    disposition: disposition,
    details: details,
  );

  Future<Task> runNextStep({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    TaskExecutionRequest executionRequest = const TaskExecutionRequest(),
    bool persist = true,
  }) => _context.stepRunner.run(
    workspace: workspace,
    snapshot: snapshot,
    cancellationToken: cancellationToken,
    persist: persist,
    execute: (recovered) => _runNextStepCore(
      client: client,
      workspace: workspace,
      snapshot: recovered,
      baseSystemPrompt: baseSystemPrompt,
      requirePhaseApproval: requirePhaseApproval,
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
      executionRequest: executionRequest,
      persist: persist,
    ),
  );

  Future<Task> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final updated = await _replanUnfinished(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      reason: reason,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    return _persistTask(workspace.rootPath, updated);
  }
}
