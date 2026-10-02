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

  Future<TaskAggregate> _persistTask(
    String workspaceRoot,
    TaskAggregate task,
  ) => _context.persistTask(workspaceRoot, task);

  Future<TaskAggregate> _recoverTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required bool persist,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final recovered = _context.recoveryService.recover(
      snapshot,
      now: DateTime.now(),
    );
    return persist ? _persistTask(workspace.rootPath, recovered) : recovered;
  }

  TaskAggregate _markCompleted(TaskAggregate snapshot) =>
      _context.markCompleted(snapshot);
  TaskAggregate _completeStep(
    TaskAggregate snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  ) => _context.completeStep(snapshot, step, output, now);
  TaskAggregate _blockStep(
    TaskAggregate snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  ) => _context.blockStep(snapshot, step, output, now);
  TaskAggregate _failStep(
    TaskAggregate snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
    DateTime now,
  ) => _context.failStep(snapshot, step, output, now);
  TaskAggregate _replaceStep(
    TaskAggregate snapshot,
    String stepId,
    TaskStep step,
  ) => _context.replaceStep(snapshot, stepId, step);
  TaskAggregate _replaceLastRun(TaskAggregate snapshot, TaskRun run) =>
      _context.replaceLastRun(snapshot, run);
  String _appendMemory(String current, String update) =>
      _context.appendMemory(current, update);
  TaskAggregate _fallbackReplannedTask(
    TaskAggregate snapshot,
    String reason, {
    required PlanningMetrics planningMetrics,
  }) => _context.fallbackReplannedTask(
    snapshot,
    reason,
    planningMetrics: planningMetrics,
  );
  int _taskPlanningStepLimit(TaskAggregate task) =>
      _context.taskPlanningStepLimit(task);
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

  Future<TaskAggregate> runNextStep({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
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

  Future<TaskAggregate> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
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
