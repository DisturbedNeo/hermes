import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/compaction_manager.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_storage_service.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

typedef TaskCancelRegistration = void Function();
typedef TaskCancelCallback = FutureOr<void> Function();
typedef TaskCompactionStatusSink = void Function(String status);

class TaskCancellationToken {
  final List<TaskCancelCallback> _callbacks = [];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void throwIfCancelled() {
    if (_isCancelled) throw const TaskCancelledException();
  }

  TaskCancelRegistration onCancel(TaskCancelCallback callback) {
    if (_isCancelled) {
      Future.microtask(callback);
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  Future<void> cancel() async {
    if (_isCancelled) return;
    _isCancelled = true;
    final callbacks = List<TaskCancelCallback>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      await callback();
    }
  }
}

class TaskCancelledException implements Exception {
  const TaskCancelledException();

  @override
  String toString() => 'Task execution cancelled';
}

class _StreamingTaskToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class _PendingTaskToolResult {
  const _PendingTaskToolResult({
    required this.messageIndex,
    required this.toolIndex,
  });

  final int messageIndex;
  final int toolIndex;
}

const int _maxConsecutiveRepeatedToolCalls = 3;

const Set<String> _readOnlyTaskToolIds = {
  'calculator',
  'list_directory',
  'read_file',
  'search_files',
  'write_file',
};

const Set<String> _mutatingTaskToolIds = {
  'write_file',
  'patch_file',
  'create_directory',
  'rename_path',
  'delete_path',
  'run_command',
};

const String _finishTaskStepToolId = 'finish_task_step';

const ToolDefinition _finishTaskStepToolDefinition = ToolDefinition(
  id: _finishTaskStepToolId,
  name: 'Finish task step',
  description:
      'Finish the current task step. Use this when the current step is done, blocked, needs replanning, or has failed. Calling this ends the step; do not call workspace tools after it.',
  schema: {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['completed', 'blocked', 'needs_replan', 'failed'],
        'description': 'Final status for the current step.',
      },
      'summary': {
        'type': 'string',
        'description': 'Concise summary of what happened in this step.',
      },
      'memoryUpdate': {
        'type': 'string',
        'description':
            'Useful context from this step that later task steps should remember.',
      },
      'artifacts': {
        'type': 'array',
        'description':
            'Current-step artifacts that were actually created. Only include declared artifact paths.',
        'items': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Workspace-relative artifact path.',
            },
            'description': {
              'type': 'string',
              'description': 'Short artifact description.',
            },
          },
          'required': ['path'],
        },
      },
      'userQuestion': {
        'type': 'string',
        'description': 'Question to ask the user when status is blocked.',
      },
      'replanRequest': {
        'type': 'string',
        'description': 'Concrete replan request when status is needs_replan.',
      },
      'error': {
        'type': 'string',
        'description': 'Failure details when status is failed.',
      },
    },
    'required': ['status', 'summary'],
  },
);

class TaskService {
  TaskService({
    required ToolService toolService,
    TaskStorageService? storage,
    WorkspaceSandbox? sandbox,
  }) : _toolService = toolService,
       _storage = storage ?? TaskStorageService(),
       _sandbox = sandbox ?? WorkspaceSandbox();

  final ToolService _toolService;
  final TaskStorageService _storage;
  final WorkspaceSandbox _sandbox;
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  TaskStorageService get storage => _storage;

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.listTasks(workspace.rootPath, chatSessionId: chatSessionId);
  }

  Future<TaskDocument?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.loadLatestTask(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<TaskDocument?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
  }) {
    return _storage.loadTask(
      workspace.rootPath,
      taskId,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _storage.deleteTasksForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _storage.deleteOrphanedChatTasks(
      workspace.rootPath,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<TaskDocument> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      chatSessionId: chatSessionId,
      updatedAt: DateTime.now(),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskDocument> recoverTask({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
  }) async {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final now = DateTime.now();
    final steps = snapshot.steps.map((step) {
      if (step.status == TaskStepStatus.running) {
        return step.copyWith(status: TaskStepStatus.blocked);
      }
      return step;
    }).toList();
    final recovered = snapshot.copyWith(
      status: TaskStatus.blocked,
      steps: steps,
      updatedAt: now,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        'Recovered an interrupted task. Review the current step before continuing.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, recovered);
    return recovered;
  }

  String encodeTask(TaskDocument task) =>
      '${_encoder.convert(task.toJson())}\n';

  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
  }) async {
    final resolved = await _sandbox.resolve(workspace.rootPath, artifactPath);
    final file = File(resolved.absolutePath);
    if (!await file.exists()) {
      throw StateError('Artifact not found: $artifactPath');
    }
    return _cap(await file.readAsString(), 240000);
  }

  Future<RefinedTaskBrief> refineTaskBrief({
    required ChatClient client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    final metadata = workspace == null || workspace.missing
        ? const _WorkspaceMetadata()
        : await _collectWorkspaceMetadata(workspace);

    try {
      final json = await _completeJson(
        client: client,
        system: _refinerSystemInstruction,
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
${_encoder.convert(metadata.toJson())}

Request:
$userPrompt
''',
      );
      return _normaliseBrief(RefinedTaskBrief.fromJson(json), userPrompt);
    } on TaskCancelledException {
      rethrow;
    } catch (_) {
      return _fallbackBrief(userPrompt);
    }
  }

  Future<TaskDocument> createTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final taskId = _newTaskId(userPrompt);
    final metadata = await _collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );

    TaskDocument task;
    try {
      final json = await _completeJson(
        client: client,
        system: '$baseSystemPrompt\n\n$_plannerSystemInstruction',
        label: 'Task Planner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Create a linear multi-step task plan.

Return only JSON:
{
  "title": "...",
  "goal": "...",
  "constraints": ["..."],
  "successCriteria": ["..."],
  "steps": [
    {
      "id": "short_stable_id",
      "title": "...",
      "objective": "...",
      "instructions": ["..."],
      "mayEditFiles": false,
      "artifacts": [{"path": ".agent/tasks/$taskId/output.md", "description": "..."}]
    }
  ]
}

Use this exact task id when referencing task-owned artifacts: $taskId
Create only as many steps as are necessary to accomplish the task.
Artifacts are optional.

Workspace metadata:
${_encoder.convert(metadata.toJson())}

Request:
$userPrompt
''',
      );
      task = _taskFromPlannerJson(
        json,
        taskId: taskId,
        originalPrompt: userPrompt,
        chatSessionId: chatSessionId,
        now: now,
      );
    } on TaskCancelledException {
      rethrow;
    } catch (_) {
      task = _fallbackTask(
        taskId: taskId,
        userPrompt: userPrompt,
        chatSessionId: chatSessionId,
        now: now,
      );
    }

    await _storage.saveSnapshot(workspace.rootPath, task);
    return task;
  }

  Future<TaskDocument> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String rawJson,
  }) async {
    final parsed = TaskDocument.fromJson(TaskJson.parseObject(rawJson));
    final now = DateTime.now();
    final normalised = _normaliseEditedTask(
      parsed.copyWith(id: snapshot.id, chatSessionId: snapshot.chatSessionId),
      snapshot,
      now,
    );
    await _storage.saveSnapshot(workspace.rootPath, normalised);
    return normalised;
  }

  Future<TaskDocument> runNextStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    var working = await recoverTask(workspace: workspace, snapshot: snapshot);
    if (working.isTerminal) return working;
    final step = working.nextRunnableStep;
    if (step == null) {
      final completed = _markCompleted(working);
      await _storage.saveSnapshot(workspace.rootPath, completed);
      return completed;
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
      await _storage.saveSnapshot(workspace.rootPath, blocked);
      return blocked;
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
    await _storage.saveSnapshot(workspace.rootPath, working);

    try {
      final execution = await _executeStep(
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
      );

      final finishedAt = DateTime.now();
      final completedRun = run.copyWith(
        status: execution.runStatus,
        completedAt: finishedAt,
        summary: execution.summary,
        memoryUpdate: execution.memoryUpdate,
        toolCalls: execution.toolCalls,
        artifacts: execution.artifacts,
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

      await _storage.saveSnapshot(workspace.rootPath, working);
      return working;
    } on TaskCancelledException catch (e) {
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
      await _storage.saveSnapshot(workspace.rootPath, working);
      return working;
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
      await _storage.saveSnapshot(workspace.rootPath, working);
      return working;
    }
  }

  Future<TaskDocument> approvePendingStep({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
  }) async {
    final approval = snapshot.pendingApproval;
    if (approval == null) return snapshot;
    final step = snapshot.stepById(approval.stepId);
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: TaskStepStatus.approved),
        ).copyWith(
          status: TaskStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          updatedAt: DateTime.now(),
        );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskDocument> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: TaskStepStatus.pending),
        ).copyWith(
          status: TaskStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          pendingQuestion: null,
          updatedAt: DateTime.now(),
        );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskDocument> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final now = DateTime.now();
    final updatedStep = step.copyWith(status: TaskStepStatus.skipped);
    var updated = _replaceStep(snapshot, step.id, updatedStep);
    updated = _advanceAfterStep(updated, now).copyWith(
      runs: [
        ...updated.runs,
        TaskRun(
          runId: 'run_${uuid.v7()}',
          stepId: step.id,
          status: TaskRunStatus.skipped,
          summary: 'Step skipped by the user.',
          memoryUpdate: '',
          toolCalls: const [],
          artifacts: const [],
          startedAt: now,
          completedAt: now,
        ),
      ],
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskDocument> stopTask({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      status: TaskStatus.cancelled,
      currentStepId: null,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: now,
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String answer,
  }) async {
    final question = snapshot.pendingQuestion;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final step = snapshot.stepById(question.stepId);
    final updated =
        _replaceStep(
          snapshot,
          question.stepId,
          (step ?? snapshot.nextRunnableStep)?.copyWith(
                status: TaskStepStatus.pending,
              ) ??
              TaskStep(
                id: question.stepId,
                title: question.stepId,
                objective: '',
                instructions: const [],
                mayEditFiles: false,
                artifacts: const [],
                status: TaskStepStatus.pending,
              ),
        ).copyWith(
          status: TaskStatus.paused,
          pendingQuestion: null,
          memorySummary: _appendMemory(
            snapshot.memorySummary,
            'User answered: ${question.question}\nAnswer: $trimmed',
          ),
          updatedAt: DateTime.now(),
        );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskDocument> replanUnfinished({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
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
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<_WorkspaceMetadata> _collectWorkspaceMetadata(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final root = Directory(workspace.rootPath);
    final rootFiles = <String>[];
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        rootFiles.add(path.basename(entity.path));
        if (rootFiles.length >= 80) break;
      }
    }
    rootFiles.sort();
    return _WorkspaceMetadata(
      workspaceName: workspace.displayName,
      rootFiles: rootFiles,
      gitAvailable: rootFiles.contains('.git'),
      existingTaskIds: (await _storage.listTasks(
        workspace.rootPath,
        chatSessionId: chatSessionId,
      )).map((task) => task.id).toList(),
    );
  }

  Future<_StepExecutionOutput> _executeStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required TaskDocument task,
    required TaskStep step,
    required TaskRun run,
    required String baseSystemPrompt,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    final allowedToolIds = _allowedToolIdsForStep(step);
    final toolDefs = [
      ..._toolService.getToolDefinitions(
        ids: allowedToolIds.toList(),
        includeWorkspaceTools: true,
      ),
      _finishTaskStepToolDefinition,
    ];
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: baseSystemPrompt),
      const ChatMessage(role: 'system', content: _executorSystemInstruction),
      ChatMessage(role: 'user', content: _buildStepPrompt(task, step)),
    ];
    final context = WorkspaceToolContext(workspace: workspace);
    final toolCalls = <TaskToolCallRecord>[];
    var finalText = '';
    var finalContent = '';
    _StepExecutionOutput? forcedOutput;
    String? previousToolKey;
    var consecutiveRepeatCount = 0;

    while (true) {
      cancellationToken?.throwIfCancelled();
      final completion = await _completeChatForTask(
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

      final finishCallIndex = completion.toolCalls.indexWhere(
        (call) => call.name == _finishTaskStepToolId,
      );
      if (finishCallIndex >= 0) {
        final finishCall = completion.toolCalls[finishCallIndex];
        final callId = finishCall.id ?? 'call_$finishCallIndex';
        final args = TaskJson.decodeJsonOrString(finishCall.arguments);
        final finish = _finishStepFromToolCall(
          args: args,
          task: task,
          step: step,
          existingToolCalls: toolCalls,
        );
        final resultJson = finish.resultJson;
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: finishCall.name,
            arguments: args,
            resultSummary: _cap(resultJson, 1200),
            error: finish.error,
            timestamp: DateTime.now(),
          ),
        );
        _emitFinishToolResults(
          onModelOutput: onModelOutput,
          label: 'Step Executor: ${step.title}',
          calls: completion.toolCalls,
          finishCallIndex: finishCallIndex,
          finishResultJson: resultJson,
        );
        finalContent = finish.finalContent;
        finalText = [
          if (completion.reasoning.trim().isNotEmpty)
            'Reasoning summary:\n${completion.reasoning.trim()}',
          if (finalContent.isNotEmpty) finalContent,
        ].join('\n\n').trim();
        forcedOutput = finish.output.copyWith(toolCalls: toolCalls);
        break;
      }

      if (_isStepResultJson(finalContent)) {
        for (var i = 0; i < completion.toolCalls.length; i++) {
          _emitTaskModelOutput(
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

        final resultJson = await _executeTaskToolCall(
          call: call,
          task: task,
          step: step,
          allowedToolIds: allowedToolIds,
          context: context,
          blockedReason: loopGuardReason,
        );
        cancellationToken?.throwIfCancelled();
        final error = _toolError(resultJson);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: call.name,
            arguments: args,
            resultSummary: _cap(resultJson, 1200),
            error: error,
            timestamp: DateTime.now(),
          ),
        );
        _emitTaskModelOutput(
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
          forcedOutput = _parseStepOutput(finalContent, task, step, toolCalls);
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

    await _storage.saveLog(
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
        );
  }

  Set<String> _allowedToolIdsForStep(TaskStep step) {
    if (!step.mayEditFiles) return _readOnlyTaskToolIds;
    return {..._readOnlyTaskToolIds, ..._mutatingTaskToolIds};
  }

  _FinishToolCallResult _finishStepFromToolCall({
    required Object args,
    required TaskDocument task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    if (args is! Map) {
      const error = 'finish_task_step arguments must be a JSON object.';
      final resultJson = jsonEncode({'error': error});
      return _FinishToolCallResult(
        resultJson: resultJson,
        finalContent: resultJson,
        error: error,
        output: _StepExecutionOutput(
          status: _StepExecutionStatus.failed,
          runStatus: TaskRunStatus.failed,
          summary: error,
          memoryUpdate: '',
          artifacts: const [],
          toolCalls: existingToolCalls,
          error: error,
        ),
      );
    }

    final json = Map<String, dynamic>.from(args);
    final finalContent = _encoder.convert(json);
    final status = jsonString(json['status'], fallback: 'completed');
    return _FinishToolCallResult(
      resultJson: jsonEncode({'finished': true, 'status': status}),
      finalContent: finalContent,
      output: _parseStepOutput(finalContent, task, step, existingToolCalls),
    );
  }

  void _emitFinishToolResults({
    required TaskModelOutputSink? onModelOutput,
    required String label,
    required List<ChatCompletionToolCall> calls,
    required int finishCallIndex,
    required String finishResultJson,
  }) {
    for (var i = 0; i < calls.length; i++) {
      _emitTaskModelOutput(
        onModelOutput,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolResult,
          label: label,
          text: i == finishCallIndex
              ? finishResultJson
              : jsonEncode({
                  'skipped': true,
                  'reason':
                      'finish_task_step ended the step, so this tool call was ignored.',
                }),
          toolIndex: i,
        ),
      );
    }
  }

  Future<String> _executeTaskToolCall({
    required ChatCompletionToolCall call,
    required TaskDocument task,
    required TaskStep step,
    required Set<String> allowedToolIds,
    required WorkspaceToolContext context,
    required String? blockedReason,
  }) async {
    if (blockedReason != null) {
      return jsonEncode({
        'error': 'Tool call skipped by task runner.',
        'reason': blockedReason,
      });
    }

    if (!allowedToolIds.contains(call.name)) {
      return jsonEncode({
        'error': 'Tool is not available for this task step.',
        'tool': call.name,
        'mayEditFiles': step.mayEditFiles,
        'availableTools': allowedToolIds.toList()..sort(),
        'reason': step.mayEditFiles
            ? 'The tool was not exposed to the task runner.'
            : 'This read-only step can read files and create new task-owned artifact files, but cannot edit source files, overwrite files, run terminal commands, rename paths, or delete paths.',
      });
    }

    if (!step.mayEditFiles && call.name == 'write_file') {
      return _executeReadOnlyArtifactWrite(
        call: call,
        task: task,
        step: step,
        context: context,
      );
    }
    if (step.mayEditFiles && call.name == 'write_file') {
      final artifactWriteError = await _taskArtifactWriteError(
        call: call,
        task: task,
        step: step,
        context: context,
      );
      if (artifactWriteError != null) return artifactWriteError;
    }

    return _toolService.execute(
      toolId: call.name,
      argumentsJson: call.arguments,
      context: context,
    );
  }

  Future<String> _executeReadOnlyArtifactWrite({
    required ChatCompletionToolCall call,
    required TaskDocument task,
    required TaskStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = TaskJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) {
        return jsonEncode({
          'error': 'write_file arguments must be a JSON object.',
        });
      }

      final rawPath = decoded['path'];
      final content = decoded['content'];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        return jsonEncode({'error': 'write_file requires a path.'});
      }
      if (content is! String) {
        return jsonEncode({'error': 'write_file requires string content.'});
      }

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      if (!_isInsideTaskDirectory(resolved.relativePath, task.id)) {
        return jsonEncode({
          'error': 'Read-only steps may only create task-owned artifact files.',
          'path': resolved.relativePath,
          'allowedPrefix': path.join('.agent', 'tasks', task.id),
        });
      }
      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (!allowedPaths.contains(path.normalize(resolved.relativePath))) {
        return jsonEncode({
          'error':
              'Read-only steps may only create artifacts declared on the current step.',
          'path': resolved.relativePath,
          'allowedArtifactPaths': allowedPaths.toList()..sort(),
        });
      }

      final existingType = await FileSystemEntity.type(resolved.absolutePath);
      if (existingType != FileSystemEntityType.notFound) {
        return jsonEncode({
          'error': 'Read-only steps cannot overwrite existing files.',
          'path': resolved.relativePath,
        });
      }

      final result = await _sandbox.writeFile(
        context.workspace.rootPath,
        resolved.relativePath,
        content,
      );
      return jsonEncode(result);
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  Future<String?> _taskArtifactWriteError({
    required ChatCompletionToolCall call,
    required TaskDocument task,
    required TaskStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = TaskJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) return null;
      final rawPath = decoded['path'];
      if (rawPath is! String || rawPath.trim().isEmpty) return null;

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      final artifactPath = path.normalize(resolved.relativePath);
      if (!_isInsideTaskDirectory(artifactPath, task.id)) return null;

      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (allowedPaths.contains(artifactPath)) return null;

      return jsonEncode({
        'error':
            'Task steps may only create artifacts declared on the current step.',
        'path': resolved.relativePath,
        'allowedArtifactPaths': allowedPaths.toList()..sort(),
      });
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  bool _isInsideTaskDirectory(String relativePath, String taskId) {
    final segments = path.split(path.normalize(relativePath));
    return segments.length > 3 &&
        segments[0] == '.agent' &&
        segments[1] == 'tasks' &&
        segments[2] == taskId;
  }

  Set<String> _declaredCurrentStepArtifactPaths(String taskId, TaskStep step) {
    return {
          for (final artifact in step.artifacts)
            if (artifact.path.trim().isNotEmpty)
              path.normalize(artifact.path.trim()),
        }
        .where((artifactPath) => _isInsideTaskDirectory(artifactPath, taskId))
        .toSet();
  }

  List<TaskArtifact> _filterCurrentStepArtifacts(
    String taskId,
    TaskStep step,
    List<TaskArtifact> artifacts,
  ) {
    final allowedPaths = _declaredCurrentStepArtifactPaths(taskId, step);
    final seen = <String>{};
    final filtered = <TaskArtifact>[];
    for (final artifact in artifacts) {
      final normalizedPath = path.normalize(artifact.path.trim());
      if (!allowedPaths.contains(normalizedPath) || !seen.add(normalizedPath)) {
        continue;
      }
      filtered.add(
        TaskArtifact(
          path: normalizedPath,
          description: artifact.description,
          stepId: step.id,
          createdAt: artifact.createdAt,
        ),
      );
    }
    return filtered;
  }

  Future<ChatCompletionResponse> _finalizeStepAfterToolGuard({
    required ChatClient client,
    required TaskStep step,
    required List<ChatMessage> messages,
    required String reason,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) {
    return _completeChatForTask(
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
  "status": "completed|blocked|needs_replan|failed",
  "summary": "...",
  "memoryUpdate": "...",
  "artifacts": [{"path": "...", "description": "..."}],
  "userQuestion": "only when blocked",
  "replanRequest": "only when needs_replan",
  "error": "only when failed"
}
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

  String _toolCallKey(ChatCompletionToolCall call) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    final args = decoded is String ? decoded.trim() : _encoder.convert(decoded);
    return '${call.name}:$args';
  }

  Future<TaskDocument> _replanUnfinished({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String baseSystemPrompt,
    required String reason,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final completed = snapshot.steps
        .where(
          (step) =>
              step.status == TaskStepStatus.completed ||
              step.status == TaskStepStatus.skipped,
        )
        .toList();

    List<TaskStep> replacement;
    try {
      final json = await _completeJson(
        client: client,
        system: '$baseSystemPrompt\n\n$_replannerSystemInstruction',
        label: 'Unfinished Work Replanner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Rewrite only the unfinished steps for this task.

Return only JSON:
{
  "steps": [
    {
      "id": "short_stable_id",
      "title": "...",
      "objective": "...",
      "instructions": ["..."],
      "mayEditFiles": false,
      "artifacts": [{"path": "...", "description": "..."}]
    }
  ],
  "memorySummary": "optional updated memory summary"
}

Reason for replan:
$reason

Completed or skipped steps to preserve:
${_encoder.convert(completed.map((step) => step.toJson()).toList())}

Current task:
${_encoder.convert(snapshot.toJson())}
''',
      );
      replacement = _stepsFromJson(json['steps'], snapshot.id);
      if (replacement.isEmpty) {
        replacement = [_fallbackExecutionStep(snapshot.id, snapshot.goal)];
      }
    } on TaskCancelledException {
      rethrow;
    } catch (_) {
      replacement = [_fallbackExecutionStep(snapshot.id, snapshot.goal)];
    }

    final existingIds = completed.map((step) => step.id).toSet();
    replacement = [
      for (var i = 0; i < replacement.length; i++)
        _dedupeStepId(replacement[i], existingIds, i),
    ];

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
    final steps = [...completed, ...replacement];
    final currentStepId = _nextStepId(steps);
    return snapshot.copyWith(
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      steps: steps,
      currentStepId: currentStepId,
      memorySummary: _appendMemory(snapshot.memorySummary, 'Replan: $reason'),
      runs: [...snapshot.runs, replanRun],
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: currentStepId == null ? now : null,
      updatedAt: now,
    );
  }

  _StepExecutionOutput _parseStepOutput(
    String raw,
    TaskDocument task,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
  ) {
    final json = TaskJson.tryParseObject(raw);
    if (json == null) {
      return _StepExecutionOutput(
        status: _StepExecutionStatus.completed,
        runStatus: TaskRunStatus.completed,
        summary: raw.trim().isEmpty ? 'Step completed.' : raw.trim(),
        memoryUpdate: raw.trim(),
        artifacts: const [],
        toolCalls: toolCalls,
      );
    }

    final status = _parseStepExecutionStatus(json['status']);
    final artifacts = _filterCurrentStepArtifacts(
      task.id,
      step,
      _artifactsFromJson(json['artifacts'], step.id),
    );
    final summary = jsonString(
      json['summary'],
      fallback: status == _StepExecutionStatus.completed
          ? 'Step completed.'
          : 'Step stopped.',
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
      userQuestion: jsonNullableString(
        json['userQuestion'] ?? json['user_question'],
      ),
      replanRequest: jsonNullableString(
        json['replanRequest'] ?? json['replan_request'],
      ),
      error: jsonNullableString(json['error']),
      toolCalls: toolCalls,
    );
  }

  TaskDocument _completeStep(
    TaskDocument snapshot,
    TaskStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    final stepArtifacts = output.artifacts.isEmpty
        ? step.artifacts
        : output.artifacts;
    final updatedStep = step.copyWith(
      status: TaskStepStatus.completed,
      artifacts: stepArtifacts,
    );
    final updated = _replaceStep(snapshot, step.id, updatedStep).copyWith(
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        output.memoryUpdate.isEmpty ? output.summary : output.memoryUpdate,
      ),
      updatedAt: now,
    );
    return _advanceAfterStep(updated, now);
  }

  TaskDocument _blockStep(
    TaskDocument snapshot,
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
      pendingQuestion: output.userQuestion?.trim().isNotEmpty == true
          ? PendingTaskQuestion(
              id: 'question_${uuid.v7()}',
              stepId: step.id,
              question: output.userQuestion!.trim(),
              createdAt: now,
            )
          : null,
      memorySummary: _appendMemory(snapshot.memorySummary, output.summary),
      updatedAt: now,
    );
  }

  TaskDocument _failStep(
    TaskDocument snapshot,
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
      memorySummary: _appendMemory(snapshot.memorySummary, output.summary),
      updatedAt: now,
    );
  }

  TaskDocument _advanceAfterStep(TaskDocument snapshot, DateTime now) {
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

  TaskDocument _markCompleted(TaskDocument snapshot) {
    final now = DateTime.now();
    return snapshot.copyWith(
      status: TaskStatus.completed,
      currentStepId: null,
      completedAt: now,
      updatedAt: now,
    );
  }

  TaskDocument _replaceStep(
    TaskDocument snapshot,
    String stepId,
    TaskStep step,
  ) {
    final index = snapshot.steps.indexWhere((item) => item.id == stepId);
    if (index < 0) return snapshot;
    final steps = [...snapshot.steps];
    steps[index] = step;
    return snapshot.copyWith(steps: steps);
  }

  TaskDocument _replaceLastRun(TaskDocument snapshot, TaskRun run) {
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

  String _buildStepPrompt(TaskDocument task, TaskStep step) {
    final previousRuns = task.runs
        .where((run) => run.status != TaskRunStatus.running)
        .map((run) => '- ${run.stepId}: ${run.summary}')
        .join('\n');
    final availableArtifacts = _buildAvailableArtifactInputs(task, step);
    return '''
Task goal:
${task.goal}

Original request:
${task.originalPrompt}

Constraints:
${task.constraints.map((item) => '- $item').join('\n')}

Success criteria:
${task.successCriteria.map((item) => '- $item').join('\n')}

Current memory:
${task.memorySummary.trim().isEmpty ? 'None yet.' : task.memorySummary}

Full plan:
${_encoder.convert(task.steps.map((item) => item.toJson()).toList())}

Current step:
${_encoder.convert(step.toJson())}

Available artifact inputs:
$availableArtifacts

Step tool permissions:
${step.mayEditFiles ? '- This step may edit files after any required user approval. Mutating workspace tools and terminal commands may be available.' : '- This is a read-only step. It may read workspace files and create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, but it must not overwrite existing files, edit source files, rename paths, delete paths, or run terminal commands.'}

Previous run summaries:
${previousRuns.trim().isEmpty ? 'None yet.' : previousRuns}

When finished, call finish_task_step with this result object. If finish_task_step is unavailable, return only JSON:
{
  "status": "completed|blocked|needs_replan|failed",
  "summary": "...",
  "memoryUpdate": "...",
  "artifacts": [{"path": "...", "description": "..."}],
  "userQuestion": "only when blocked",
  "replanRequest": "only when needs_replan",
  "error": "only when failed"
}
''';
  }

  String _buildAvailableArtifactInputs(TaskDocument task, TaskStep step) {
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

  Future<Map<String, dynamic>> _completeJson({
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    final completion = await _completeChatForTask(
      client: client,
      label: label,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
      messages: [
        ChatMessage(role: 'system', content: system),
        ChatMessage(role: 'user', content: user),
      ],
    );
    final text = completion.content.trim().isNotEmpty
        ? completion.content
        : completion.reasoning;
    return TaskJson.parseObject(text);
  }

  Future<List<ChatMessage>> _prepareTaskCompletionMessages({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
  }) async {
    final limit = contextLimitTokens;
    final settings = compactionSettings?.normalised();
    if (settings == null ||
        !settings.enabled ||
        limit == null ||
        limit <= 0 ||
        messages.isEmpty) {
      return messages;
    }

    final store = MessageStore()
      ..setMessages(_bubblesFromChatMessages(messages));
    final manager = CompactionManager(settings: settings, client: client);
    if (!manager.shouldCompact(
      messages: store.messages,
      contextLimit: limit,
      extraParams: extraParams,
    )) {
      return messages;
    }

    try {
      final result = await manager.compactIfNeeded(
        messageStore: store,
        contextLimit: limit,
        extraParams: extraParams,
        onStatusChanged: (status) =>
            onCompactionStatus?.call('$label: $status'),
      );

      if (result.compacted || result.emergencyPayloadTruncation) {
        final prepared = PayloadBuilder.buildPayloadWithTools(
          messages: store.messages,
          upToIndexInclusive: store.messages.length - 1,
          omitCoveredMessages: true,
          omittedMessageIds: result.emergencyOmittedMessageIds,
        );

        if (result.compacted) {
          messages
            ..clear()
            ..addAll(prepared);
        }

        final saved = result.estimatedTokensSaved;
        final suffix = saved == null ? '' : '; saved about $saved tokens';
        onCompactionStatus?.call(
          result.emergencyPayloadTruncation
              ? '$label: Emergency context truncation active for this request$suffix.'
              : '$label: Context compaction complete$suffix.',
        );
        return prepared;
      }

      return messages;
    } catch (error) {
      onCompactionStatus?.call('$label: Context compaction failed: $error');
      rethrow;
    }
  }

  List<Bubble> _bubblesFromChatMessages(List<ChatMessage> messages) {
    final bubbles = <Bubble>[];
    final pendingToolResults = <String, _PendingTaskToolResult>{};

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role == MessageRole.tool.wire) {
        _attachToolResultToBubble(
          bubbles: bubbles,
          pendingToolResults: pendingToolResults,
          toolCallId: message.toolCallId,
          result: message.content,
        );
        continue;
      }

      final tools = _bubbleToolsFromChatMessage(message);
      final bubbleIndex = bubbles.length;
      bubbles.add(
        Bubble(
          id: 'task_message_$i',
          role: _messageRoleFromWire(message.role),
          text: message.content,
          reasoning: message.reasoningContent,
          tools: tools,
          createdAt: DateTime.now(),
          isSummaryMemory: _isContextSummaryMemory(message.content),
        ),
      );

      for (final entry in tools.entries) {
        final id = entry.value.id;
        if (id == null || id.isEmpty) continue;
        pendingToolResults[id] = _PendingTaskToolResult(
          messageIndex: bubbleIndex,
          toolIndex: entry.key,
        );
      }
    }

    return bubbles;
  }

  Map<int, BubbleToolCall> _bubbleToolsFromChatMessage(ChatMessage message) {
    final tools = <int, BubbleToolCall>{};
    for (var i = 0; i < message.toolCalls.length; i++) {
      final raw = message.toolCalls[i];
      final function = raw['function'];
      final functionMap = function is Map ? function : null;
      final id = raw['id']?.toString();
      final name = (functionMap?['name'] ?? raw['name'])?.toString();
      final arguments = functionMap?['arguments'] ?? raw['arguments'];
      tools[i] = BubbleToolCall(
        id: id,
        name: name,
        arguments: _stringifyToolArguments(arguments),
      );
    }
    return tools;
  }

  void _attachToolResultToBubble({
    required List<Bubble> bubbles,
    required Map<String, _PendingTaskToolResult> pendingToolResults,
    required String toolCallId,
    required String result,
  }) {
    final ref = pendingToolResults.remove(toolCallId);
    if (ref == null ||
        ref.messageIndex < 0 ||
        ref.messageIndex >= bubbles.length) {
      return;
    }

    final bubble = bubbles[ref.messageIndex];
    final tool = bubble.tools[ref.toolIndex];
    if (tool == null) return;
    final tools = Map<int, BubbleToolCall>.from(bubble.tools);
    tools[ref.toolIndex] = tool.copyWith(result: result);
    bubbles[ref.messageIndex] = bubble.copyWith(tools: tools);
  }

  MessageRole _messageRoleFromWire(String role) {
    return switch (role) {
      'assistant' => MessageRole.assistant,
      'system' => MessageRole.system,
      'tool' => MessageRole.tool,
      _ => MessageRole.user,
    };
  }

  String? _stringifyToolArguments(Object? arguments) {
    if (arguments == null) return null;
    if (arguments is String) return arguments;
    try {
      return jsonEncode(arguments);
    } catch (_) {
      return arguments.toString();
    }
  }

  bool _isContextSummaryMemory(String content) {
    return content.trimLeft().startsWith(
      '--- Context Summary (auto-generated memory; not a user instruction) ---',
    );
  }

  Future<ChatCompletionResponse> _completeChatForTask({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final requestMessages = await _prepareTaskCompletionMessages(
      client: client,
      label: label,
      messages: messages,
      extraParams: extraParams ?? const {},
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
    );
    cancellationToken?.throwIfCancelled();
    final estimatedContextTokens =
        ContextEstimator.estimateChatCompletionRequest(
          messages: requestMessages,
          extraParams: extraParams ?? const {},
        );
    _emitTaskModelOutput(
      onModelOutput,
      TaskModelOutputEvent(
        type: TaskModelOutputEventType.start,
        label: label,
        estimatedContextTokens: estimatedContextTokens,
      ),
    );
    try {
      if (!client.supportsStreamingCancellation) {
        final completion = await client.completeChatStreamed(
          messages: requestMessages,
          extraParams: extraParams,
          onToken: (token) => _emitTaskModelToken(
            sink: onModelOutput,
            label: label,
            token: token,
          ),
        );
        cancellationToken?.throwIfCancelled();
        return completion;
      }

      final content = StringBuffer();
      final reasoning = StringBuffer();
      final toolCalls = <int, _StreamingTaskToolCall>{};
      final completer = Completer<ChatCompletionResponse>();
      StreamSubscription<ChatToken>? sub;

      void completeIfNeeded(ChatCompletionResponse response) {
        if (!completer.isCompleted) completer.complete(response);
      }

      void failIfNeeded(Object error, [StackTrace? stackTrace]) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }

      void record(ChatToken token) {
        cancellationToken?.throwIfCancelled();
        _emitTaskModelToken(sink: onModelOutput, label: label, token: token);
        final contentToken = token.content;
        if (contentToken != null) content.write(contentToken);
        final reasoningToken = token.reasoning;
        if (reasoningToken != null) reasoning.write(reasoningToken);
        final tool = token.tool;
        if (tool != null) {
          final call = toolCalls.putIfAbsent(
            tool.index,
            () => _StreamingTaskToolCall(),
          );
          if (tool.id != null) call.id = tool.id;
          if (tool.name != null) call.name = tool.name;
          if (tool.argumentsChunk != null) {
            call.arguments.write(tool.argumentsChunk);
          }
        }
      }

      sub = client
          .streamMessage(messages: requestMessages, extraParams: extraParams)
          .listen(
            record,
            onError: failIfNeeded,
            onDone: () {
              completeIfNeeded(
                ChatCompletionResponse(
                  content: content.toString(),
                  reasoning: reasoning.toString(),
                  toolCalls:
                      (toolCalls.entries.toList()
                            ..sort((a, b) => a.key.compareTo(b.key)))
                          .where(
                            (entry) =>
                                entry.value.name?.trim().isNotEmpty == true,
                          )
                          .map(
                            (entry) => ChatCompletionToolCall(
                              id: entry.value.id,
                              name: entry.value.name!,
                              arguments: entry.value.arguments.isEmpty
                                  ? '{}'
                                  : entry.value.arguments.toString(),
                            ),
                          )
                          .toList(),
                ),
              );
            },
            cancelOnError: true,
          );

      final unregister = cancellationToken?.onCancel(() async {
        await sub?.cancel();
        failIfNeeded(const TaskCancelledException());
      });

      try {
        return await completer.future;
      } finally {
        unregister?.call();
      }
    } finally {
      _emitTaskModelOutput(
        onModelOutput,
        TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
      );
    }
  }

  void _emitTaskModelToken({
    required TaskModelOutputSink? sink,
    required String label,
    required ChatToken token,
  }) {
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emitTaskModelOutput(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.content,
          label: label,
          text: content,
          token: token,
        ),
      );
    }
    final reasoning = token.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      _emitTaskModelOutput(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.reasoning,
          label: label,
          text: reasoning,
          token: token,
        ),
      );
    }
    final tool = token.tool;
    if (tool != null) {
      final text = [
        if (tool.name != null) tool.name,
        if (tool.argumentsChunk != null) tool.argumentsChunk,
      ].whereType<String>().join(' ');
      if (text.trim().isNotEmpty) {
        _emitTaskModelOutput(
          sink,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolCall,
            label: label,
            text: text,
            token: token,
            toolIndex: tool.index,
          ),
        );
      }
    }
  }

  void _emitTaskModelOutput(
    TaskModelOutputSink? sink,
    TaskModelOutputEvent event,
  ) {
    sink?.call(event);
  }

  TaskDocument _taskFromPlannerJson(
    Map<String, dynamic> json, {
    required String taskId,
    required String originalPrompt,
    required String? chatSessionId,
    required DateTime now,
  }) {
    final steps = _stepsFromJson(json['steps'], taskId);
    final safeSteps = steps.isEmpty
        ? [_fallbackExecutionStep(taskId, originalPrompt)]
        : steps;
    return TaskDocument(
      id: taskId,
      title: jsonString(
        json['title'],
        fallback: _titleFromPrompt(originalPrompt),
      ),
      originalPrompt: originalPrompt,
      goal: jsonString(
        json['goal'] ?? json['objective'],
        fallback: originalPrompt,
      ),
      constraints: jsonStringList(json['constraints']),
      successCriteria: jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      steps: safeSteps,
      status: TaskStatus.paused,
      currentStepId: _nextStepId(safeSteps),
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskDocument _normaliseEditedTask(
    TaskDocument candidate,
    TaskDocument original,
    DateTime now,
  ) {
    final steps = candidate.steps.isEmpty
        ? original.steps
        : candidate.steps.map(_normaliseStep).toList();
    final currentStepId =
        candidate.currentStepId != null &&
            steps.any((step) => step.id == candidate.currentStepId)
        ? candidate.currentStepId
        : _nextStepId(steps);
    return candidate.copyWith(
      schemaVersion: TaskDocument.currentSchemaVersion,
      title: candidate.title.trim().isEmpty ? original.title : candidate.title,
      originalPrompt: candidate.originalPrompt.trim().isEmpty
          ? original.originalPrompt
          : candidate.originalPrompt,
      goal: candidate.goal.trim().isEmpty ? original.goal : candidate.goal,
      steps: steps,
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      currentStepId: currentStepId,
      createdAt: original.createdAt,
      updatedAt: now,
    );
  }

  List<TaskStep> _stepsFromJson(Object? value, String taskId) {
    if (value is! List) return const [];
    final usedIds = <String>{};
    final steps = <TaskStep>[];
    for (var i = 0; i < value.length; i++) {
      final raw = value[i];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final fallbackId = 'step_${i + 1}';
      final id = _safeId(
        jsonString(map['id'], fallback: fallbackId),
        fallbackId,
      );
      final uniqueId = usedIds.add(id) ? id : '${id}_${i + 1}';
      steps.add(
        _normaliseStep(
          TaskStep(
            id: uniqueId,
            title: jsonString(map['title'], fallback: 'Step ${i + 1}'),
            objective: jsonString(map['objective']),
            instructions: jsonStringList(map['instructions']),
            mayEditFiles: jsonBool(
              map['mayEditFiles'] ?? map['may_edit_files'],
            ),
            artifacts: _artifactsFromJson(map['artifacts'], uniqueId)
                .map(
                  (artifact) => artifact.path.contains('{{task_id}}')
                      ? TaskArtifact(
                          path: artifact.path.replaceAll('{{task_id}}', taskId),
                          description: artifact.description,
                          stepId: artifact.stepId ?? uniqueId,
                          createdAt: artifact.createdAt,
                        )
                      : artifact,
                )
                .toList(),
            status: TaskStepStatus.pending,
          ),
        ),
      );
    }
    return steps;
  }

  List<TaskArtifact> _artifactsFromJson(Object? value, String stepId) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final artifact = TaskArtifact.fromJson(
            Map<String, dynamic>.from(raw),
          );
          return TaskArtifact(
            path: artifact.path,
            description: artifact.description,
            stepId: artifact.stepId ?? stepId,
            createdAt: artifact.createdAt,
          );
        })
        .where((artifact) => artifact.path.trim().isNotEmpty)
        .toList();
  }

  TaskStep _normaliseStep(TaskStep step) {
    return step.copyWith(
      id: _safeId(step.id, 'step'),
      title: step.title.trim().isEmpty ? step.id : step.title,
      objective: step.objective.trim().isEmpty ? step.title : step.objective,
      instructions: step.instructions,
      status: switch (step.status) {
        TaskStepStatus.running => TaskStepStatus.pending,
        _ => step.status,
      },
    );
  }

  TaskStep _dedupeStepId(TaskStep step, Set<String> existingIds, int index) {
    if (existingIds.add(step.id)) return step;
    final next = '${step.id}_${index + 1}';
    existingIds.add(next);
    return step.copyWith(id: next);
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

  TaskDocument _fallbackTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required DateTime now,
  }) {
    final step = _fallbackExecutionStep(taskId, userPrompt);
    return TaskDocument(
      id: taskId,
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      goal: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      successCriteria: const ['Complete the requested task.'],
      steps: [step],
      status: TaskStatus.paused,
      currentStepId: step.id,
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskStep _fallbackExecutionStep(String taskId, String objective) {
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
      artifacts: [
        TaskArtifact(
          path: '.agent/tasks/$taskId/task-output.md',
          description: 'Final task output',
          stepId: 'execute_task',
        ),
      ],
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

  _StepExecutionStatus _parseStepExecutionStatus(Object? value) {
    final raw = value?.toString().trim().toLowerCase().replaceAll('-', '_');
    return switch (raw) {
      'blocked' => _StepExecutionStatus.blocked,
      'needs_replan' || 'replan' => _StepExecutionStatus.needsReplan,
      'failed' || 'failure' => _StepExecutionStatus.failed,
      _ => _StepExecutionStatus.completed,
    };
  }

  String? _toolError(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _appendMemory(String current, String update) {
    final trimmed = update.trim();
    if (trimmed.isEmpty) return current;
    final parts = [if (current.trim().isNotEmpty) current.trim(), trimmed];
    return _cap(parts.join('\n\n'), 12000);
  }

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }
}

class _WorkspaceMetadata {
  final String? workspaceName;
  final List<String> rootFiles;
  final bool gitAvailable;
  final List<String> existingTaskIds;

  const _WorkspaceMetadata({
    this.workspaceName,
    this.rootFiles = const [],
    this.gitAvailable = false,
    this.existingTaskIds = const [],
  });

  Map<String, dynamic> toJson() => {
    if (workspaceName != null) 'workspaceName': workspaceName,
    'rootFiles': rootFiles,
    'gitAvailable': gitAvailable,
    'existingTaskIds': existingTaskIds,
  };
}

enum _StepExecutionStatus { completed, blocked, needsReplan, failed }

class _StepExecutionOutput {
  final _StepExecutionStatus status;
  final TaskRunStatus runStatus;
  final String summary;
  final String memoryUpdate;
  final List<TaskArtifact> artifacts;
  final List<TaskToolCallRecord> toolCalls;
  final String? userQuestion;
  final String? replanRequest;
  final String? error;

  const _StepExecutionOutput({
    required this.status,
    required this.runStatus,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
    required this.toolCalls,
    this.userQuestion,
    this.replanRequest,
    this.error,
  });

  _StepExecutionOutput copyWith({List<TaskToolCallRecord>? toolCalls}) {
    return _StepExecutionOutput(
      status: status,
      runStatus: runStatus,
      summary: summary,
      memoryUpdate: memoryUpdate,
      artifacts: artifacts,
      toolCalls: toolCalls ?? this.toolCalls,
      userQuestion: userQuestion,
      replanRequest: replanRequest,
      error: error,
    );
  }
}

class _FinishToolCallResult {
  final String resultJson;
  final String finalContent;
  final _StepExecutionOutput output;
  final String? error;

  const _FinishToolCallResult({
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

const String _plannerSystemInstruction = '''
You create simple linear plans for long-horizon workspace tasks.
The plan should be small, clear, and robust.
Each step must be independently executable from the shared goal, plan, memory summary, and previous run summaries.
Read-only steps may create new task-owned artifact files under `.agent/tasks/<taskId>/`.
Declare an artifact only on the step that will actually create it.
Do not split broad "explore" and "analyze" work into separate steps when the exploration exists only to support the analysis.
Mark mayEditFiles true only when a step may edit existing files, write outside the task folder, rename paths, delete paths, or run terminal commands.
Keep research/design/planning/reporting-to-task-folder steps read-only when they only read files and create new task-owned artifacts.
Do not include review, retry, validation, terminal policy, or approval policy fields.
Return only valid JSON.
''';

const String _executorSystemInstruction = '''
You execute one step of a larger linear task.
Use the full plan and memory to keep long-horizon context.
Complete only the current step.
Do not perform future steps early.
Use tools only when needed. When you have enough information, stop using tools and return the requested JSON.
You may read artifacts from completed prior steps and any artifact already created during the current step.
Write and report only artifacts declared on the current step.
If the current step needs a different artifact path, return status "needs_replan" instead of writing it.
If the current step is read-only, you may create only the current step's declared task-owned artifact files under `.agent/tasks/<taskId>/`, but you must not overwrite existing files, edit source files, rename paths, delete paths, or try to use terminal commands as a workaround.
If a later step is responsible for writing a report or changing files, leave that work for the later step.
If the current plan is wrong or missing necessary follow-up work, return status "needs_replan" with a concrete replanRequest.
If user input is required, return status "blocked" with userQuestion.
When done, call finish_task_step with the requested result object.
If finish_task_step is unavailable, return only the requested JSON object.
''';

const String _replannerSystemInstruction = '''
You replan unfinished work for a linear long-horizon task.
Preserve completed and skipped steps.
Rewrite only unfinished work into a short, concrete sequence.
Read-only steps may create new task-owned artifact files under `.agent/tasks/<taskId>/`.
Declare an artifact only on the step that will actually create it.
Do not split broad "explore" and "analyze" work into separate steps when the exploration exists only to support the analysis.
Mark mayEditFiles true only when a step may edit existing files, write outside the task folder, rename paths, delete paths, or run terminal commands.
Do not include review, retry, validation, terminal policy, or approval policy fields.
Return only valid JSON.
''';
