// ignore_for_file: dead_code, dead_code_on_catch_subtype, unused_element
part of 'task_controller.dart';

enum _StepExecutionStatus { completed, blocked, needsReplan, failed }

class _StepExecutionOutput {
  final _StepExecutionStatus status;
  final TaskRunStatus runStatus;
  final String summary;
  final String memoryUpdate;
  final List<TaskArtifact> artifacts;
  final List<TaskToolCallRecord> toolCalls;
  final List<TaskGateResult> gateResults;
  final List<TaskEvidenceClaim> evidenceClaims;
  final String? userQuestion;
  final AgentQuestion? agentQuestion;
  final String? replanRequest;
  final String? error;

  const _StepExecutionOutput({
    required this.status,
    required this.runStatus,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
    required this.toolCalls,
    this.gateResults = const [],
    this.evidenceClaims = const [],
    this.userQuestion,
    this.agentQuestion,
    this.replanRequest,
    this.error,
  });

  _StepExecutionOutput copyWith({
    _StepExecutionStatus? status,
    TaskRunStatus? runStatus,
    String? summary,
    String? memoryUpdate,
    List<TaskArtifact>? artifacts,
    List<TaskToolCallRecord>? toolCalls,
    List<TaskGateResult>? gateResults,
    List<TaskEvidenceClaim>? evidenceClaims,
    Object? userQuestion = kSentinel,
    Object? agentQuestion = kSentinel,
    Object? replanRequest = kSentinel,
    Object? error = kSentinel,
  }) {
    return _StepExecutionOutput(
      status: status ?? this.status,
      runStatus: runStatus ?? this.runStatus,
      summary: summary ?? this.summary,
      memoryUpdate: memoryUpdate ?? this.memoryUpdate,
      artifacts: artifacts ?? this.artifacts,
      toolCalls: toolCalls ?? this.toolCalls,
      gateResults: gateResults ?? this.gateResults,
      evidenceClaims: evidenceClaims ?? this.evidenceClaims,
      userQuestion: resolve(userQuestion, this.userQuestion),
      agentQuestion: resolve(agentQuestion, this.agentQuestion),
      replanRequest: resolve(replanRequest, this.replanRequest),
      error: resolve(error, this.error),
    );
  }
}

class _TaskTerminalToolCallResult {
  final String resultJson;
  final String finalContent;
  final _StepExecutionOutput output;
  final String? error;

  const _TaskTerminalToolCallResult({
    required this.resultJson,
    required this.finalContent,
    required this.output,
    this.error,
  });
}

const String _refinerSystemInstruction = '''
You refine user requests for a long-horizon AI task runner.
Do not perform the task.
Prefer useful assumptions over broad questioning.
Ask at most three questions.
Return only valid JSON.
''';

const String _executorSystemInstruction = '''
You execute one step of a larger linear task.
Use the full plan and memory to keep long-horizon context.
Complete only the current step.
Do not perform future steps early.
Use tools only when needed. When you have enough information, stop using tools and return the requested JSON.
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Use task_request_user_decision for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
You may read artifacts from completed prior steps and any artifact already created during the current step.
Write and report only artifacts declared on the current step.
If the current step needs a different artifact path, call task_request_replan instead of writing it.
If the current step is read-only, you may create only the current step's declared task-owned artifact files under `.agent/tasks/<taskId>/`, and you may run only whitelisted verification terminal commands exposed for the step. Invoke each whitelisted command with the exact command text and working directory shown in the step permissions. Do not add or remove arguments, flags, pipes, redirects, shell wrappers, or combined commands; any variation will be rejected and will not satisfy its command_passes gate. Attempt advisory verification commands when terminal execution is approved; their results are evidence even when they fail. You must not overwrite existing files, edit source files, rename paths, delete paths, or try to use other terminal commands as a workaround.
If a later step is responsible for writing a report or changing files, leave that work for the later step.
If the current plan is wrong or missing necessary follow-up work, call task_request_replan with a concrete reason.
If confirmed workspace evidence contradicts the refined project goal, active milestone, declared task paths, or planner memory, stop bounded diagnostic work and call task_request_replan with the concrete contradiction and affected plan element.
If user input is truly required, call task_request_user_decision with the question and context.
When done, call finish_task_step with only status and summary. Hermes derives artifact provenance from successful workspace calls, evaluates completion gates, and treats model-written evidence claims as advisory.
If finish_task_step is unavailable, return only the requested JSON object.
''';

const String _taskPlanningToolsSystemInstruction = '''
You create a compact linear task plan through explicit task planning tools.
Do not return a complete task JSON document. Start with task_view when context
is needed, optionally use task_set_brief, add one independently executable
step at a time with task_add_step, attach exact verification commands with
task_add_check, and finish with task_commit_plan. If a validation error means
the current uncommitted draft must be replaced, use task_reset_plan first and
then rebuild the corrected draft with commands.

Hermes generates step, artifact, gate, evidence, question, and runtime IDs.
Never provide persistent IDs, statuses, timestamps, run history, fingerprints,
or completion fields. A tool error affects only that command; inspect the
returned error and retry the smallest correction.

Stay inside the task objective, done criteria, out-of-scope boundaries, and
declared read/write paths. Do not expand a bounded Project task to the whole
Project. Keep the number of steps within the supplied limit. Use
task_request_user_decision only for genuinely blocking irreversible choices,
credentials, scope conflicts, or high-cost ambiguity with no safe default.
Use task_request_replan when the current unfinished approach is demonstrably
wrong, and include a concrete reason. A successful task_commit_plan is the
only completion signal.
''';

extension _TaskExecutionOperations on _TaskApplicationContext {
  Future<Task> _runNextStepCore({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
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
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    TaskModelOutputSink? onModelOutput,
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
    return WorkspaceMetadata(
      workspaceName: workspace.displayName,
      rootFiles: profile.rootEntries,
      gitAvailable:
          await FileSystemEntity.type(
            path.join(workspace.rootPath, '.git'),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound,
      commandExecutionApproved: workspace.commandExecutionApproved,
      existingTaskIds: (await repository.listTasks(
        workspace.rootPath,
        chatSessionId: chatSessionId,
      )).map((task) => task.id).toList(),
      workspaceProfile: profile,
    );
  }

  Future<_StepExecutionOutput> _executeStep({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task task,
    required TaskStep step,
    required TaskRun run,
    required String baseSystemPrompt,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    required TaskExecutionRequest executionRequest,
  }) async {
    final allowedCommands = _allowedCommandsForStep(task, step);
    final allowedToolIds = _allowedToolIdsForStep(step, allowedCommands);
    final toolDefs = [
      ..._toolService.getToolDefinitions(
        ids: allowedToolIds.toList(),
        includeWorkspaceTools: true,
      ),
      _finishTaskStepToolDefinition,
      _requestTaskUserDecisionToolDefinition,
      _requestTaskReplanToolDefinition,
    ];
    final messages = <ChatMessage>[
      ChatMessage(
        role: 'system',
        content: '$baseSystemPrompt\n\n$_executorSystemInstruction',
      ),
      ChatMessage(
        role: 'user',
        content: _buildStepPrompt(task, step, workspace, executionRequest),
      ),
    ];
    final context = WorkspaceToolContext(
      workspace: workspace,
      cancellationToken: cancellationToken,
    );
    final toolCalls = <TaskToolCallRecord>[];
    var finalText = '';
    var finalContent = '';
    _StepExecutionOutput? forcedOutput;
    String? previousToolKey;
    var consecutiveRepeatCount = 0;

    while (true) {
      cancellationToken?.throwIfCancelled();
      final completion = await _modelCompletion.completeChat(
        client: client,
        label: 'Step Executor: ${step.title}',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        messages: messages,
        extraParams: ToolCaller.buildExtraParams(
          addGenerationPrompt: true,
          toolDefs: toolDefs,
        ),
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
      );

      cancellationToken?.throwIfCancelled();
      finalContent = completion.content.trim();
      finalText = [
        if (completion.reasoning.trim().isNotEmpty)
          'Reasoning summary:\n${completion.reasoning.trim()}',
        if (finalContent.isNotEmpty) finalContent,
      ].join('\n\n').trim();

      if (completion.toolCalls.isEmpty) break;

      final terminalCallIndex = completion.toolCalls.indexWhere(
        (call) => _isTaskTerminalTool(call.name),
      );
      if (terminalCallIndex >= 0) {
        final terminalCall = completion.toolCalls[terminalCallIndex];
        final callId = terminalCall.id ?? 'call_$terminalCallIndex';
        final args = TaskJson.decodeJsonOrString(terminalCall.arguments);
        final terminal = _terminalTaskToolCall(
          callName: terminalCall.name,
          args: args,
          task: task,
          step: step,
          existingToolCalls: toolCalls,
          executionRequest: executionRequest,
        );
        final resultJson = terminal.resultJson;
        final result = _structuredToolResult(terminalCall.name, resultJson);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: terminalCall.name,
            arguments: args,
            result: result,
            resultSummary: _cap(resultJson, 1200),
            outcome: terminal.error == null
                ? TaskToolCallOutcome.succeeded
                : TaskToolCallOutcome.failed,
            operationKey: terminalCall.name,
            toolError: terminal.error == null
                ? null
                : TaskToolError(
                    code: 'invalid_task_control_arguments',
                    message: terminal.error!,
                    disposition: TaskToolErrorDisposition.advisory,
                  ),
            timestamp: DateTime.now(),
          ),
        );
        _emitTerminalToolResults(
          onModelOutput: onModelOutput,
          label: 'Step Executor: ${step.title}',
          calls: completion.toolCalls,
          terminalCallIndex: terminalCallIndex,
          terminalResultJson: resultJson,
        );
        finalContent = terminal.finalContent;
        finalText = [
          if (completion.reasoning.trim().isNotEmpty)
            'Reasoning summary:\n${completion.reasoning.trim()}',
          if (finalContent.isNotEmpty) finalContent,
        ].join('\n\n').trim();
        forcedOutput = terminal.output.copyWith(toolCalls: toolCalls);
        break;
      }

      if (_isStepResultJson(finalContent)) {
        for (var i = 0; i < completion.toolCalls.length; i++) {
          _modelCompletion.emitOutput(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.toolResult,
              label: 'Step Executor: ${step.title}',
              text: jsonEncode({
                'skipped': true,
                'reason':
                    'The step already returned final JSON, so this extra tool call was ignored.',
              }),
              toolIndex: i,
            ),
          );
        }
        break;
      }

      String? loopGuardReason;

      messages.add(
        ChatMessage(
          role: 'assistant',
          content: completion.content,
          reasoningContent: completion.reasoning,
          toolCalls: [
            for (var i = 0; i < completion.toolCalls.length; i++)
              {
                'id': completion.toolCalls[i].id ?? 'call_$i',
                'type': 'function',
                'function': {
                  'name': completion.toolCalls[i].name,
                  'arguments': TaskJson.decodeJsonOrString(
                    completion.toolCalls[i].arguments,
                  ),
                },
              },
          ],
        ),
      );

      for (var i = 0; i < completion.toolCalls.length; i++) {
        cancellationToken?.throwIfCancelled();
        final call = completion.toolCalls[i];
        final callId = call.id ?? 'call_$i';
        final args = TaskJson.decodeJsonOrString(call.arguments);
        final toolKey = _toolCallKey(call);
        if (toolKey == previousToolKey) {
          consecutiveRepeatCount++;
        } else {
          previousToolKey = toolKey;
          consecutiveRepeatCount = 1;
        }

        if (loopGuardReason == null &&
            consecutiveRepeatCount >= _maxConsecutiveRepeatedToolCalls) {
          loopGuardReason =
              'The step repeated the same tool call $consecutiveRepeatCount times: ${call.name}.';
        }

        final resultJson = await _toolExecution.execute(
          call: call,
          task: task,
          step: step,
          allowedToolIds: allowedToolIds,
          allowedCommands: allowedCommands,
          context: context,
          blockedReason: loopGuardReason,
        );
        cancellationToken?.throwIfCancelled();
        final result = _structuredToolResult(call.name, resultJson);
        final toolError = _toolErrorInfoForCall(call.name, result);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: call.name,
            arguments: args,
            result: result,
            resultSummary: _cap(resultJson, 1200),
            outcome: _toolCallOutcome(result, toolError),
            operationKey: _operationKey(call.name, args),
            toolError: toolError,
            timestamp: DateTime.now(),
          ),
        );
        _modelCompletion.emitOutput(
          onModelOutput,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolResult,
            label: 'Step Executor: ${step.title}',
            text: resultJson,
            toolIndex: i,
          ),
        );
        messages.add(
          ChatMessage(role: 'tool', content: resultJson, toolCallId: callId),
        );

        if (loopGuardReason != null) break;
      }

      if (loopGuardReason != null) {
        final finalizer = await _finalizeStepAfterToolGuard(
          client: client,
          step: step,
          messages: messages,
          reason: loopGuardReason,
          compactionSettings: compactionSettings,
          contextLimitTokens: contextLimitTokens,
          onCompactionStatus: onCompactionStatus,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        finalContent = finalizer.content.trim();
        finalText = [
          if (finalizer.reasoning.trim().isNotEmpty)
            'Reasoning summary:\n${finalizer.reasoning.trim()}',
          if (finalContent.isNotEmpty) finalContent,
        ].join('\n\n').trim();
        if (_isStepResultJson(finalContent)) {
          forcedOutput = _parseStepOutput(
            finalContent,
            task,
            step,
            toolCalls,
            executionRequest,
          );
        } else {
          forcedOutput = _StepExecutionOutput(
            status: _StepExecutionStatus.failed,
            runStatus: TaskRunStatus.failed,
            summary:
                'Stopped step after a tool-call loop guard fired. $loopGuardReason',
            memoryUpdate: '',
            artifacts: const [],
            toolCalls: toolCalls,
            error: loopGuardReason,
          );
        }
        break;
      }
    }

    await repository.saveLog(
      workspace.rootPath,
      task.id,
      '${step.id}-${run.runId}.md',
      finalText,
    );

    return forcedOutput ??
        _parseStepOutput(
          finalContent.isEmpty ? finalText : finalContent,
          task,
          step,
          toolCalls,
          executionRequest,
        );
  }

  Future<_StepExecutionOutput> _applyCompletionGates({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task task,
    required TaskStep step,
    required _StepExecutionOutput execution,
    required String baseSystemPrompt,
    CancellationToken? cancellationToken,
  }) async {
    final gates = _completionGates(task, step);
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

  List<TaskGate> _completionGates(Task task, TaskStep step) {
    final hasRemainingSteps = task.steps.any((candidate) {
      if (candidate.id == step.id) return false;
      return candidate.status == TaskStepStatus.pending ||
          candidate.status == TaskStepStatus.approved ||
          candidate.status == TaskStepStatus.blocked ||
          candidate.status == TaskStepStatus.failed;
    });
    return [...step.gates, if (!hasRemainingSteps) ...task.gates];
  }

  Set<String> _allowedToolIdsForStep(
    TaskStep step,
    List<TaskAllowedCommand> allowedCommands,
  ) {
    if (!step.mayEditFiles) {
      return {
        ..._readOnlyTaskToolIds,
        if (allowedCommands.isNotEmpty) 'run_command',
      };
    }
    return {..._readOnlyTaskToolIds, ..._mutatingTaskToolIds};
  }

  List<TaskAllowedCommand> _allowedCommandsForStep(Task task, TaskStep step) {
    final seen = <String>{};
    final commands = <TaskAllowedCommand>[];
    for (final gate in _completionGates(task, step)) {
      if (gate.id != 'command_passes') continue;
      final command = _commandTextFromParts(
        jsonString(gate.params['command']),
        jsonStringList(gate.params['args']),
      );
      if (command.isEmpty) continue;
      final workingDirectory = path.normalize(
        jsonString(
          gate.params['working_directory'] ?? gate.params['workingDirectory'],
          fallback: '.',
        ),
      );
      final key = '$workingDirectory\x00$command';
      if (!seen.add(key)) continue;
      commands.add(
        TaskAllowedCommand(
          command: command,
          workingDirectory: workingDirectory,
        ),
      );
    }
    return commands;
  }

  String _commandTextFromParts(String command, List<String> args) {
    return TerminalCommandParser.commandTextFromParts(command, args);
  }

  bool _isTaskTerminalTool(String name) {
    return name == _finishTaskStepToolId ||
        name == _requestTaskUserDecisionToolId ||
        name == _requestTaskReplanToolId;
  }

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
    final question = AgentQuestion.parse(args);
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

  void _emitTerminalToolResults({
    required TaskModelOutputSink? onModelOutput,
    required String label,
    required List<ModelToolCall> calls,
    required int terminalCallIndex,
    required String terminalResultJson,
  }) {
    for (var i = 0; i < calls.length; i++) {
      _modelCompletion.emitOutput(
        onModelOutput,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolResult,
          label: label,
          text: i == terminalCallIndex
              ? terminalResultJson
              : jsonEncode({
                  'skipped': true,
                  'reason':
                      'The task control tool ended the step, so this tool call was ignored.',
                }),
          toolIndex: i,
        ),
      );
    }
  }

  Future<ModelCompletion> _finalizeStepAfterToolGuard({
    required ModelProvider client,
    required TaskStep step,
    required List<ChatMessage> messages,
    required String reason,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) {
    return _modelCompletion.completeChat(
      client: client,
      label: 'Step Finalizer: ${step.title}',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      messages: [
        ...messages,
        ChatMessage(
          role: 'user',
          content:
              '''
The task runner has stopped tool use for this step.

Reason:
$reason

Do not call any more tools. Based only on the work already completed and the tool results already provided, return the final step result as only this JSON object:
{
  "status": "completed|failed",
  "summary": "what happened in this step"
}
Do not include artifacts or evidence claims. Hermes records workspace
provenance and evaluates gates separately.
''',
        ),
      ],
      extraParams: ToolCaller.buildExtraParams(
        addGenerationPrompt: true,
        toolDefs: const [],
      ),
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
    );
  }

  bool _isStepResultJson(String value) {
    final json = TaskJson.tryParseObject(value);
    if (json == null) return false;
    final rawStatus = json['status']?.toString().trim().toLowerCase();
    return rawStatus == 'completed' ||
        rawStatus == 'blocked' ||
        rawStatus == 'needs_replan' ||
        rawStatus == 'failed';
  }

  String _toolCallKey(ModelToolCall call) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    final args = decoded is String ? decoded.trim() : _encoder.convert(decoded);
    return '${call.name}:$args';
  }

  Future<Task> _replanUnfinished({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    required String reason,
    TaskModelOutputSink? onModelOutput,
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
}
