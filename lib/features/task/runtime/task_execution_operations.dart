part of 'task_execution_coordinator.dart';

extension TaskExecutionOperations on TaskExecutionUseCase {
  Future<TaskAggregate> _runNextStepCore({
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
  }) async {
    cancellationToken?.throwIfCancelled();
    var working = await _recoverTask(
      workspace: workspace,
      snapshot: snapshot,
      persist: persist,
    );
    Future<TaskAggregate> save(TaskAggregate task) =>
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
      if (execution.status == TaskStepExecutionStatus.completed) {
        execution = await _applyCompletionGates(
          client: client,
          workspace: workspace,
          task: working,
          step: step,
          execution: execution,
          baseSystemPrompt: baseSystemPrompt,
          cancellationToken: cancellationToken,
        );
      } else if (execution.status == TaskStepExecutionStatus.blocked) {
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
        case TaskStepExecutionStatus.completed:
          working = _completeStep(working, step, execution, finishedAt);
          break;
        case TaskStepExecutionStatus.blocked:
          working = _blockStep(working, step, execution, finishedAt);
          break;
        case TaskStepExecutionStatus.failed:
          working = _failStep(working, step, execution, finishedAt);
          break;
        case TaskStepExecutionStatus.needsReplan:
          working = await _replanUnfinished(
            client: client,
            workspace: workspace,
            snapshot: working,
            baseSystemPrompt: baseSystemPrompt,
            executionRequest: executionRequest,
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

  Future<WorkspaceMetadata> _collectWorkspaceMetadata(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final profile = await _profileService.collect(workspace: workspace);
    final existingTasks =
        await _persistenceStore.listTasks(
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

  Future<TaskStepExecutionOutput> _executeStep({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
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

  Future<TaskStepExecutionOutput> _applyCompletionGates({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
    required TaskStep step,
    required TaskStepExecutionOutput execution,
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
        status: TaskStepExecutionStatus.failed,
        runStatus: TaskRunStatus.failed,
        summary: summary,
        error: evaluation.blockingSummary,
        gateResults: evaluation.results,
      );
    }
    if (evaluation.hasHumanApprovalPending) {
      return execution.copyWith(
        status: TaskStepExecutionStatus.blocked,
        runStatus: TaskRunStatus.blocked,
        summary: summary,
        userQuestion: 'Approve completion after reviewing gate results.',
        gateResults: evaluation.results,
      );
    }
    return execution.copyWith(
      status: TaskStepExecutionStatus.needsReplan,
      runStatus: TaskRunStatus.needsReplan,
      summary: summary,
      replanRequest:
          'Add or run the missing verification needed to satisfy completion gates.',
      gateResults: evaluation.results,
    );
  }

  TaskStepExecutionOutput _applyQuestionPolicy(
    TaskStepExecutionOutput execution, {
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
      status: TaskStepExecutionStatus.completed,
      runStatus: TaskRunStatus.completed,
      summary: summary,
      memoryUpdate: _appendMemory(execution.memoryUpdate, decision.assumption),
      userQuestion: null,
      agentQuestion: null,
      error: null,
    );
  }

  // Gate and tool-surface policy is delegated to TaskExecutionPolicy.
  TaskTerminalToolCallResult _terminalTaskToolCall({
    required String callName,
    required Object args,
    required TaskAggregate task,
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

  TaskTerminalToolCallResult _invalidTaskControlCall(
    String error, {
    required TaskAggregate task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    final resultJson = _taskToolErrorJson(
      code: 'invalid_task_control_arguments',
      message: error,
      disposition: TaskToolErrorDisposition.advisory,
    );
    return TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      error: error,
      output: TaskStepExecutionOutput(
        status: TaskStepExecutionStatus.failed,
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

  TaskTerminalToolCallResult _requestUserDecisionFromToolCall({
    required Object args,
    required TaskAggregate task,
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
    return TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      output: TaskStepExecutionOutput(
        status: TaskStepExecutionStatus.blocked,
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

  TaskTerminalToolCallResult _requestReplanFromToolCall({
    required Object args,
    required TaskAggregate task,
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
    return TaskTerminalToolCallResult(
      resultJson: resultJson,
      finalContent: resultJson,
      output: TaskStepExecutionOutput(
        status: TaskStepExecutionStatus.needsReplan,
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

  TaskTerminalToolCallResult _finishStepFromToolCall({
    required Object args,
    required TaskAggregate task,
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
      return TaskTerminalToolCallResult(
        resultJson: resultJson,
        finalContent: resultJson,
        error: error,
        output: TaskStepExecutionOutput(
          status: TaskStepExecutionStatus.failed,
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
      fallback: parsedStatus == TaskStepExecutionStatus.failed
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
    return TaskTerminalToolCallResult(
      resultJson: jsonEncode({'finished': true, 'status': rawStatus}),
      finalContent: finalContent,
      output: TaskStepExecutionOutput(
        status: parsedStatus,
        runStatus: switch (parsedStatus) {
          TaskStepExecutionStatus.completed => TaskRunStatus.completed,
          TaskStepExecutionStatus.blocked => TaskRunStatus.blocked,
          TaskStepExecutionStatus.failed => TaskRunStatus.failed,
          TaskStepExecutionStatus.needsReplan => TaskRunStatus.needsReplan,
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

  Future<TaskAggregate> _replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required String baseSystemPrompt,
    TaskExecutionRequest executionRequest = const TaskExecutionRequest(),
    required String reason,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final projectContext = executionRequest.planningContext;
    final context = TaskPlanningToolContext(
      task: snapshot,
      workspaceRoot: workspace.rootPath,
      maxSteps: _taskPlanningStepLimit(snapshot),
      projectGoal: projectContext?.projectGoal ?? '',
      doneCriteria: projectContext?.doneCriteria.isNotEmpty == true
          ? projectContext!.doneCriteria
          : snapshot.doneCriteria.isNotEmpty
          ? snapshot.doneCriteria
          : snapshot.successCriteria,
      outOfScope: projectContext?.outOfScope.isNotEmpty == true
          ? projectContext!.outOfScope
          : snapshot.outOfScope,
      readPaths: projectContext?.readPaths.isNotEmpty == true
          ? projectContext!.readPaths
          : snapshot.readPaths,
      writePaths: projectContext?.writePaths.isNotEmpty == true
          ? projectContext!.writePaths
          : snapshot.writePaths,
      requiredArtifacts: projectContext?.expectedArtifacts.isNotEmpty == true
          ? projectContext!.expectedArtifacts
          : snapshot.expectedArtifacts,
      requiredGates: projectContext?.requiredGates.isNotEmpty == true
          ? projectContext!.requiredGates
          : snapshot.gates,
      requiredEvidence: projectContext?.expectedEvidence.isNotEmpty == true
          ? projectContext!.expectedEvidence
          : executionRequest.expectedEvidence,
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

Project context that remains authoritative:
${projectContext == null ? 'None supplied.' : _encoder.convert(snakeCaseWire(ModelJson.encode(projectContext)))}

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
}
