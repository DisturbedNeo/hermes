part of 'task_execution_coordinator.dart';

extension TaskExecutionOperations on TaskExecutionCoordinator {
  Future<Task> _runNextStepCore({
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
  }) async {
    cancellationToken?.throwIfCancelled();
    var working = await recoverTask(
      workspace: workspace,
      snapshot: snapshot,
      persist: persist,
    );
    Future<Task> save(Task task) =>
        persist ? _persistTask(workspace.rootPath, task) : Future.value(task);
    if (working.isTerminal) return working;
    final step = working.nextRunnableStep;
    if (step == null) {
      final completed = _markCompleted(working);
      return save(completed);
    }

    if (working.pendingQuestion != null) return working;

    if (requirePhaseApproval &&
        step.mayEditFiles &&
        step.status != TaskStepStatus.approved) {
      final blocked =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.blocked),
          ).copyWith(
            status: TaskStatus.blocked,
            currentStepId: step.id,
            pendingApproval: PendingTaskApproval(
              stepId: step.id,
              reason: 'Step "${step.title}" may edit workspace files.',
              createdAt: DateTime.now(),
            ),
            updatedAt: DateTime.now(),
          );
      return save(blocked);
    }

    final now = DateTime.now();
    final run = TaskRun(
      runId: 'run_${uuid.v7()}',
      stepId: step.id,
      status: TaskRunStatus.running,
      summary: '',
      memoryUpdate: '',
      toolCalls: const [],
      artifacts: const [],
      startedAt: now,
    );

    working =
        _replaceStep(
          working,
          step.id,
          step.copyWith(status: TaskStepStatus.running),
        ).copyWith(
          status: TaskStatus.running,
          currentStepId: step.id,
          runs: [...working.runs, run],
          pendingApproval: null,
          pendingQuestion: null,
          updatedAt: now,
        );
    working = await save(working);

    try {
      var execution = await _executeStep(
        client: client,
        workspace: workspace,
        task: working,
        step: step,
        run: run,
        baseSystemPrompt: baseSystemPrompt,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        executionRequest: executionRequest,
      );

      final finishedAt = DateTime.now();
      if (execution.status == _StepExecutionStatus.completed) {
        execution = await _applyCompletionGates(
          client: client,
          workspace: workspace,
          task: working,
          step: step,
          execution: execution,
          baseSystemPrompt: baseSystemPrompt,
          cancellationToken: cancellationToken,
        );
      } else if (execution.status == _StepExecutionStatus.blocked) {
        execution = _applyQuestionPolicy(execution, autonomy: questionAutonomy);
      }
      final completedRun = run.copyWith(
        status: execution.runStatus,
        completedAt: finishedAt,
        summary: execution.summary,
        memoryUpdate: execution.memoryUpdate,
        toolCalls: execution.toolCalls,
        artifacts: execution.artifacts,
        gateResults: execution.gateResults,
        evidenceClaims: [
          for (final claim in execution.evidenceClaims)
            TaskEvidenceClaim(
              criterionId: claim.criterionId,
              claim: claim.claim,
              evidenceType: claim.evidenceType,
              sourceRef: claim.sourceRef,
              suggestedStrength: claim.suggestedStrength,
              expectationId: claim.expectationId,
              runId: run.runId,
            ),
        ],
        replanReason: execution.replanRequest,
        error: execution.error,
      );
      working = _replaceLastRun(working, completedRun);

      switch (execution.status) {
        case _StepExecutionStatus.completed:
          working = _completeStep(working, step, execution, finishedAt);
          break;
        case _StepExecutionStatus.blocked:
          working = _blockStep(working, step, execution, finishedAt);
          break;
        case _StepExecutionStatus.failed:
          working = _failStep(working, step, execution, finishedAt);
          break;
        case _StepExecutionStatus.needsReplan:
          working = await _replanUnfinished(
            client: client,
            workspace: workspace,
            snapshot: working,
            baseSystemPrompt: baseSystemPrompt,
            reason: execution.replanRequest?.trim().isNotEmpty == true
                ? execution.replanRequest!.trim()
                : execution.summary,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
          break;
      }

      return save(working);
    } on OperationCancelledException catch (e) {
      final cancelledAt = DateTime.now();
      final cancelledRun = run.copyWith(
        status: TaskRunStatus.cancelled,
        completedAt: cancelledAt,
        summary: 'Step cancelled by the user.',
        error: e.toString(),
      );
      working = _replaceLastRun(working, cancelledRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.pending),
          ).copyWith(
            status: TaskStatus.paused,
            currentStepId: step.id,
            pendingApproval: null,
            pendingQuestion: null,
            updatedAt: cancelledAt,
          );
      return save(working);
    } on ChatTransportException catch (e) {
      final pausedAt = DateTime.now();
      final pausedRun = run.copyWith(
        status: TaskRunStatus.failed,
        completedAt: pausedAt,
        summary:
            'Model transport was interrupted after automatic retry. '
            'Resume the task to retry this step.',
        error: e.toString(),
      );
      working = _replaceLastRun(working, pausedRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.pending),
          ).copyWith(
            status: TaskStatus.paused,
            currentStepId: step.id,
            pendingApproval: null,
            pendingQuestion: null,
            updatedAt: pausedAt,
          );
      return save(working);
    } catch (e) {
      final failedRun = run.copyWith(
        status: TaskRunStatus.failed,
        completedAt: DateTime.now(),
        summary: 'Step failed: $e',
        error: e.toString(),
      );
      working = _replaceLastRun(working, failedRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: TaskStepStatus.failed),
          ).copyWith(
            status: TaskStatus.failed,
            currentStepId: step.id,
            updatedAt: DateTime.now(),
          );
      return save(working);
    }
  }

  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _commandService.approvePendingStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _commandService.retryCurrentStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) =>
      _commandService.skipCurrentStep(workspace: workspace, snapshot: snapshot);

  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _commandService.stopTask(workspace: workspace, snapshot: snapshot);

  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  }) => _commandService.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
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

  Future<WorkspaceMetadata> _collectWorkspaceMetadata(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final profile = await _profileService.collect(workspace: workspace);
    final existingTasks =
        await _persistenceStore.persistence.listTasks(
              workspace.rootPath,
              chatSessionId: chatSessionId,
            )
            as Iterable<dynamic>;
    return WorkspaceMetadata(
      workspaceName: workspace.displayName,
      rootFiles: profile.rootEntries,
      gitAvailable: (await _sandbox.inspectPath(
        workspace.rootPath,
        '.git',
      )).exists,
      commandExecutionApproved: workspace.commandExecutionApproved,
      existingTaskIds: [for (final task in existingTasks) task.id.toString()],
      workspaceProfile: profile,
    );
  }

  Future<_StepExecutionOutput> _executeStep({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required Task task,
    required TaskStep step,
    required TaskRun run,
    required String baseSystemPrompt,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    required TaskExecutionRequest executionRequest,
  }) => _stepLoop.execute(
    client: client,
    workspace: workspace,
    task: task,
    step: step,
    run: run,
    baseSystemPrompt: baseSystemPrompt,
    compactionSettings: compactionSettings,
    contextLimitTokens: contextLimitTokens,
    onCompactionStatus: onCompactionStatus,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
    executionRequest: executionRequest,
  );

  Future<_StepExecutionOutput> _applyCompletionGates({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required Task task,
    required TaskStep step,
    required _StepExecutionOutput execution,
    required String baseSystemPrompt,
    CancellationToken? cancellationToken,
  }) async {
    final gates = _executionPolicy.completionGates(task, step);
    if (gates.isEmpty) return execution;
    // Gate scope comes from the persisted plan, never from model output or a
    // partial set of observed writes. This keeps artifact existence/content
    // checks authoritative for every declared artifact.
    final stepArtifacts = step.artifacts.isEmpty
        ? execution.artifacts
        : step.artifacts;
    final taskToolCalls = [
      for (final run in task.runs) ...run.toolCalls,
      ...execution.toolCalls,
    ];
    final taskArtifacts = <TaskArtifact>[
      for (final run in task.runs) ...run.artifacts,
      for (final taskStep in task.steps) ...taskStep.artifacts,
      ...stepArtifacts,
    ];

    final evaluation = await _gateEvaluator.evaluate(
      workspace: workspace,
      task: task,
      step: step,
      gates: gates,
      evidence: TaskGateEvidence(
        stepToolCalls: execution.toolCalls,
        taskToolCalls: taskToolCalls,
        stepArtifacts: stepArtifacts,
        taskArtifacts: taskArtifacts,
      ),
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      humanApprovalGranted: step.status == TaskStepStatus.approved,
      cancellationToken: cancellationToken,
    );
    if (!evaluation.hasRequiredFailure && !evaluation.hasRequiredPending) {
      return execution.copyWith(gateResults: evaluation.results);
    }

    final summary = [
      execution.summary,
      'Completion gates did not pass:',
      evaluation.blockingSummary,
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    if (evaluation.hasRequiredFailure) {
      return execution.copyWith(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: summary,
        error: evaluation.blockingSummary,
        gateResults: evaluation.results,
      );
    }
    if (evaluation.hasHumanApprovalPending) {
      return execution.copyWith(
        status: _StepExecutionStatus.blocked,
        runStatus: TaskRunStatus.blocked,
        summary: summary,
        userQuestion: 'Approve completion after reviewing gate results.',
        gateResults: evaluation.results,
      );
    }
    return execution.copyWith(
      status: _StepExecutionStatus.needsReplan,
      runStatus: TaskRunStatus.needsReplan,
      summary: summary,
      replanRequest:
          'Add or run the missing verification needed to satisfy completion gates.',
      gateResults: evaluation.results,
    );
  }

  _StepExecutionOutput _applyQuestionPolicy(
    _StepExecutionOutput execution, {
    required QuestionAutonomy autonomy,
  }) {
    final questionText = execution.userQuestion?.trim();
    if (questionText == null || questionText.isEmpty) return execution;
    final decision = _questionPolicy.decide(
      question: execution.agentQuestion ?? AgentQuestion.fromText(questionText),
      autonomy: autonomy,
    );
    if (decision.shouldBlock) return execution;
    final summary = [
      execution.summary,
      'Question policy continued with an assumption:',
      decision.assumption,
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    return execution.copyWith(
      status: _StepExecutionStatus.completed,
      runStatus: TaskRunStatus.completed,
      summary: summary,
      memoryUpdate: _appendMemory(execution.memoryUpdate, decision.assumption),
      userQuestion: null,
      agentQuestion: null,
      error: null,
    );
  }

  // Gate and tool-surface policy is delegated to TaskExecutionPolicy.
  _TaskTerminalToolCallResult _terminalTaskToolCall({
    required String callName,
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
    required TaskExecutionRequest executionRequest,
  }) {
    return switch (callName) {
      _finishTaskStepToolId => _finishStepFromToolCall(
        args: args,
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
        executionRequest: executionRequest,
      ),
      _requestTaskUserDecisionToolId => _requestUserDecisionFromToolCall(
        args: args,
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      ),
      _requestTaskReplanToolId => _requestReplanFromToolCall(
        args: args,
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      ),
      _ => _invalidTaskControlCall(
        'Unknown task control tool: $callName.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      ),
    };
  }

  _TaskTerminalToolCallResult _invalidTaskControlCall(
    String error, {
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    final resultJson = _taskToolErrorJson(
      code: 'invalid_task_control_arguments',
      message: error,
      disposition: TaskToolErrorDisposition.advisory,
    );
    return _TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      error: error,
      output: _StepExecutionOutput(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: error,
        memoryUpdate: '',
        artifacts: _toolExecution.artifactsFromToolCalls(
          task.id,
          step,
          existingToolCalls,
        ),
        toolCalls: existingToolCalls,
        error: error,
      ),
    );
  }

  _TaskTerminalToolCallResult _requestUserDecisionFromToolCall({
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    if (args is! Map) {
      return _invalidTaskControlCall(
        'task_request_user_decision arguments must be a JSON object.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final question = const QuestionProtocolAdapter().decode(args);
    if (question == null || question.question.trim().isEmpty) {
      return _invalidTaskControlCall(
        'task_request_user_decision requires a question.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final resultJson = jsonEncode({
      'recorded': true,
      'status': 'blocked',
      'question': question.question.trim(),
    });
    return _TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      output: _StepExecutionOutput(
        status: _StepExecutionStatus.blocked,
        runStatus: TaskRunStatus.blocked,
        summary: 'Waiting for a user decision: ${question.question.trim()}',
        memoryUpdate: '',
        artifacts: _toolExecution.artifactsFromToolCalls(
          task.id,
          step,
          existingToolCalls,
        ),
        toolCalls: existingToolCalls,
        userQuestion: question.displayText,
        agentQuestion: question,
      ),
    );
  }

  _TaskTerminalToolCallResult _requestReplanFromToolCall({
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    if (args is! Map) {
      return _invalidTaskControlCall(
        'task_request_replan arguments must be a JSON object.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final reason = jsonString(args['reason']).trim();
    if (reason.isEmpty) {
      return _invalidTaskControlCall(
        'task_request_replan requires a concrete reason.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final resultJson = jsonEncode({
      'recorded': true,
      'status': 'needs_replan',
      'reason': reason,
    });
    return _TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      output: _StepExecutionOutput(
        status: _StepExecutionStatus.needsReplan,
        runStatus: TaskRunStatus.needsReplan,
        summary: reason,
        memoryUpdate: '',
        artifacts: _toolExecution.artifactsFromToolCalls(
          task.id,
          step,
          existingToolCalls,
        ),
        toolCalls: existingToolCalls,
        replanRequest: reason,
      ),
    );
  }

  _TaskTerminalToolCallResult _finishStepFromToolCall({
    required Object args,
    required Task task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
    required TaskExecutionRequest executionRequest,
  }) {
    if (args is! Map) {
      const error = 'finish_task_step arguments must be a JSON object.';
      final resultJson = _taskToolErrorJson(
        code: 'invalid_finish_arguments',
        message: error,
        disposition: TaskToolErrorDisposition.advisory,
      );
      return _TaskTerminalToolCallResult(
        resultJson: resultJson,
        finalContent: resultJson,
        error: error,
        output: _StepExecutionOutput(
          status: _StepExecutionStatus.failed,
          runStatus: TaskRunStatus.failed,
          summary: error,
          memoryUpdate: '',
          artifacts: _toolExecution.artifactsFromToolCalls(
            task.id,
            step,
            existingToolCalls,
          ),
          toolCalls: existingToolCalls,
          error: error,
        ),
      );
    }

    final json = Map<String, dynamic>.from(args);
    final rawStatus = jsonString(
      json['status'],
    ).trim().toLowerCase().replaceAll('-', '_');
    final parsedStatus = _parseStepExecutionStatusStrict(rawStatus);
    if (parsedStatus == null) {
      return _invalidTaskControlCall(
        'finish_task_step requires status to be either completed or failed.',
        task: task,
        step: step,
        existingToolCalls: existingToolCalls,
      );
    }
    final summary = jsonString(
      json['summary'],
      fallback: parsedStatus == _StepExecutionStatus.failed
          ? 'Step failed.'
          : 'Step completed.',
    );
    // memoryUpdate and evidence claims are model-output fields only. Artifact
    // paths never become execution artifacts; evidence claims are advisory.
    // Authoritative facts come from executed workspace calls and gate
    // evaluation below.
    final finalContent = _encoder.convert({
      'status': rawStatus,
      'summary': summary,
    });
    return _TaskTerminalToolCallResult(
      resultJson: jsonEncode({'finished': true, 'status': rawStatus}),
      finalContent: finalContent,
      output: _StepExecutionOutput(
        status: parsedStatus,
        runStatus: switch (parsedStatus) {
          _StepExecutionStatus.completed => TaskRunStatus.completed,
          _StepExecutionStatus.blocked => TaskRunStatus.blocked,
          _StepExecutionStatus.failed => TaskRunStatus.failed,
          _StepExecutionStatus.needsReplan => TaskRunStatus.needsReplan,
        },
        summary: summary,
        memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
        artifacts: _toolExecution.artifactsFromToolCalls(
          task.id,
          step,
          existingToolCalls,
        ),
        evidenceClaims: _evidenceClaimsFromJson(
          json['evidenceClaims'] ?? json['evidence_claims'],
          executionRequest.criterionIds,
          expectedEvidence: executionRequest.expectedEvidence,
        ),
        toolCalls: existingToolCalls,
        error: jsonNullableString(json['error']),
      ),
    );
  }

  Future<Task> _replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    required String reason,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final context = TaskPlanningToolContext(
      task: snapshot,
      workspaceRoot: workspace.rootPath,
      maxSteps: _taskPlanningStepLimit(snapshot),
      projectGoal: '',
      doneCriteria: snapshot.doneCriteria.isNotEmpty
          ? snapshot.doneCriteria
          : snapshot.successCriteria,
      outOfScope: snapshot.outOfScope,
      readPaths: snapshot.readPaths,
      writePaths: snapshot.writePaths,
      requiredArtifacts: snapshot.expectedArtifacts,
      requiredGates: snapshot.gates,
      preserveCompletedStepsOnly: true,
    );
    final planningResult = await _planningCoordinator.replan(
      client: client,
      context: context,
      label: 'Incremental Task Replan',
      system:
          '''
$baseSystemPrompt

$_taskPlanningToolsSystemInstruction

You are replanning only unfinished work. Completed and skipped steps are
already preserved by Hermes. Add replacement steps for the remaining work,
then call task_commit_plan. Do not recreate, rename, or edit preserved steps.
''',
      user:
          '''
Reason for replan:
$reason

Current bounded task view:
${_encoder.convert(_taskViewService.query(snapshot, maxSteps: _taskPlanningStepLimit(snapshot), doneCriteria: context.doneCriteria, outOfScope: context.outOfScope, readPaths: context.readPaths, writePaths: context.writePaths, requiredGates: context.requiredGates))}
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    var planningMetrics = planningResult.planningMetrics;
    if (context.committedTask != null) {
      final now = DateTime.now();
      final replanRun = TaskRun(
        runId: 'run_${uuid.v7()}',
        stepId: snapshot.currentStepId ?? 'replan',
        status: TaskRunStatus.replanned,
        summary: 'Replanned unfinished work.',
        memoryUpdate: reason,
        toolCalls: const [],
        artifacts: const [],
        startedAt: now,
        completedAt: now,
        replanReason: reason,
      );
      planningMetrics = planningMetrics.copyWith(
        recoveryAttempts: planningMetrics.recoveryAttempts + 1,
        recoverySuccesses: planningMetrics.recoverySuccesses + 1,
      );
      return context.committedTask!.copyWith(
        status: context.committedTask!.pendingQuestion == null
            ? (context.committedTask!.currentStepId == null
                  ? TaskStatus.completed
                  : TaskStatus.paused)
            : TaskStatus.blocked,
        runs: [...snapshot.runs, replanRun],
        memorySummary: _appendMemory(
          context.committedTask!.memorySummary,
          'Replan: $reason',
        ),
        planningMetrics: snapshot.planningMetrics.add(planningMetrics),
        updatedAt: now,
      );
    }
    return _fallbackReplannedTask(
      snapshot,
      reason,
      planningMetrics: planningMetrics.copyWith(
        recoveryAttempts: planningMetrics.recoveryAttempts + 1,
      ),
    );
  }

  int _taskPlanningStepLimit(Task task) {
    final effortLimit = switch (task.effort) {
      TaskEffort.small => 1,
      TaskEffort.medium => 4,
      TaskEffort.large => 6,
    };
    // Older standalone tasks did not persist an effort classification. Do
    // not make their existing multi-step plans impossible to replan.
    return task.steps.length > effortLimit
        ? task.steps.length.clamp(1, 6).toInt()
        : effortLimit;
  }

  Future<Task> createTask({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    String? projectId,
    String? canonicalTaskId,
    TaskPlanningContext? planningContext,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final taskId = canonicalTaskId ?? _newTaskId(userPrompt);
    final metadata = await _collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );

    Task task;
    var planningMetrics = PlanningMetrics(planningStartedAt: now);
    try {
      final incremental = await _completeTaskPlanWithCommands(
        client: client,
        baseSystemPrompt: baseSystemPrompt,
        workspace: workspace,
        taskId: taskId,
        userPrompt: userPrompt,
        metadata: metadata,
        planningContext: planningContext,
        now: now,
        chatSessionId: chatSessionId,
        projectId: projectId,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      planningMetrics = planningMetrics.add(incremental.planningMetrics);
      final plannedTask = incremental.task;
      if (plannedTask != null) {
        task = plannedTask;
      } else {
        task = planningContext == null
            ? _fallbackTask(
                taskId: taskId,
                userPrompt: userPrompt,
                chatSessionId: chatSessionId,
                projectId: projectId,
                now: now,
              )
            : _fallbackProjectBoundedTask(
                taskId: taskId,
                userPrompt: userPrompt,
                chatSessionId: chatSessionId,
                projectId: projectId,
                planningContext: planningContext,
                now: now,
              );
        task = task.copyWith(
          planningError:
              incremental.planningError ??
              'Task planner did not commit an executable plan; safe fallback used.',
        );
      }
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (error) {
      task = planningContext == null
          ? _fallbackTask(
              taskId: taskId,
              userPrompt: userPrompt,
              chatSessionId: chatSessionId,
              projectId: projectId,
              now: now,
            )
          : _fallbackProjectBoundedTask(
              taskId: taskId,
              userPrompt: userPrompt,
              chatSessionId: chatSessionId,
              projectId: projectId,
              planningContext: planningContext,
              now: now,
            );
      task = task.copyWith(
        planningError: 'Task planning failed; safe fallback used: $error',
      );
    }

    final firstExecutableAt = task.currentStepId == null
        ? null
        : DateTime.now();
    planningMetrics = planningMetrics.copyWith(
      timeToFirstExecutableMs: firstExecutableAt == null
          ? null
          : DateTime.now().difference(now).inMilliseconds,
    );
    task = task.copyWith(
      planningMetrics: task.planningMetrics.add(planningMetrics),
    );
    final existing = await _persistenceStore.persistence.loadTaskSnapshot(
      workspace.rootPath,
      task.id,
      includeHistory: false,
    );
    if (existing != null) {
      task = task.copyWith(persistenceRevision: existing.revision);
    }
    return _persistTask(workspace.rootPath, task);
  }

  Future<_IncrementalTaskPlanAttempt> _completeTaskPlanWithCommands({
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
  }) async {
    final task = _taskPlanningSeed(
      taskId: taskId,
      userPrompt: userPrompt,
      planningContext: planningContext,
      chatSessionId: chatSessionId,
      projectId: projectId,
      now: now,
    );
    final requiredArtifacts = [
      for (final artifact in planningContext?.expectedArtifacts ?? const [])
        TaskArtifact(
          path: artifact.path.replaceAll('{{task_id}}', taskId),
          description: artifact.description,
          kind: artifact.kind,
        ),
    ];
    final maxSteps = planningContext?.maxSteps.clamp(1, 6).toInt() ?? 3;
    final context = TaskPlanningToolContext(
      task: task,
      workspaceRoot: workspace.rootPath,
      maxSteps: maxSteps,
      projectGoal: planningContext?.projectGoal ?? '',
      doneCriteria: planningContext?.doneCriteria ?? const [],
      outOfScope: planningContext?.outOfScope ?? const [],
      readPaths: planningContext?.readPaths ?? const [],
      writePaths: planningContext?.writePaths ?? const [],
      requiredArtifacts: requiredArtifacts,
      requiredGates: planningContext?.requiredGates ?? const [],
      requiredEvidence: planningContext?.expectedEvidence ?? const [],
      requireDeclaredWriteBoundary: planningContext != null,
    );
    final planningResult = await _planningCoordinator.plan(
      client: client,
      context: context,
      label: 'Incremental Task Planner',
      system:
          '''
$baseSystemPrompt

$_taskPlanningToolsSystemInstruction
''',
      user:
          '''
Plan this task with the task planning tools. Hermes owns the task ID
$taskId; never use it as a step ID and never supply persistent IDs.

For a bounded Project task, the Project goal is context only: do not plan or
perform the whole Project. Plan only the selected task objective.

User request:
$userPrompt

Bounded workspace profile:
${_encoder.convert(_compactTaskMetadata(metadata))}

      ${planningContext == null ? '' : 'Bounded Project task context:\n${_encoder.convert(_taskPlanningContextMap(planningContext, taskId: taskId))}'}

Workspace context is read-only task context. Do not mutate the project
workspace graph directly; durable graph changes belong to the project planner
or an explicit user command. Task memories remain separate from that graph.
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );

    return _IncrementalTaskPlanAttempt(
      task: context.committedTask,
      usedPlanningTools: context.committedTask != null,
      planningMetrics: planningResult.planningMetrics,
      planningError: planningResult.error,
    );
  }

  Task _taskPlanningSeed({
    required String taskId,
    required String userPrompt,
    required TaskPlanningContext? planningContext,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  }) {
    final objective =
        planningContext?.projectTaskObjective.trim().isNotEmpty == true
        ? planningContext!.projectTaskObjective.trim()
        : userPrompt;
    final title = planningContext?.projectTaskTitle.trim().isNotEmpty == true
        ? planningContext!.projectTaskTitle.trim()
        : _titleFromPrompt(objective);
    final constraints = [
      'Stay within the attached workspace.',
      if (planningContext?.readPaths.isNotEmpty == true)
        'Read paths: ${planningContext!.readPaths.join(', ')}',
      if (planningContext?.writePaths.isNotEmpty == true)
        'Write paths: ${planningContext!.writePaths.join(', ')}',
      if (planningContext?.outOfScope.isNotEmpty == true)
        ...planningContext!.outOfScope.map((item) => 'Out of scope: $item'),
    ];
    return Task(
      id: taskId,
      title: title,
      originalPrompt: userPrompt,
      objective: objective,
      constraints: constraints,
      successCriteria: planningContext?.doneCriteria.isNotEmpty == true
          ? [...planningContext!.doneCriteria]
          : ['Complete the requested task.'],
      gates: planningContext?.requiredGates ?? const [],
      criterionIds: planningContext?.criterionIds ?? const [],
      readPaths: planningContext?.readPaths ?? const [],
      writePaths: planningContext?.writePaths ?? const [],
      doneCriteria: planningContext?.doneCriteria ?? const [],
      outOfScope: planningContext?.outOfScope ?? const [],
      context: planningContext?.knownFacts ?? const [],
      status: TaskStatus.paused,
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> _taskPlanningContextMap(
    TaskPlanningContext context, {
    String? taskId,
  }) => {
    'project_goal': context.projectGoal,
    'task_title': context.projectTaskTitle,
    'task_objective': context.projectTaskObjective,
    'known_facts': context.knownFacts,
    'workspace_orientation': context.workspaceOrientation,
    'workspace_context': context.workspaceContext,
    'done_criteria': context.doneCriteria,
    'out_of_scope': context.outOfScope,
    'criterion_ids': context.criterionIds,
    'criteria': [
      for (final criterion in context.criteria)
        {
          'id': criterion.id,
          'statement': criterion.statement,
          'required': criterion.required,
          'verification_mode': criterion.verificationMode,
        },
    ],
    'read_paths': context.readPaths,
    'write_paths': context.writePaths,
    'expected_artifacts': [
      for (final artifact in context.expectedArtifacts)
        {
          'path': artifact.path.replaceAll(
            '{{task_id}}',
            taskId ?? '{{task_id}}',
          ),
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
    'max_steps': context.maxSteps.clamp(1, 6),
    'required_checks': [
      for (final gate in context.requiredGates)
        {
          'kind': gate.id,
          'required': gate.required,
          'scope': gate.scope,
          'command': gate.params['command'],
          'working_directory':
              gate.params['working_directory'] ??
              gate.params['workingDirectory'],
        },
    ],
    'expected_evidence': [
      for (final item in context.expectedEvidence)
        {
          'type': item.type,
          'description': item.description,
          'required': item.required,
          'source_ref': item.sourceRef,
          'details': item.details,
        },
    ],
  };

  Map<String, dynamic> _compactTaskMetadata(WorkspaceMetadata metadata) {
    final raw = ModelJson.encode(metadata);
    final profile = raw['workspaceProfile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : const <String, dynamic>{};
    List<String> strings(Object? value, {int limit = 80}) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ].take(limit).toList();
    final highSignalFiles = <Map<String, dynamic>>[];
    final rawHighSignalFiles = profileMap['highSignalFiles'];
    if (rawHighSignalFiles is List) {
      for (final rawFile in rawHighSignalFiles.take(6)) {
        if (rawFile is! Map) continue;
        final file = Map<String, dynamic>.from(rawFile);
        final content = file['content']?.toString() ?? '';
        highSignalFiles.add({
          'path': file['path']?.toString() ?? '',
          'content': content.length <= 2200
              ? content
              : '${content.substring(0, 2199).trimRight()}…',
          'truncated': file['truncated'] == true || content.length > 2200,
        });
      }
    }
    return {
      'workspaceName': raw['workspaceName'],
      'commandExecutionApproved': raw['commandExecutionApproved'],
      'rootFiles': strings(raw['rootFiles']),
      'gitAvailable': raw['gitAvailable'] == true,
      'treePaths': strings(profileMap['treePaths'], limit: 160),
      'highSignalFiles': highSignalFiles,
      'packageName': profileMap['packageName'],
      'scripts': profileMap['scripts'],
      'dependencies': strings(profileMap['dependencies']),
      'languages': strings(profileMap['languages']),
      'frameworks': strings(profileMap['frameworks']),
      'treeTruncated': profileMap['treeTruncated'] == true,
    };
  }

  /// Converts an already-bounded Project task directly into one executable
  /// task step without invoking the Task Planner model.
  Future<Task> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  }) async {
    final now = DateTime.now();
    final taskId = canonicalTaskId ?? _newTaskId(userPrompt);
    final task = _fallbackProjectBoundedTask(
      taskId: taskId,
      userPrompt: userPrompt,
      chatSessionId: chatSessionId,
      projectId: projectId,
      planningContext: planningContext,
      now: now,
    );
    final existing = await _persistenceStore.persistence.loadTaskSnapshot(
      workspace.rootPath,
      task.id,
      includeHistory: false,
    );
    final prepared = existing == null
        ? task
        : task.copyWith(persistenceRevision: existing.revision);
    return _persistTask(workspace.rootPath, prepared);
  }

  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required TaskPlanUpdateCommand command,
  }) async {
    final parsed = ModelJson.decode<Task>(command.toWire());
    final now = DateTime.now();
    final normalised = _normaliseEditedTask(
      parsed.copyWith(
        id: snapshot.id,
        persistenceRevision: snapshot.persistenceRevision,
        chatSessionId: snapshot.chatSessionId,
        projectId: snapshot.projectId,
      ),
      snapshot,
      now,
    );
    return _persistTask(workspace.rootPath, normalised);
  }

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
  }) => _stepRunner.run(
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

  Task _fallbackReplannedTask(
    Task snapshot,
    String reason, {
    PlanningMetrics planningMetrics = const PlanningMetrics(),
  }) {
    final now = DateTime.now();
    final preserved = snapshot.steps
        .where(
          (step) =>
              step.status == TaskStepStatus.completed ||
              step.status == TaskStepStatus.skipped,
        )
        .toList();
    final existingIds = preserved.map((step) => step.id).toSet();
    if (preserved.length >= _taskPlanningStepLimit(snapshot)) {
      return snapshot.copyWith(
        status: TaskStatus.blocked,
        planningMetrics: snapshot.planningMetrics.add(planningMetrics),
        memorySummary: _appendMemory(snapshot.memorySummary, 'Replan: $reason'),
        updatedAt: now,
      );
    }
    var replacement = _fallbackExecutionStep(snapshot.id, snapshot.objective);
    if (!existingIds.add(replacement.id)) {
      replacement = replacement.copyWith(id: 'step_${uuid.v7()}');
    }
    final run = TaskRun(
      runId: 'run_${uuid.v7()}',
      stepId: snapshot.currentStepId ?? 'replan',
      status: TaskRunStatus.replanned,
      summary: 'Replanned unfinished work with a safe fallback step.',
      memoryUpdate: reason,
      toolCalls: const [],
      artifacts: const [],
      startedAt: now,
      completedAt: now,
      replanReason: reason,
    );
    final steps = [...preserved, replacement];
    return snapshot.copyWith(
      status: TaskStatus.paused,
      steps: steps,
      currentStepId: replacement.id,
      memorySummary: _appendMemory(snapshot.memorySummary, 'Replan: $reason'),
      runs: [...snapshot.runs, run],
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: null,
      planningMetrics: snapshot.planningMetrics.add(planningMetrics),
      updatedAt: now,
    );
  }

  _StepExecutionOutput _parseStepOutput(
    String raw,
    Task task,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
    TaskExecutionRequest executionRequest,
  ) {
    final json = TaskJson.tryParseObject(raw);
    if (json == null) {
      return _StepExecutionOutput(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: raw.trim().isEmpty
            ? 'The model did not return a structured step result.'
            : 'The model did not return a structured step result: ${raw.trim()}',
        memoryUpdate: '',
        artifacts: const [],
        toolCalls: toolCalls,
        error: 'invalid_step_result',
      );
    }

    final rawStatus = jsonString(
      json['status'],
    ).trim().toLowerCase().replaceAll('-', '_');
    final status = _parseStepExecutionStatusStrict(rawStatus);
    if (status == null) {
      return _StepExecutionOutput(
        status: _StepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: 'The model did not return a valid terminal step status.',
        memoryUpdate: '',
        artifacts: _toolExecution.artifactsFromToolCalls(
          task.id,
          step,
          toolCalls,
        ),
        toolCalls: toolCalls,
        error: 'invalid_step_status',
      );
    }
    // JSON output remains a model-output boundary, but execution facts are
    // never accepted from it. Artifacts come from actual successful workspace
    // calls, and claims are advisory only.
    final artifacts = _toolExecution.artifactsFromToolCalls(
      task.id,
      step,
      toolCalls,
    );
    final summary = jsonString(
      json['summary'],
      fallback: status == _StepExecutionStatus.completed
          ? 'Step completed.'
          : 'Step stopped.',
    );
    final rawUserQuestion = json['userQuestion'] ?? json['user_question'];
    final agentQuestion = const QuestionProtocolAdapter().decode(
      rawUserQuestion,
    );
    return _StepExecutionOutput(
      status: status,
      runStatus: switch (status) {
        _StepExecutionStatus.completed => TaskRunStatus.completed,
        _StepExecutionStatus.blocked => TaskRunStatus.blocked,
        _StepExecutionStatus.failed => TaskRunStatus.failed,
        _StepExecutionStatus.needsReplan => TaskRunStatus.needsReplan,
      },
      summary: summary,
      memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
      artifacts: artifacts,
      evidenceClaims: _evidenceClaimsFromJson(
        json['evidenceClaims'] ?? json['evidence_claims'],
        executionRequest.criterionIds,
        expectedEvidence: executionRequest.expectedEvidence,
      ),
      userQuestion: agentQuestion?.displayText,
      agentQuestion: agentQuestion,
      replanRequest: jsonNullableString(
        json['replanRequest'] ?? json['replan_request'],
      ),
      error: jsonNullableString(json['error']),
      toolCalls: toolCalls,
    );
  }

  Task _completeStep(
    Task snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    final updatedStep = step.copyWith(status: TaskStepStatus.completed);
    final updated = _replaceStep(snapshot, step.id, updatedStep).copyWith(
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        _unverifiedModelReport(
          output.memoryUpdate.isEmpty ? output.summary : output.memoryUpdate,
        ),
      ),
      updatedAt: now,
    );
    return _advanceAfterStep(updated, now);
  }

  Task _blockStep(
    Task snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    return _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: TaskStepStatus.blocked),
    ).copyWith(
      status: TaskStatus.blocked,
      currentStepId: step.id,
      pendingApproval:
          output.gateResults.any(
            (result) =>
                result.gateId == 'human_approval' &&
                result.status == TaskGateStatus.pending &&
                result.details['required'] == true,
          )
          ? PendingTaskApproval(
              stepId: step.id,
              reason: 'Completion requires human approval.',
              createdAt: now,
            )
          : null,
      pendingQuestion: output.userQuestion?.trim().isNotEmpty == true
          ? PendingTaskQuestion(
              id: 'question_${uuid.v7()}',
              stepId: step.id,
              question: output.userQuestion!.trim(),
              createdAt: now,
            )
          : null,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        _unverifiedModelReport(output.summary),
      ),
      updatedAt: now,
    );
  }

  Task _failStep(
    Task snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    return _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: TaskStepStatus.failed),
    ).copyWith(
      status: TaskStatus.failed,
      currentStepId: step.id,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        _unverifiedModelReport(output.summary),
      ),
      updatedAt: now,
    );
  }

  Task _advanceAfterStep(Task snapshot, DateTime now) {
    final currentStepId = _nextStepId(snapshot.steps);
    return snapshot.copyWith(
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      currentStepId: currentStepId,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: currentStepId == null ? now : null,
      updatedAt: now,
    );
  }

  Task _markCompleted(Task snapshot) {
    final now = DateTime.now();
    return snapshot.copyWith(
      status: TaskStatus.completed,
      currentStepId: null,
      completedAt: now,
      updatedAt: now,
    );
  }

  Task _replaceStep(Task snapshot, String stepId, TaskStep step) {
    final index = snapshot.steps.indexWhere((item) => item.id == stepId);
    if (index < 0) return snapshot;
    final steps = [...snapshot.steps];
    steps[index] = step;
    return snapshot.copyWith(steps: steps);
  }

  Task _replaceLastRun(Task snapshot, TaskRun run) {
    if (snapshot.runs.isEmpty) return snapshot.copyWith(runs: [run]);
    final runs = [...snapshot.runs];
    runs[runs.length - 1] = run;
    return snapshot.copyWith(runs: runs);
  }

  String? _nextStepId(List<TaskStep> steps) {
    for (final step in steps) {
      if (step.status == TaskStepStatus.pending ||
          step.status == TaskStepStatus.approved ||
          step.status == TaskStepStatus.blocked ||
          step.status == TaskStepStatus.failed) {
        return step.id;
      }
    }
    return null;
  }

  String _buildStepPrompt(
    Task task,
    TaskStep step,
    WorkspaceAttachment workspace,
    TaskExecutionRequest executionRequest,
  ) {
    final previousRuns = task.runs
        .where((run) => run.status != TaskRunStatus.running)
        .map((run) => '- ${run.stepId}: ${_unverifiedModelReport(run.summary)}')
        .join('\n');
    final availableArtifacts = _buildAvailableArtifactInputs(task, step);
    final stepIndex = task.steps.indexWhere((item) => item.id == step.id);
    final isFinalPlannedStep =
        stepIndex >= 0 &&
        task.steps
            .skip(stepIndex + 1)
            .every(
              (item) =>
                  item.status == TaskStepStatus.completed ||
                  item.status == TaskStepStatus.skipped,
            );
    return '''
Task objective:
${task.objective}

Original request:
${task.originalPrompt}

Constraints:
${task.constraints.map((item) => '- $item').join('\n')}

Success criteria:
${task.successCriteria.map((item) => '- $item').join('\n')}

Linked Project criteria:
${executionRequest.criteria.isEmpty ? _encoder.convert(executionRequest.criterionIds) : _encoder.convert(executionRequest.criteria.map(ModelJson.encode).toList())}

Expected Project evidence:
${executionRequest.expectedEvidence.isEmpty ? 'None specified.' : _encoder.convert(executionRequest.expectedEvidence.map(ModelJson.encode).toList())}

Current memory:
${task.memorySummary.trim().isEmpty ? 'None yet.' : task.memorySummary}

Full plan:
${_encoder.convert(task.steps.map(ModelJson.encode).toList())}

Current step:
${_encoder.convert(ModelJson.encode(step))}

Available artifact inputs:
$availableArtifacts

Step tool permissions:
${_stepToolPermissionText(task, step, workspace)}

Previous run summaries:
${previousRuns.trim().isEmpty ? 'None yet.' : previousRuns}

This ${isFinalPlannedStep ? 'is' : 'is not'} the final planned task step.
${executionRequest.criterionIds.isNotEmpty ? 'Project evidence is derived from successful workspace calls and evaluated gates. Your summary is advisory; do not claim that a command passed unless its gate result confirms it.' : 'Do not claim work that has not been verified.'}

When finished, call finish_task_step with only this result object. If finish_task_step is unavailable, return only JSON:
{
  "status": "completed|failed",
  "summary": "what happened in this step"
}
For a genuinely blocking user decision, call task_request_user_decision with
the question and context. If the approach is wrong or incomplete, call
task_request_replan with a concrete reason. Those tools end the step.
''';
  }

  String _stepToolPermissionText(
    Task task,
    TaskStep step,
    WorkspaceAttachment workspace,
  ) {
    final terminalStatus = workspace.commandExecutionApproved
        ? 'Host terminal access is approved for this session. Commands are not sandboxed.'
        : 'Host terminal access is disabled until the user approves it from the workspace chip.';
    final allowedCommands = _executionPolicy.allowedCommands(task, step);
    final availableTools =
        (_executionPolicy.allowedToolIds(step, allowedCommands).toList()
              ..sort())
            .join(', ');
    final stepPolicy = step.mayEditFiles
        ? 'This step may edit files after any required user approval. Mutating workspace tools and terminal commands may be available.'
        : allowedCommands.isEmpty
        ? 'This is a read-only step. It may read workspace files and create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, but it must not overwrite existing files, edit source files, rename paths, delete paths, or run terminal commands.'
        : 'This is a read-only step. It may read workspace files, create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, and run only the whitelisted verification terminal commands listed below. It must not overwrite existing files, edit source files, rename paths, delete paths, or run any other terminal command.';
    final whitelist = allowedCommands.isEmpty
        ? ''
        : '\n- Whitelisted terminal commands for this step: ${_encoder.convert([
            for (final item in allowedCommands) {'command': item.command, 'working_directory': item.workingDirectory},
          ])}.\n- Exact-command requirement: pass both `command` and `working_directory` to `run_command` exactly as listed to satisfy the command_passes gate. Do not add or remove arguments, flags, pipes, redirects, shell wrappers, or combined commands. ${step.mayEditFiles ? 'A variation may be available through this step\'s broader terminal permission, but it will not satisfy the gate.' : 'Any variation will be rejected and will not satisfy the gate.'}';
    return '''
- $terminalStatus
- $stepPolicy
- Tools exposed to this step: $availableTools.
$whitelist
'''
        .trim();
  }

  String _buildAvailableArtifactInputs(Task task, TaskStep step) {
    final currentIndex = task.steps.indexWhere((item) => item.id == step.id);
    final priorStepIds = <String>{};
    if (currentIndex > 0) {
      for (final priorStep in task.steps.take(currentIndex)) {
        if (priorStep.status == TaskStepStatus.completed ||
            priorStep.status == TaskStepStatus.skipped) {
          priorStepIds.add(priorStep.id);
        }
      }
    }

    final artifacts = <TaskArtifact>[
      for (final run in task.runs)
        if (priorStepIds.contains(run.stepId)) ...run.artifacts,
      for (final priorStep in task.steps)
        if (priorStepIds.contains(priorStep.id)) ...priorStep.artifacts,
      ...step.artifacts,
    ];

    final seen = <String>{};
    final lines = <String>[];
    for (final artifact in artifacts) {
      final artifactPath = path.normalize(artifact.path.trim());
      if (artifactPath.isEmpty || !seen.add(artifactPath)) continue;
      final suffix = artifact.description == null
          ? ''
          : ' - ${artifact.description}';
      lines.add('- $artifactPath$suffix');
    }
    return lines.isEmpty ? 'None.' : lines.join('\n');
  }

  Task _normaliseEditedTask(Task candidate, Task original, DateTime now) {
    final steps = candidate.steps.isEmpty
        ? original.steps
        : _normaliseUniqueSteps(candidate.steps);
    final currentStepId =
        candidate.currentStepId != null &&
            steps.any((step) => step.id == candidate.currentStepId)
        ? candidate.currentStepId
        : _nextStepId(steps);
    return candidate.copyWith(
      title: candidate.title.trim().isEmpty ? original.title : candidate.title,
      originalPrompt: candidate.originalPrompt.trim().isEmpty
          ? original.originalPrompt
          : candidate.originalPrompt,
      objective: candidate.objective.trim().isEmpty
          ? original.objective
          : candidate.objective,
      gates: _dedupeGates(candidate.gates),
      steps: steps,
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      currentStepId: currentStepId,
      createdAt: original.createdAt,
      updatedAt: now,
    );
  }

  List<TaskEvidenceClaim> _evidenceClaimsFromJson(
    Object? value,
    List<String> allowedCriterionIds, {
    List<TaskProjectEvidenceExpectation> expectedEvidence = const [],
  }) {
    if (value is! List || allowedCriterionIds.isEmpty) return const [];
    final allowed = allowedCriterionIds.toSet();
    final allowedExpectationIds = {
      for (final expectation in expectedEvidence)
        if (allowed.containsAll(expectation.criterionIds)) expectation.id,
    };
    final seen = <String>{};
    final claims = <TaskEvidenceClaim>[];
    for (final raw in value.whereType<Map>()) {
      final map = Map<String, dynamic>.from(raw);
      final criterionId = jsonString(map['criterionId'] ?? map['criterion_id']);
      final rawExpectationId = jsonNullableString(
        map['expectationId'] ?? map['expectation_id'],
      );
      final expectationId =
          rawExpectationId != null &&
              allowedExpectationIds.contains(rawExpectationId)
          ? rawExpectationId
          : null;
      final claim = jsonString(map['claim']);
      final sourceRef = jsonString(map['sourceRef'] ?? map['source_ref']);
      if (!allowed.contains(criterionId) ||
          claim.isEmpty ||
          sourceRef.isEmpty) {
        continue;
      }
      final evidenceType = switch (jsonString(
        map['evidenceType'] ?? map['evidence_type'],
      ).toLowerCase().replaceAll('-', '_')) {
        'gate' => TaskEvidenceClaimType.gate,
        'artifact' => TaskEvidenceClaimType.artifact,
        'command' => TaskEvidenceClaimType.command,
        'user_approval' || 'userapproval' => TaskEvidenceClaimType.userApproval,
        _ => TaskEvidenceClaimType.taskClaim,
      };
      // A model can suggest where a claim belongs, but it cannot promote its
      // own assertion. Conclusive/supporting evidence is created from gates
      // and actual workspace provenance at the execution boundary.
      const strength = TaskEvidenceClaimStrength.advisory;
      final key = '$criterionId|${evidenceType.name}|$sourceRef|$claim';
      if (!seen.add(key)) continue;
      claims.add(
        TaskEvidenceClaim(
          criterionId: criterionId,
          claim: claim,
          evidenceType: evidenceType,
          sourceRef: sourceRef,
          suggestedStrength: strength,
          expectationId: expectationId,
        ),
      );
    }
    return claims;
  }

  List<TaskGate> _defaultTaskGates(List<TaskStep> steps, String prompt) {
    final mutating = steps.any((step) => step.mayEditFiles);
    final looksCoding = _looksLikeCodingTask(prompt);
    if (!mutating && !looksCoding) return const [];
    return const [
      TaskGate(
        id: 'no_tool_errors',
        required: true,
        scope: 'task',
        description: 'No unresolved fatal workspace tool errors.',
      ),
      TaskGate(
        id: 'no_failed_commands',
        required: true,
        scope: 'task',
        description: 'No failed terminal commands after workspace mutation.',
      ),
    ];
  }

  List<TaskGate> _defaultArtifactGates(List<TaskArtifact> artifacts) {
    final paths = artifacts
        .map((artifact) => artifact.path)
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (paths.isEmpty) return const [];
    return [
      TaskGate(
        id: 'artifact_exists',
        required: true,
        scope: 'step',
        params: {'paths': paths},
        description: 'Declared artifacts must exist.',
      ),
      TaskGate(
        id: 'artifact_nonempty',
        required: true,
        scope: 'step',
        params: {'paths': paths},
        description:
            'Declared file artifacts must be non-empty; directories must exist.',
      ),
    ];
  }

  List<TaskGate> _dedupeGates(List<TaskGate> gates) {
    final seen = <String>{};
    final deduped = <TaskGate>[];
    for (final gate in gates) {
      final key = _encoder.convert({
        'id': gate.id,
        'scope': gate.scope,
        'params': gate.params,
      });
      if (seen.add(key)) deduped.add(gate);
    }
    return deduped;
  }

  bool _looksLikeCodingTask(String value) {
    final normalised = value.toLowerCase();
    return const [
      'code',
      'test',
      'build',
      'bug',
      'fix',
      'implement',
      'refactor',
      'compile',
      'flutter',
      'dart',
      'dotnet',
      'npm',
      'api',
    ].any(normalised.contains);
  }

  TaskStep _normaliseStep(TaskStep step) {
    return step.copyWith(
      id: _safeId(step.id, 'step'),
      title: step.title.trim().isEmpty ? step.id : step.title,
      objective: step.objective.trim().isEmpty ? step.title : step.objective,
      instructions: step.instructions,
      gates: _dedupeGates(step.gates),
      status: switch (step.status) {
        TaskStepStatus.running => TaskStepStatus.pending,
        _ => step.status,
      },
    );
  }

  List<TaskStep> _normaliseUniqueSteps(Iterable<TaskStep> source) {
    final usedIds = <String>{};
    final result = <TaskStep>[];
    for (final step in source) {
      final normalised = _normaliseStep(step);
      var id = normalised.id;
      var suffix = 2;
      while (!usedIds.add(id)) {
        id = '${normalised.id}_$suffix';
        suffix++;
      }
      result.add(_rebindStep(normalised, id));
    }
    return result;
  }

  TaskStep _rebindStep(TaskStep step, String id) {
    if (step.id == id &&
        step.artifacts.every((artifact) => artifact.stepId == id)) {
      return step;
    }
    return step.copyWith(
      id: id,
      artifacts: [
        for (final artifact in step.artifacts) artifact.copyWith(stepId: id),
      ],
    );
  }

  RefinedTaskBrief _normaliseBrief(RefinedTaskBrief brief, String prompt) {
    return RefinedTaskBrief(
      title: brief.title.trim().isEmpty
          ? _titleFromPrompt(prompt)
          : brief.title,
      goal: brief.goal.trim().isEmpty ? prompt : brief.goal,
      constraints: brief.constraints,
      successCriteria: brief.successCriteria,
      assumptions: brief.assumptions,
      questions: brief.questions.take(3).toList(),
    );
  }

  RefinedTaskBrief _fallbackBrief(String prompt) {
    return RefinedTaskBrief(
      title: _titleFromPrompt(prompt),
      goal: prompt,
      successCriteria: const ['Complete the requested task.'],
      assumptions: const ['Use the attached workspace as the source of truth.'],
    );
  }

  Task _fallbackTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  }) {
    final step = _fallbackExecutionStep(taskId, userPrompt);
    return Task(
      id: taskId,
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      objective: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      successCriteria: const ['Complete the requested task.'],
      gates: _defaultTaskGates([step], userPrompt),
      steps: [step],
      status: TaskStatus.paused,
      currentStepId: step.id,
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Task _fallbackProjectBoundedTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    required DateTime now,
  }) {
    final artifactPaths = planningContext.expectedArtifacts.isEmpty
        ? planningContext.requiredGates.isNotEmpty
              ? const <TaskArtifact>[]
              : [
                  TaskArtifact(
                    path: '.agent/tasks/$taskId/task-output.md',
                    description: 'Bounded task output',
                    stepId: 'execute_project_task',
                  ),
                ]
        : planningContext.expectedArtifacts
              .map(
                (artifact) => TaskArtifact(
                  path: artifact.path.replaceAll('{{task_id}}', taskId),
                  description: artifact.description,
                  kind: artifact.kind,
                  stepId: 'execute_project_task',
                ),
              )
              .toList();
    final successCriteria = planningContext.doneCriteria.isEmpty
        ? ['Complete the selected bounded Project task.']
        : planningContext.doneCriteria;
    final mayEditFiles = planningContext.writePaths.isNotEmpty;
    final step = TaskStep(
      id: 'execute_project_task',
      title: 'Execute bounded project task',
      objective: planningContext.projectTaskObjective,
      instructions: [
        'Complete only the selected Project task objective.',
        if (planningContext.knownFacts.isNotEmpty)
          'Use the provided Project facts as context.',
        if (planningContext.outOfScope.isNotEmpty)
          'Do not perform any out-of-scope work.',
        if (planningContext.readPaths.isNotEmpty)
          'Prefer reads within: ${planningContext.readPaths.join(', ')}.',
        if (planningContext.writePaths.isNotEmpty)
          'Limit workspace writes to: ${planningContext.writePaths.join(', ')}.',
        if (!mayEditFiles)
          'This is a read-only task; do not modify workspace files.',
        'Report what was completed and what remains.',
      ],
      mayEditFiles: mayEditFiles,
      artifacts: artifactPaths,
      gates: planningContext.expectedArtifacts.isEmpty
          ? const []
          : _defaultArtifactGates(artifactPaths),
      status: TaskStepStatus.pending,
    );
    return Task(
      id: taskId,
      title: planningContext.projectTaskTitle.trim().isEmpty
          ? _titleFromPrompt(planningContext.projectTaskObjective)
          : planningContext.projectTaskTitle.trim(),
      originalPrompt: userPrompt,
      objective: planningContext.projectTaskObjective,
      constraints: [
        'Stay within the attached workspace.',
        if (planningContext.readPaths.isNotEmpty)
          'Read paths: ${planningContext.readPaths.join(', ')}',
        if (planningContext.writePaths.isNotEmpty)
          'Write paths: ${planningContext.writePaths.join(', ')}',
        ...planningContext.outOfScope.map((item) => 'Out of scope: $item'),
      ],
      successCriteria: successCriteria,
      gates: _dedupeGates([
        ...planningContext.requiredGates,
        ..._defaultTaskGates([step], planningContext.projectTaskObjective),
      ]),
      steps: [step],
      status: TaskStatus.paused,
      currentStepId: step.id,
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskStep _fallbackExecutionStep(String taskId, String objective) {
    final artifacts = [
      TaskArtifact(
        path: '.agent/tasks/$taskId/task-output.md',
        description: 'Final task output',
        stepId: 'execute_task',
      ),
    ];
    return TaskStep(
      id: 'execute_task',
      title: 'Execute task',
      objective: objective,
      instructions: const [
        'Inspect the workspace as needed.',
        'Carry out the requested work.',
        'Summarize what changed and what remains.',
      ],
      mayEditFiles: true,
      artifacts: artifacts,
      gates: _defaultArtifactGates(artifacts),
      status: TaskStepStatus.pending,
    );
  }

  String _newTaskId(String prompt) {
    final slug = _titleFromPrompt(prompt)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = slug.isEmpty ? 'task' : slug;
    return 'task_${prefix.length > 32 ? prefix.substring(0, 32) : prefix}_${uuid.v7().substring(0, 8)}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled task';
    return singleLine.length <= 60
        ? singleLine
        : '${singleLine.substring(0, 57)}...';
  }

  String _safeId(String value, String fallback) {
    final id = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return id.isEmpty ? fallback : id;
  }

  _StepExecutionStatus? _parseStepExecutionStatusStrict(String raw) {
    return switch (raw) {
      'blocked' => _StepExecutionStatus.blocked,
      'needs_replan' || 'replan' => _StepExecutionStatus.needsReplan,
      'failed' || 'failure' => _StepExecutionStatus.failed,
      'completed' || 'complete' => _StepExecutionStatus.completed,
      _ => null,
    };
  }

  TaskToolError? _toolErrorInfo(Map<String, dynamic>? result) {
    if (result == null) return null;
    return taskToolErrorFromResult(result);
  }

  TaskToolError? _toolErrorInfoForCall(
    String toolName,
    Map<String, dynamic>? result,
  ) {
    final error = _toolErrorInfo(result);
    if (error != null) return error;
    if (toolName != 'run_command' || _commandExitCode(result) != null) {
      return null;
    }
    return const TaskToolError(
      code: 'invalid_command_result',
      message: 'run_command did not return a valid exit_code.',
      disposition: TaskToolErrorDisposition.retryable,
    );
  }

  int? _commandExitCode(Map<String, dynamic>? result) {
    if (result == null || !result.containsKey('exit_code')) return null;
    final raw = result['exit_code'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  TaskToolCallOutcome _toolCallOutcome(
    Map<String, dynamic>? result,
    TaskToolError? error,
  ) {
    if (result?['skipped'] == true) return TaskToolCallOutcome.skipped;
    if (error == null) return TaskToolCallOutcome.succeeded;
    if (error.disposition == TaskToolErrorDisposition.advisory) {
      return TaskToolCallOutcome.denied;
    }
    return TaskToolCallOutcome.failed;
  }

  String _operationKey(String toolName, Object? rawArguments) {
    final arguments = jsonMap(rawArguments);
    String normalisePath(Object? value) {
      final raw = value?.toString().trim() ?? '';
      return raw.isEmpty ? '.' : path.normalize(raw);
    }

    return switch (toolName) {
      'read_file' => 'read:${normalisePath(arguments['path'])}',
      'list_directory' => 'list:${normalisePath(arguments['path'])}',
      'search_files' =>
        'search:${normalisePath(arguments['path'])}:${jsonString(arguments['query']).trim()}',
      'write_file' ||
      'patch_file' => 'write:${normalisePath(arguments['path'])}',
      'create_directory' => 'mkdir:${normalisePath(arguments['path'])}',
      'delete_path' => 'delete:${normalisePath(arguments['path'])}',
      'rename_path' =>
        'rename:${normalisePath(arguments['from'])}->${normalisePath(arguments['to'])}',
      'run_command' =>
        'command:${path.normalize(jsonString(arguments['working_directory'] ?? arguments['workingDirectory'], fallback: '.'))}:${_executionPolicy.commandTextFromParts(jsonString(arguments['command']), jsonStringList(arguments['args']))}',
      _ => toolName,
    };
  }

  String _taskToolErrorJson({
    required String code,
    required String message,
    required TaskToolErrorDisposition disposition,
    Map<String, dynamic> details = const {},
  }) {
    return jsonEncode(
      toolErrorPayload(
        code: code,
        message: message,
        disposition: disposition,
        details: details,
      ),
    );
  }

  Map<String, dynamic>? _structuredToolResult(
    String toolName,
    String resultJson,
  ) {
    final decoded = TaskJson.tryParseObject(resultJson);
    if (decoded == null) return null;

    final result = <String, dynamic>{};
    void copyKey(String key) {
      if (decoded.containsKey(key)) result[key] = decoded[key];
    }

    if (toolName == _requestTaskUserDecisionToolId) {
      copyKey('recorded');
      copyKey('status');
      copyKey('question');
    } else if (toolName == _requestTaskReplanToolId) {
      copyKey('recorded');
      copyKey('status');
      copyKey('reason');
    } else if (toolName == 'run_command') {
      copyKey('command');
      copyKey('working_directory');
      copyKey('exit_code');
      copyKey('error');
      copyKey('reason');
    } else {
      copyKey('error');
      copyKey('reason');
      copyKey('skipped');
      copyKey('path');
      copyKey('from');
      copyKey('to');
    }
    copyKey('error_code');
    copyKey('error_disposition');

    return result.isEmpty ? null : result;
  }

  String _appendMemory(String current, String update) {
    final trimmed = update.trim();
    if (trimmed.isEmpty) return current;
    final parts = [if (current.trim().isNotEmpty) current.trim(), trimmed];
    return _cap(parts.join('\n\n'), 12000);
  }

  String _unverifiedModelReport(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return 'Model-reported (unverified): $trimmed';
  }

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }

  Future<Task> _persistTask(String workspaceRoot, Task task) async {
    final persisted = await _persistenceStore.save(workspaceRoot, task);
    return persisted.value;
  }

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _persistenceStore.list(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<Task?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final snapshot = await _persistenceStore.loadLatest(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
    return snapshot?.value;
  }

  Future<Task?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) async {
    final snapshot = await _persistenceStore.load(
      workspace.rootPath,
      taskId,
      chatSessionId: chatSessionId,
      projectId: projectId,
      includeHistory: includeHistory,
    );
    return snapshot?.value;
  }

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _persistenceStore.deleteForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _persistenceStore.deleteOrphaned(
      workspace.rootPath,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<Task> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      chatSessionId: chatSessionId,
      updatedAt: DateTime.now(),
    );
    return _persistTask(workspace.rootPath, updated);
  }

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final now = DateTime.now();
    final recovered = _recoveryService.recover(snapshot, now: now);
    return persist ? _persistTask(workspace.rootPath, recovered) : recovered;
  }

  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  }) async {
    try {
      return await _sandbox.readFilePreview(
        workspace.rootPath,
        artifactPath,
        maxChars: 240000,
        cancellationToken: cancellationToken,
      );
    } on WorkspaceSandboxException catch (error) {
      if (error.message.contains('Path not found')) {
        throw StateError('Artifact not found: $artifactPath');
      }
      rethrow;
    }
  }

  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final metadata = workspace == null || workspace.missing
        ? const WorkspaceMetadata()
        : await _collectWorkspaceMetadata(workspace);

    try {
      final json = await _modelCompletion.completeJson(
        client: client,
        system: _refinerSystemInstruction,
        expectedShape:
            '{"title":"...","goal":"...","constraints":[],"successCriteria":[],"assumptions":[],"questions":[]}',
        label: 'Prompt Refiner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Refine this request into a concise brief for a long-horizon task planner.

Return only JSON:
{
  "title": "...",
  "goal": "...",
  "constraints": ["..."],
  "successCriteria": ["..."],
  "assumptions": ["..."],
  "questions": ["..."]
}

Selected mode: ${selectedMode.wire}
Workspace metadata:
${_encoder.convert(ModelJson.encode(metadata))}

Request:
$userPrompt
''',
      );
      return _normaliseBrief(
        ModelJson.decode<RefinedTaskBrief>(json.toWire()),
        userPrompt,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return _fallbackBrief(userPrompt);
    }
  }
}
