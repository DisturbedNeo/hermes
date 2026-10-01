part of 'task_execution_coordinator.dart';

typedef _TaskTerminalToolCall =
    _TaskTerminalToolCallResult Function({
      required String callName,
      required Object args,
      required Task task,
      required TaskStep step,
      required List<TaskToolCallRecord> existingToolCalls,
      required TaskExecutionRequest executionRequest,
    });

typedef _TaskStepOutputParser =
    _StepExecutionOutput Function(
      String raw,
      Task task,
      TaskStep step,
      List<TaskToolCallRecord> toolCalls,
      TaskExecutionRequest executionRequest,
    );

typedef _TaskStepPromptBuilder =
    String Function(
      Task task,
      TaskStep step,
      WorkspaceAttachment workspace,
      TaskExecutionRequest executionRequest,
    );

typedef _TaskStructuredToolResult =
    Map<String, dynamic>? Function(String toolName, String resultJson);

typedef _TaskToolErrorResolver =
    TaskToolError? Function(String toolName, Map<String, dynamic>? result);

typedef _TaskToolOutcomeResolver =
    TaskToolCallOutcome Function(
      Map<String, dynamic>? result,
      TaskToolError? error,
    );

typedef _TaskOperationKeyBuilder =
    String Function(String toolName, Object? rawArguments);

typedef _TaskTextCapper = String Function(String value, int maxChars);

class _TaskStepExecutionLoop {
  _TaskStepExecutionLoop({
    required ToolRegistryPort toolService,
    required TaskModelCompletionPort modelCompletion,
    required TaskToolExecutionPort toolExecution,
    required TaskExecutionPolicy executionPolicy,
    required JsonEncoder encoder,
    required _TaskTerminalToolCall terminalToolCall,
    required _TaskStepOutputParser parseStepOutput,
    required TaskPersistenceStore persistenceStore,
    required _TaskStepPromptBuilder buildStepPrompt,
    required _TaskStructuredToolResult structuredToolResult,
    required _TaskToolErrorResolver toolErrorInfoForCall,
    required _TaskToolOutcomeResolver toolCallOutcome,
    required _TaskOperationKeyBuilder operationKey,
    required _TaskTextCapper cap,
  }) : _toolService = toolService,
       _modelCompletion = modelCompletion,
       _toolExecution = toolExecution,
       _executionPolicy = executionPolicy,
       _encoder = encoder,
       _terminalToolCall = terminalToolCall,
       _parseStepOutputCallback = parseStepOutput,
       _persistenceStore = persistenceStore,
       _buildStepPromptCallback = buildStepPrompt,
       _structuredToolResultCallback = structuredToolResult,
       _toolErrorInfoForCallCallback = toolErrorInfoForCall,
       _toolCallOutcomeCallback = toolCallOutcome,
       _operationKeyCallback = operationKey,
       _capCallback = cap;

  final ToolRegistryPort _toolService;
  final TaskModelCompletionPort _modelCompletion;
  final TaskToolExecutionPort _toolExecution;
  final TaskExecutionPolicy _executionPolicy;
  final JsonEncoder _encoder;
  final _TaskTerminalToolCall _terminalToolCall;
  final _TaskStepOutputParser _parseStepOutputCallback;
  final TaskPersistenceStore _persistenceStore;
  final _TaskStepPromptBuilder _buildStepPromptCallback;
  final _TaskStructuredToolResult _structuredToolResultCallback;
  final _TaskToolErrorResolver _toolErrorInfoForCallCallback;
  final _TaskToolOutcomeResolver _toolCallOutcomeCallback;
  final _TaskOperationKeyBuilder _operationKeyCallback;
  final _TaskTextCapper _capCallback;

  Future<_StepExecutionOutput> execute({
    required ModelCompletionPort client,
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
  }) async {
    final allowedCommands = _executionPolicy.allowedCommands(task, step);
    final allowedToolIds = _executionPolicy.allowedToolIds(
      step,
      allowedCommands,
    );
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
        content: _buildStepPromptCallback(
          task,
          step,
          workspace,
          executionRequest,
        ),
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
        (call) => _executionPolicy.isTerminalTool(call.name),
      );
      if (terminalCallIndex >= 0) {
        final terminalCall = completion.toolCalls[terminalCallIndex];
        final callId = terminalCall.id ?? 'call_$terminalCallIndex';
        final args = TaskJson.decodeJsonOrString(terminalCall.arguments);
        final terminal = _terminalToolCall(
          callName: terminalCall.name,
          args: args,
          task: task,
          step: step,
          existingToolCalls: toolCalls,
          executionRequest: executionRequest,
        );
        final resultJson = terminal.resultJson;
        final result = _structuredToolResultCallback(
          terminalCall.name,
          resultJson,
        );
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: terminalCall.name,
            arguments: args,
            result: result,
            resultSummary: _capCallback(resultJson, 1200),
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
        emitTerminalToolResults(
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

      if (isStepResultJson(finalContent)) {
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
              const ChatMessageWireAdapter().toolCall(
                id: completion.toolCalls[i].id ?? 'call_$i',
                name: completion.toolCalls[i].name,
                argumentsJson: completion.toolCalls[i].arguments,
              ),
          ],
        ),
      );

      for (var i = 0; i < completion.toolCalls.length; i++) {
        cancellationToken?.throwIfCancelled();
        final call = completion.toolCalls[i];
        final callId = call.id ?? 'call_$i';
        final args = TaskJson.decodeJsonOrString(call.arguments);
        final toolKey = toolCallKey(call);
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

        final toolResult = await _toolExecution.execute(
          call: call,
          task: task,
          step: step,
          allowedToolIds: allowedToolIds,
          allowedCommands: allowedCommands,
          context: context,
          blockedReason: loopGuardReason,
        );
        cancellationToken?.throwIfCancelled();
        final resultJson = ToolProtocolAdapter.encodeResult(toolResult);
        final result = _structuredToolResultCallback(call.name, resultJson);
        final toolError = _toolErrorInfoForCallCallback(call.name, result);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: call.name,
            arguments: args,
            result: result,
            resultSummary: _capCallback(resultJson, 1200),
            outcome: _toolCallOutcomeCallback(result, toolError),
            operationKey: _operationKeyCallback(call.name, args),
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
        final finalizer = await finalizeStepAfterToolGuard(
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
        if (isStepResultJson(finalContent)) {
          forcedOutput = _parseStepOutputCallback(
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

    await _persistenceStore.persistence.saveLog(
      workspace.rootPath,
      task.id,
      '${step.id}-${run.runId}.md',
      finalText,
    );

    return forcedOutput ??
        _parseStepOutputCallback(
          finalContent.isEmpty ? finalText : finalContent,
          task,
          step,
          toolCalls,
          executionRequest,
        );
  }

  void emitTerminalToolResults({
    required ModelOutputSink? onModelOutput,
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

  Future<ModelCompletion> finalizeStepAfterToolGuard({
    required ModelCompletionPort client,
    required TaskStep step,
    required List<ChatMessage> messages,
    required String reason,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
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

  bool isStepResultJson(String value) {
    final json = TaskJson.tryParseObject(value);
    if (json == null) return false;
    final rawStatus = json['status']?.toString().trim().toLowerCase();
    return rawStatus == 'completed' ||
        rawStatus == 'blocked' ||
        rawStatus == 'needs_replan' ||
        rawStatus == 'failed';
  }

  String toolCallKey(ModelToolCall call) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    final args = decoded is String ? decoded.trim() : _encoder.convert(decoded);
    return '${call.name}:$args';
  }
}
