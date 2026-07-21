import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/compaction_manager.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/finalizer_tool_call_runner.dart';
import 'package:hermes/core/services/task_system/task_gate_evaluator.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/tools/tool_error.dart';
import 'package:path/path.dart' as path;

part 'task_service.mapper.dart';

typedef TaskCancelRegistration = void Function();
typedef TaskCancelCallback = FutureOr<void> Function();
typedef TaskCompactionStatusSink = void Function(String status);

@MappableClass(generateMethods: GenerateMethods.encode)
class TaskPlanningContext with TaskPlanningContextMappable {
  final String projectGoal;
  final String projectTaskObjective;
  final List<String> knownFacts;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<TaskArtifact> expectedArtifacts;
  final List<TaskGate> requiredGates;
  final int maxSteps;

  const TaskPlanningContext({
    required this.projectGoal,
    required this.projectTaskObjective,
    this.knownFacts = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.expectedArtifacts = const [],
    this.requiredGates = const [],
    this.maxSteps = 3,
  });
}

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

class _AllowedTaskCommand {
  final String command;
  final String workingDirectory;

  const _AllowedTaskCommand({
    required this.command,
    required this.workingDirectory,
  });
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
        'description':
            'Question to ask the user when status is blocked. Prefer an object with question, reason, defaultIfUnanswered, riskOfAssuming, and kind.',
        'oneOf': [
          {'type': 'string'},
          {
            'type': 'object',
            'properties': {
              'question': {'type': 'string'},
              'reason': {'type': 'string'},
              'defaultIfUnanswered': {'type': 'string'},
              'riskOfAssuming': {'type': 'string'},
              'kind': {
                'type': 'string',
                'enum': ['blocking', 'preference', 'advisory'],
              },
            },
            'required': ['question'],
          },
        ],
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

const String _finaliseTaskCreationToolId = 'finaliseTaskCreation';

const ToolDefinition _finaliseTaskCreationToolDefinition = ToolDefinition(
  id: _finaliseTaskCreationToolId,
  name: 'Finalise task creation',
  description:
      'Finalize task creation with the complete structured task plan. Call this exactly once after any needed read-only workspace discovery.',
  schema: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'goal': {'type': 'string'},
      'constraints': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'successCriteria': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'gates': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'required': {'type': 'boolean'},
            'scope': {'type': 'string'},
            'params': {'type': 'object'},
            'description': {'type': 'string'},
          },
          'required': ['id'],
        },
      },
      'steps': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'title': {'type': 'string'},
            'objective': {'type': 'string'},
            'instructions': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'mayEditFiles': {'type': 'boolean'},
            'artifacts': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                  'description': {'type': 'string'},
                },
                'required': ['path'],
              },
            },
            'gates': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string'},
                  'required': {'type': 'boolean'},
                  'scope': {'type': 'string'},
                  'params': {'type': 'object'},
                  'description': {'type': 'string'},
                },
                'required': ['id'],
              },
            },
          },
          'required': [
            'id',
            'title',
            'objective',
            'instructions',
            'mayEditFiles',
          ],
        },
      },
    },
    'required': ['title', 'goal', 'successCriteria', 'steps'],
  },
);

class TaskService {
  TaskService({
    required ToolService toolService,
    required WorkspaceSandbox sandbox,
    TaskRepository? repository,
  }) : _toolService = toolService,
       _creationRunner = FinalizerToolCallRunner(toolService: toolService),
       _repository = repository ?? TaskRepository(),
       _sandbox = sandbox,
       _gateEvaluator = TaskGateEvaluator(sandbox: sandbox);

  final ToolService _toolService;
  final FinalizerToolCallRunner _creationRunner;
  final TaskRepository _repository;
  final WorkspaceSandbox _sandbox;
  final TaskGateEvaluator _gateEvaluator;
  final QuestionPolicyService _questionPolicy = const QuestionPolicyService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  TaskRepository get repository => _repository;
  ToolService get toolService => _toolService;

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _repository.listTasks(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<TaskDocument?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _repository.loadLatestTask(
      workspace.rootPath,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<TaskDocument?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
  }) {
    return _repository.loadTask(
      workspace.rootPath,
      taskId,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
  }

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _repository.deleteTasksForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _repository.deleteOrphanedChatTasks(
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
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
    await _repository.saveSnapshot(workspace.rootPath, recovered);
    return recovered;
  }

  String encodeTask(TaskDocument task) =>
      '${_encoder.convert(ModelJson.encode(task))}\n';

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
        ? const WorkspaceMetadata()
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
${_encoder.convert(ModelJson.encode(metadata))}

Request:
$userPrompt
''',
      );
      return _normaliseBrief(
        ModelJson.decode<RefinedTaskBrief>(json),
        userPrompt,
      );
    } on TaskCancelledException {
      rethrow;
    } on ChatTransportException {
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
    String? projectId,
    TaskPlanningContext? planningContext,
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
      final json = await _completeTaskCreation(
        client: client,
        system: '$baseSystemPrompt\n\n$_plannerSystemInstruction',
        label: 'Task Planner',
        workspace: workspace,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user: _buildPlannerPrompt(
          taskId: taskId,
          userPrompt: userPrompt,
          metadata: metadata,
          planningContext: planningContext,
        ),
      );
      task = _taskFromPlannerJson(
        json,
        taskId: taskId,
        originalPrompt: userPrompt,
        chatSessionId: chatSessionId,
        projectId: projectId,
        requiredGates: planningContext?.requiredGates ?? const [],
        now: now,
      );
      if (planningContext != null) {
        final violations = _projectPlanningViolations(task, planningContext);
        if (violations.isNotEmpty) {
          task = await _repairProjectBoundedTaskPlan(
            client: client,
            task: task,
            taskId: taskId,
            originalPrompt: userPrompt,
            baseSystemPrompt: baseSystemPrompt,
            workspace: workspace,
            metadata: metadata,
            planningContext: planningContext,
            violations: violations,
            chatSessionId: chatSessionId,
            projectId: projectId,
            now: now,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
        }
      }
    } on TaskCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
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
    }

    await _repository.saveSnapshot(workspace.rootPath, task);
    return task;
  }

  Future<TaskDocument> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required TaskDocument snapshot,
    required String rawJson,
  }) async {
    final parsed = ModelJson.decode<TaskDocument>(
      TaskJson.parseObject(rawJson),
    );
    final now = DateTime.now();
    final normalised = _normaliseEditedTask(
      parsed.copyWith(
        id: snapshot.id,
        chatSessionId: snapshot.chatSessionId,
        projectId: snapshot.projectId,
      ),
      snapshot,
      now,
    );
    await _repository.saveSnapshot(workspace.rootPath, normalised);
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
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    var working = await recoverTask(workspace: workspace, snapshot: snapshot);
    if (working.isTerminal) return working;
    final step = working.nextRunnableStep;
    if (step == null) {
      final completed = _markCompleted(working);
      await _repository.saveSnapshot(workspace.rootPath, completed);
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
      await _repository.saveSnapshot(workspace.rootPath, blocked);
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
    await _repository.saveSnapshot(workspace.rootPath, working);

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

      await _repository.saveSnapshot(workspace.rootPath, working);
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
      await _repository.saveSnapshot(workspace.rootPath, working);
      return working;
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
      await _repository.saveSnapshot(workspace.rootPath, working);
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
      await _repository.saveSnapshot(workspace.rootPath, working);
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
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
    await _repository.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<WorkspaceMetadata> _collectWorkspaceMetadata(
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
    return WorkspaceMetadata(
      workspaceName: workspace.displayName,
      rootFiles: rootFiles,
      gitAvailable: rootFiles.contains('.git'),
      commandExecutionApproved: workspace.commandExecutionApproved,
      existingTaskIds: (await _repository.listTasks(
        workspace.rootPath,
        chatSessionId: chatSessionId,
      )).map((task) => task.id).toList(),
    );
  }

  String _buildPlannerPrompt({
    required String taskId,
    required String userPrompt,
    required WorkspaceMetadata metadata,
    required TaskPlanningContext? planningContext,
  }) {
    final context = planningContext;
    if (context == null) {
      return '''
Create a linear multi-step task plan.

Return only JSON:
{
  "title": "...",
  "goal": "...",
  "constraints": ["..."],
  "successCriteria": ["..."],
  "gates": [{"id": "no_tool_errors", "required": true, "scope": "task", "params": {}, "description": "..."}],
  "steps": [
    {
      "id": "short_stable_id",
      "title": "...",
      "objective": "...",
      "instructions": ["..."],
      "mayEditFiles": false,
      "artifacts": [{"path": ".agent/tasks/$taskId/output.md", "description": "..."}],
      "gates": [{"id": "artifact_exists", "required": true, "scope": "step", "params": {"paths": [".agent/tasks/$taskId/output.md"]}, "description": "..."}]
    }
  ]
}

Gate catalog:
${_taskGateCatalogPrompt()}

Use this exact task id when referencing task-owned artifacts: $taskId
Create only as many steps as are necessary to accomplish the task.
Artifacts are optional.

Workspace metadata:
${_encoder.convert(ModelJson.encode(metadata))}

Request:
$userPrompt
''';
    }

    return '''
Create a linear plan for exactly one bounded Project task.

The Project goal is context only. Do not plan or perform the whole project.
The task plan must cover only the selected Project task objective.
Use at most ${context.maxSteps.clamp(1, 6)} steps.
Every step must stay inside the task's done criteria and out-of-scope boundaries.

Return only JSON:
{
  "title": "...",
  "goal": "the selected Project task objective, not the whole Project goal",
  "constraints": ["..."],
  "successCriteria": ["copy or refine the task doneCriteria"],
  "gates": [{"id": "no_tool_errors", "required": true, "scope": "task", "params": {}, "description": "..."}],
  "steps": [
    {
      "id": "short_stable_id",
      "title": "...",
      "objective": "...",
      "instructions": ["..."],
      "mayEditFiles": false,
      "artifacts": [{"path": ".agent/tasks/$taskId/output.md", "description": "..."}],
      "gates": [{"id": "artifact_exists", "required": true, "scope": "step", "params": {"paths": [".agent/tasks/$taskId/output.md"]}, "description": "..."}]
    }
  ]
}

Gate catalog:
${_taskGateCatalogPrompt()}

Use this exact task id when referencing task-owned artifacts: $taskId
Artifacts are optional unless expectedArtifacts lists them.

Workspace metadata:
${_encoder.convert(ModelJson.encode(metadata))}

Bounded Project task context:
${_encoder.convert(ModelJson.encode(context))}

Request:
$userPrompt
''';
  }

  Future<Map<String, dynamic>> _completeTaskCreation({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String system,
    required String user,
    required String label,
    bool allowReadOnlyTools = true,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) {
    return _creationRunner.completeWithFinalizer(
      client: client,
      workspace: workspace,
      label: label,
      system:
          '''
$system

You may use read-only tools to inspect the workspace before creating the task plan.
Do not edit files, run terminal commands, rename paths, delete paths, or create task artifacts during task creation.
When the task plan is ready, call the $_finaliseTaskCreationToolId tool with the complete structured task plan.
'''
              .trim(),
      user: user,
      finalizerTool: _finaliseTaskCreationToolDefinition,
      reminderPrompt:
          '''
You did not call $_finaliseTaskCreationToolId. Return only the JSON object that would be passed as that tool's arguments:
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
      "artifacts": []
    }
  ]
}
''',
      allowReadOnlyTools: allowReadOnlyTools,
      onModelOutput: onModelOutput,
      throwIfCancelled: cancellationToken?.throwIfCancelled,
    );
  }

  Future<TaskDocument> _repairProjectBoundedTaskPlan({
    required ChatClient client,
    required TaskDocument task,
    required String taskId,
    required String originalPrompt,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required WorkspaceMetadata metadata,
    required TaskPlanningContext planningContext,
    required List<String> violations,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
    TaskModelOutputSink? onModelOutput,
    TaskCancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeTaskCreation(
        client: client,
        system: '$baseSystemPrompt\n\n$_plannerSystemInstruction',
        label: 'Task Plan Repair',
        workspace: workspace,
        allowReadOnlyTools: false,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Repair this task plan so it executes exactly one bounded Project task.

Return only JSON in the normal task plan shape.

Violations:
${_encoder.convert(violations)}

Bounded Project task context:
${_encoder.convert(ModelJson.encode(planningContext))}

Workspace metadata:
${_encoder.convert(ModelJson.encode(metadata))}

Invalid task plan:
${_encoder.convert(ModelJson.encode(task))}
''',
      );
      final repaired = _taskFromPlannerJson(
        json,
        taskId: taskId,
        originalPrompt: originalPrompt,
        chatSessionId: chatSessionId,
        projectId: projectId,
        requiredGates: planningContext.requiredGates,
        now: now,
      );
      if (_projectPlanningViolations(repaired, planningContext).isEmpty) {
        return repaired;
      }
    } on TaskCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      // Fall through to deterministic bounded fallback.
    }

    return _fallbackProjectBoundedTask(
      taskId: taskId,
      userPrompt: originalPrompt,
      chatSessionId: chatSessionId,
      projectId: projectId,
      planningContext: planningContext,
      now: now,
    );
  }

  List<String> _projectPlanningViolations(
    TaskDocument task,
    TaskPlanningContext context,
  ) {
    final violations = <String>[];
    final maxSteps = context.maxSteps.clamp(1, 6).toInt();
    if (task.steps.length > maxSteps) {
      violations.add(
        'Task plan has ${task.steps.length} steps; max is $maxSteps.',
      );
    }
    if (_normalisePrompt(task.goal) == _normalisePrompt(context.projectGoal)) {
      violations.add('Task goal matches the whole project goal.');
    }
    if (task.successCriteria.isEmpty) {
      violations.add('Task plan has no success criteria.');
    }
    if (context.doneCriteria.isNotEmpty) {
      final planned = _normalisePrompt(task.successCriteria.join(' '));
      final missing = context.doneCriteria.where(
        (criterion) => !planned.contains(_normalisePrompt(criterion)),
      );
      if (missing.length == context.doneCriteria.length) {
        violations.add(
          'Task success criteria do not reflect the task done criteria.',
        );
      }
    }
    for (final step in task.steps) {
      if (_looksLikeWholeProject(step.objective, context.projectGoal)) {
        violations.add(
          'Step "${step.id}" appears to target the whole project.',
        );
      }
    }
    return violations;
  }

  bool _looksLikeWholeProject(String value, String projectGoal) {
    final normalised = _normalisePrompt(value);
    final project = _normalisePrompt(projectGoal);
    if (normalised == project) return true;
    return normalised.contains('entire project') ||
        normalised.contains('whole project') ||
        normalised.contains('complete the project') ||
        normalised.contains('finish the project');
  }

  String _normalisePrompt(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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
    final allowedCommands = _allowedCommandsForStep(task, step);
    final allowedToolIds = _allowedToolIdsForStep(step, allowedCommands);
    final toolDefs = [
      ..._toolService.getToolDefinitions(
        ids: allowedToolIds.toList(),
        includeWorkspaceTools: true,
      ),
      _finishTaskStepToolDefinition,
    ];
    final messages = <ChatMessage>[
      ChatMessage(
        role: 'system',
        content: '$baseSystemPrompt\n\n$_executorSystemInstruction',
      ),
      ChatMessage(
        role: 'user',
        content: _buildStepPrompt(task, step, workspace),
      ),
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
        final result = _structuredToolResult(finishCall.name, resultJson);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: finishCall.name,
            arguments: args,
            result: result,
            resultSummary: _cap(resultJson, 1200),
            error: finish.error,
            outcome: finish.error == null
                ? TaskToolCallOutcome.succeeded
                : TaskToolCallOutcome.failed,
            operationKey: 'finish_task_step',
            toolError: finish.error == null
                ? null
                : TaskToolError(
                    code: 'invalid_finish_arguments',
                    message: finish.error!,
                    disposition: TaskToolErrorDisposition.advisory,
                  ),
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
          allowedCommands: allowedCommands,
          context: context,
          blockedReason: loopGuardReason,
        );
        cancellationToken?.throwIfCancelled();
        final result = _structuredToolResult(call.name, resultJson);
        final toolError = _toolErrorInfo(result);
        toolCalls.add(
          TaskToolCallRecord(
            id: callId,
            stepId: step.id,
            runId: run.runId,
            toolName: call.name,
            arguments: args,
            result: result,
            resultSummary: _cap(resultJson, 1200),
            error: toolError?.message,
            outcome: _toolCallOutcome(result, toolError),
            operationKey: _operationKey(call.name, args),
            toolError: toolError,
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

    await _repository.saveLog(
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

  Future<_StepExecutionOutput> _applyCompletionGates({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required TaskDocument task,
    required TaskStep step,
    required _StepExecutionOutput execution,
    required String baseSystemPrompt,
  }) async {
    final gates = _completionGates(task, step);
    if (gates.isEmpty) return execution;
    final stepArtifacts = execution.artifacts.isEmpty
        ? step.artifacts
        : execution.artifacts;
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

  List<TaskGate> _completionGates(TaskDocument task, TaskStep step) {
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
    List<_AllowedTaskCommand> allowedCommands,
  ) {
    if (!step.mayEditFiles) {
      return {
        ..._readOnlyTaskToolIds,
        if (allowedCommands.isNotEmpty) 'run_command',
      };
    }
    return {..._readOnlyTaskToolIds, ..._mutatingTaskToolIds};
  }

  List<_AllowedTaskCommand> _allowedCommandsForStep(
    TaskDocument task,
    TaskStep step,
  ) {
    final seen = <String>{};
    final commands = <_AllowedTaskCommand>[];
    for (final gate in _completionGates(task, step)) {
      if (gate.id != 'command_passes' || !gate.required) continue;
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
        _AllowedTaskCommand(
          command: command,
          workingDirectory: workingDirectory,
        ),
      );
    }
    return commands;
  }

  String _commandTextFromParts(String command, List<String> args) {
    return [command, ...args].where((item) => item.isNotEmpty).join(' ').trim();
  }

  _FinishToolCallResult _finishStepFromToolCall({
    required Object args,
    required TaskDocument task,
    required TaskStep step,
    required List<TaskToolCallRecord> existingToolCalls,
  }) {
    if (args is! Map) {
      const error = 'finish_task_step arguments must be a JSON object.';
      final resultJson = _taskToolErrorJson(
        code: 'invalid_finish_arguments',
        message: error,
        disposition: TaskToolErrorDisposition.advisory,
      );
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
    required List<_AllowedTaskCommand> allowedCommands,
    required WorkspaceToolContext context,
    required String? blockedReason,
  }) async {
    if (blockedReason != null) {
      return _taskToolErrorJson(
        code: 'loop_guard',
        message: 'Tool call skipped by task runner.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {'reason': blockedReason, 'skipped': true},
      );
    }

    if (!allowedToolIds.contains(call.name)) {
      return _taskToolErrorJson(
        code: 'tool_not_available',
        message: 'Tool is not available for this task step.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {
          'tool': call.name,
          'mayEditFiles': step.mayEditFiles,
          'availableTools': allowedToolIds.toList()..sort(),
          'reason': step.mayEditFiles
              ? 'The tool was not exposed to the task runner.'
              : 'This read-only step can read files and create new task-owned artifact files, but cannot edit source files, overwrite files, run terminal commands, rename paths, or delete paths.',
        },
      );
    }

    if (!step.mayEditFiles && call.name == 'run_command') {
      final whitelistError = _readOnlyCommandWhitelistError(
        call,
        allowedCommands,
      );
      if (whitelistError != null) return whitelistError;
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

  String? _readOnlyCommandWhitelistError(
    ChatCompletionToolCall call,
    List<_AllowedTaskCommand> allowedCommands,
  ) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    if (decoded is! Map) {
      return _taskToolErrorJson(
        code: 'invalid_tool_arguments',
        message: 'run_command arguments must be a JSON object.',
        disposition: TaskToolErrorDisposition.advisory,
      );
    }
    final args = jsonMap(decoded);
    final command = _commandTextFromParts(
      jsonString(args['command']),
      jsonStringList(args['args']),
    );
    final workingDirectory = path.normalize(
      jsonString(
        args['working_directory'] ?? args['workingDirectory'],
        fallback: '.',
      ),
    );
    final allowed = allowedCommands.any(
      (item) =>
          item.command == command &&
          path.normalize(item.workingDirectory) == workingDirectory,
    );
    if (allowed) return null;
    return _taskToolErrorJson(
      code: 'command_not_whitelisted',
      message: 'Terminal command is not whitelisted for this read-only step.',
      disposition: TaskToolErrorDisposition.advisory,
      details: {
        'command': command,
        'working_directory': workingDirectory,
        'allowedCommands': [
          for (final item in allowedCommands)
            {
              'command': item.command,
              'working_directory': item.workingDirectory,
            },
        ],
      },
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
        return _taskToolErrorJson(
          code: 'invalid_tool_arguments',
          message: 'write_file arguments must be a JSON object.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }

      final rawPath = decoded['path'];
      final content = decoded['content'];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        return _taskToolErrorJson(
          code: 'invalid_tool_arguments',
          message: 'write_file requires a path.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }
      if (content is! String) {
        return _taskToolErrorJson(
          code: 'invalid_tool_arguments',
          message: 'write_file requires string content.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      if (!_isInsideTaskDirectory(resolved.relativePath, task.id)) {
        return _taskToolErrorJson(
          code: 'artifact_path_denied',
          message: 'Read-only steps may only create task-owned artifact files.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {
            'path': resolved.relativePath,
            'allowedPrefix': path.join('.agent', 'tasks', task.id),
          },
        );
      }
      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (!allowedPaths.contains(path.normalize(resolved.relativePath))) {
        return _taskToolErrorJson(
          code: 'artifact_not_declared',
          message:
              'Read-only steps may only create artifacts declared on the current step.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {
            'path': resolved.relativePath,
            'allowedArtifactPaths': allowedPaths.toList()..sort(),
          },
        );
      }

      final existingType = await FileSystemEntity.type(resolved.absolutePath);
      if (existingType != FileSystemEntityType.notFound) {
        return _taskToolErrorJson(
          code: 'read_only_overwrite_denied',
          message: 'Read-only steps cannot overwrite existing files.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {'path': resolved.relativePath},
        );
      }

      final result = await _sandbox.writeFile(
        context.workspace.rootPath,
        resolved.relativePath,
        content,
      );
      return jsonEncode(result);
    } on WorkspaceSandboxException catch (e) {
      return _taskToolErrorJson(
        code: e.code,
        message: e.message,
        disposition: TaskToolErrorDisposition.advisory,
      );
    } catch (e) {
      return _taskToolErrorJson(
        code: 'workspace_io_failure',
        message: e.toString(),
        disposition: TaskToolErrorDisposition.retryable,
      );
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

      return _taskToolErrorJson(
        code: 'artifact_not_declared',
        message:
            'Task steps may only create artifacts declared on the current step.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {
          'path': resolved.relativePath,
          'allowedArtifactPaths': allowedPaths.toList()..sort(),
        },
      );
    } on WorkspaceSandboxException catch (e) {
      return _taskToolErrorJson(
        code: e.code,
        message: e.message,
        disposition: TaskToolErrorDisposition.advisory,
      );
    } catch (e) {
      return _taskToolErrorJson(
        code: 'workspace_io_failure',
        message: e.toString(),
        disposition: TaskToolErrorDisposition.retryable,
      );
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
  "userQuestion": {"question":"only when blocked","reason":"why this blocks","defaultIfUnanswered":"reasonable default if any","riskOfAssuming":"risk if the default is wrong","kind":"blocking|preference|advisory"},
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
      "artifacts": [{"path": "...", "description": "..."}],
      "gates": [{"id": "artifact_exists", "required": true, "scope": "step", "params": {"paths": ["..."]}, "description": "..."}]
    }
  ],
  "memorySummary": "optional updated memory summary"
}

Gate catalog:
${_taskGateCatalogPrompt()}

Reason for replan:
$reason

Completed or skipped steps to preserve:
${_encoder.convert(completed.map(ModelJson.encode).toList())}

Current task:
${_encoder.convert(ModelJson.encode(snapshot))}
''',
      );
      replacement = _stepsFromJson(json['steps'], snapshot.id);
      if (replacement.isEmpty) {
        replacement = [_fallbackExecutionStep(snapshot.id, snapshot.goal)];
      }
    } on TaskCancelledException {
      rethrow;
    } on ChatTransportException {
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
    final rawUserQuestion = json['userQuestion'] ?? json['user_question'];
    final agentQuestion = AgentQuestion.parse(rawUserQuestion);
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
      userQuestion: agentQuestion?.displayText,
      agentQuestion: agentQuestion,
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

  String _buildStepPrompt(
    TaskDocument task,
    TaskStep step,
    WorkspaceAttachment workspace,
  ) {
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
${_encoder.convert(task.steps.map(ModelJson.encode).toList())}

Current step:
${_encoder.convert(ModelJson.encode(step))}

Available artifact inputs:
$availableArtifacts

Step tool permissions:
${_stepToolPermissionText(task, step, workspace)}

Previous run summaries:
${previousRuns.trim().isEmpty ? 'None yet.' : previousRuns}

When finished, call finish_task_step with this result object. If finish_task_step is unavailable, return only JSON:
{
  "status": "completed|blocked|needs_replan|failed",
  "summary": "...",
  "memoryUpdate": "...",
  "artifacts": [{"path": "...", "description": "..."}],
  "userQuestion": {"question":"only when blocked","reason":"why this blocks","defaultIfUnanswered":"reasonable default if any","riskOfAssuming":"risk if the default is wrong","kind":"blocking|preference|advisory"},
  "replanRequest": "only when needs_replan",
  "error": "only when failed"
}
''';
  }

  String _taskGateCatalogPrompt() {
    return '''
Choose only these gate ids. Gates are checked by the task runner, not by the executor.
- artifact_exists: params {"paths": ["relative/path"]}
- artifact_nonempty: params {"paths": ["relative/path"]}
- command_passes: params {"command": "dart test", "working_directory": "."}
- no_tool_errors: params {} (fails unresolved fatal tool errors; recoverable guard denials are recorded as advisory details)
- no_failed_commands: params {}
- content_contains: params {"path": "relative/path", "mustContain": ["..."]}
- content_not_contains: params {"path": "relative/path", "mustNotContain": ["TODO", "FIXME", "[...]"]}
- json_valid: params {"path": "relative/path"}
- yaml_valid: params {"path": "relative/path"}
- xml_valid: params {"path": "relative/path"}
- markdown_links_valid: params {"path": "relative/path"}
- schema_matches: params {"path": "relative/path", "requiredKeys": ["..."], "types": {"key": "string|number|boolean|array|object"}}
- workspace_clean_enough: usually advisory unless the user requires clean git state
- human_approval: use for risky irreversible or subjective acceptance checkpoints
- model_review: subjective review; advisory by default for creative/research work
For coding tasks, prefer no_tool_errors, no_failed_commands, and command_passes when a likely test/analyze/build command is inferable.
For declared artifact outputs, use artifact_exists and artifact_nonempty.
''';
  }

  String _stepToolPermissionText(
    TaskDocument task,
    TaskStep step,
    WorkspaceAttachment workspace,
  ) {
    final terminalStatus = workspace.commandExecutionApproved
        ? 'Terminal commands are enabled for this chat.'
        : 'Terminal commands are disabled for this chat until the user enables them from the workspace chip.';
    final allowedCommands = _allowedCommandsForStep(task, step);
    final availableTools = (_allowedToolIdsForStep(
      step,
      allowedCommands,
    ).toList()..sort()).join(', ');
    final stepPolicy = step.mayEditFiles
        ? 'This step may edit files after any required user approval. Mutating workspace tools and terminal commands may be available.'
        : allowedCommands.isEmpty
        ? 'This is a read-only step. It may read workspace files and create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, but it must not overwrite existing files, edit source files, rename paths, delete paths, or run terminal commands.'
        : 'This is a read-only step. It may read workspace files, create only this step\'s declared task-owned artifact files under `.agent/tasks/${task.id}/`, and run only the whitelisted verification terminal commands listed below. It must not overwrite existing files, edit source files, rename paths, delete paths, or run any other terminal command.';
    final whitelist = allowedCommands.isEmpty
        ? ''
        : '\n- Whitelisted terminal commands for this step: ${_encoder.convert([
            for (final item in allowedCommands) {'command': item.command, 'working_directory': item.workingDirectory},
          ])}.';
    return '''
- $terminalStatus
- $stepPolicy
- Tools exposed to this step: $availableTools.
$whitelist
'''
        .trim();
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
    required String? projectId,
    List<TaskGate> requiredGates = const [],
    required DateTime now,
  }) {
    final steps = _stepsFromJson(json['steps'], taskId);
    final safeSteps = steps.isEmpty
        ? [_fallbackExecutionStep(taskId, originalPrompt)]
        : steps;
    final gates = [
      ..._gatesFromJson(json['gates'], fallbackScope: 'task', taskId: taskId),
      ...requiredGates,
      ..._defaultTaskGates(safeSteps, originalPrompt),
    ];
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
      gates: _dedupeGates(gates),
      steps: safeSteps,
      status: TaskStatus.paused,
      currentStepId: _nextStepId(safeSteps),
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      projectId: projectId,
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
      gates: _dedupeGates(candidate.gates),
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
      final artifacts = _artifactsFromJson(map['artifacts'], uniqueId)
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
          .toList();
      final gates = [
        ..._gatesFromJson(map['gates'], fallbackScope: 'step', taskId: taskId),
      ];
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
            artifacts: artifacts,
            gates: _dedupeGates(gates),
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
          final artifact = ModelJson.decode<TaskArtifact>(raw);
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

  List<TaskGate> _gatesFromJson(
    Object? value, {
    required String fallbackScope,
    String? taskId,
  }) {
    if (value is! List) return const [];
    final gates = <TaskGate>[];
    for (final raw in value.whereType<Map>()) {
      final gate = ModelJson.decode<TaskGate>(raw);
      final id = gate.id.trim();
      gates.add(
        TaskGate(
          id: id,
          required: gate.required,
          scope: gate.scope.trim().isEmpty ? fallbackScope : gate.scope,
          params: jsonMap(_replaceTaskIdPlaceholder(gate.params, taskId)),
          description: gate.description,
        ),
      );
    }
    return gates;
  }

  Object? _replaceTaskIdPlaceholder(Object? value, String? taskId) {
    if (taskId == null) return value;
    if (value is String) return value.replaceAll('{{task_id}}', taskId);
    if (value is List) {
      return value
          .map((item) => _replaceTaskIdPlaceholder(item, taskId))
          .toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _replaceTaskIdPlaceholder(entry.value, taskId),
      };
    }
    return value;
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
        description: 'Declared artifacts must be non-empty.',
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
    required String? projectId,
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

  TaskDocument _fallbackProjectBoundedTask({
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
                  stepId: 'execute_project_task',
                ),
              )
              .toList();
    final successCriteria = planningContext.doneCriteria.isEmpty
        ? ['Complete the selected bounded Project task.']
        : planningContext.doneCriteria;
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
        'Report what was completed and what remains.',
      ],
      mayEditFiles: true,
      artifacts: artifactPaths,
      status: TaskStepStatus.pending,
    );
    return TaskDocument(
      id: taskId,
      title: _titleFromPrompt(planningContext.projectTaskObjective),
      originalPrompt: userPrompt,
      goal: planningContext.projectTaskObjective,
      constraints: [
        'Stay within the attached workspace.',
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

  _StepExecutionStatus _parseStepExecutionStatus(Object? value) {
    final raw = value?.toString().trim().toLowerCase().replaceAll('-', '_');
    return switch (raw) {
      'blocked' => _StepExecutionStatus.blocked,
      'needs_replan' || 'replan' => _StepExecutionStatus.needsReplan,
      'failed' || 'failure' => _StepExecutionStatus.failed,
      _ => _StepExecutionStatus.completed,
    };
  }

  TaskToolError? _toolErrorInfo(Map<String, dynamic>? result) {
    if (result == null) return null;
    return taskToolErrorFromResult(result);
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
        'command:${path.normalize(jsonString(arguments['working_directory'] ?? arguments['workingDirectory'], fallback: '.'))}:${_commandTextFromParts(jsonString(arguments['command']), jsonStringList(arguments['args']))}',
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

    if (toolName == 'run_command') {
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

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }
}

@MappableClass(generateMethods: GenerateMethods.encode, ignoreNull: true)
class WorkspaceMetadata with WorkspaceMetadataMappable {
  final String? workspaceName;
  final List<String> rootFiles;
  final bool gitAvailable;
  final bool commandExecutionApproved;
  final List<String> existingTaskIds;

  const WorkspaceMetadata({
    this.workspaceName,
    this.rootFiles = const [],
    this.gitAvailable = false,
    this.commandExecutionApproved = false,
    this.existingTaskIds = const [],
  });
}

enum _StepExecutionStatus { completed, blocked, needsReplan, failed }

class _StepExecutionOutput {
  final _StepExecutionStatus status;
  final TaskRunStatus runStatus;
  final String summary;
  final String memoryUpdate;
  final List<TaskArtifact> artifacts;
  final List<TaskToolCallRecord> toolCalls;
  final List<TaskGateResult> gateResults;
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
      userQuestion: resolve(userQuestion, this.userQuestion),
      agentQuestion: resolve(agentQuestion, this.agentQuestion),
      replanRequest: resolve(replanRequest, this.replanRequest),
      error: resolve(error, this.error),
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
Do not ask blocking questions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default and continue.
Ask the user only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
Choose completion gates from the provided gate catalog when observable evidence should be required before a step or task can complete.
Use model_review only for subjective creative/research judgment; use deterministic gates whenever possible.
Read-only steps may create new task-owned artifact files under `.agent/tasks/<taskId>/`.
Declare an artifact only on the step that will actually create it.
Do not split broad "explore" and "analyze" work into separate steps when the exploration exists only to support the analysis.
Mark mayEditFiles true only when a step may edit existing files, write outside the task folder, rename paths, delete paths, or run terminal commands beyond exact commands declared in required command_passes gates.
A read-only step may include required command_passes gates for non-mutating verification commands; the runner will expose only those exact commands.
If the request involves opaque or binary documents such as .odt, .docx, .pdf, .xlsx, or archives, mark inspection/extraction steps mayEditFiles true when terminal commands may be needed and commandExecutionApproved is true in workspace metadata.
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
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Only return status "blocked" with userQuestion for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
You may read artifacts from completed prior steps and any artifact already created during the current step.
Write and report only artifacts declared on the current step.
If the current step needs a different artifact path, return status "needs_replan" instead of writing it.
If the current step is read-only, you may create only the current step's declared task-owned artifact files under `.agent/tasks/<taskId>/`, and you may run only whitelisted verification terminal commands exposed for the step. You must not overwrite existing files, edit source files, rename paths, delete paths, or try to use other terminal commands as a workaround.
If a later step is responsible for writing a report or changing files, leave that work for the later step.
If the current plan is wrong or missing necessary follow-up work, return status "needs_replan" with a concrete replanRequest.
If user input is truly required, return status "blocked" with userQuestion.
When done, call finish_task_step with the requested result object.
If finish_task_step is unavailable, return only the requested JSON object.
''';

const String _replannerSystemInstruction = '''
You replan unfinished work for a linear long-horizon task.
Preserve completed and skipped steps.
Rewrite only unfinished work into a short, concrete sequence.
Do not ask blocking questions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default and continue.
Ask the user only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
Choose completion gates from the provided gate catalog when observable evidence should be required before a step or task can complete.
Use model_review only for subjective creative/research judgment; use deterministic gates whenever possible.
Read-only steps may create new task-owned artifact files under `.agent/tasks/<taskId>/`.
Declare an artifact only on the step that will actually create it.
Do not split broad "explore" and "analyze" work into separate steps when the exploration exists only to support the analysis.
Mark mayEditFiles true only when a step may edit existing files, write outside the task folder, rename paths, delete paths, or run terminal commands beyond exact commands declared in required command_passes gates.
A read-only step may include required command_passes gates for non-mutating verification commands; the runner will expose only those exact commands.
If unfinished work involves opaque or binary documents such as .odt, .docx, .pdf, .xlsx, or archives, mark inspection/extraction steps mayEditFiles true when terminal commands may be needed and commandExecutionApproved is true in workspace metadata.
Do not include review, retry, validation, terminal policy, or approval policy fields.
Return only valid JSON.
''';
