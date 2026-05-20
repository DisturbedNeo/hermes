import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/job_system/job_json.dart';
import 'package:hermes/core/services/job_system/job_model_output.dart';
import 'package:hermes/core/services/job_system/job_storage_service.dart';
import 'package:hermes/core/services/job_system/job_summary.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

typedef JobCancelRegistration = void Function();
typedef JobCancelCallback = FutureOr<void> Function();

class JobCancellationToken {
  final List<JobCancelCallback> _callbacks = [];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void throwIfCancelled() {
    if (_isCancelled) throw const JobCancelledException();
  }

  JobCancelRegistration onCancel(JobCancelCallback callback) {
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
    final callbacks = List<JobCancelCallback>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      await callback();
    }
  }
}

class JobCancelledException implements Exception {
  const JobCancelledException();

  @override
  String toString() => 'Job execution cancelled';
}

class _StreamingJobToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

const int _maxConsecutiveRepeatedToolCalls = 3;

const Set<String> _readOnlyJobToolIds = {
  'calculator',
  'list_directory',
  'read_file',
  'search_files',
  'write_file',
};

const Set<String> _mutatingJobToolIds = {
  'write_file',
  'patch_file',
  'create_directory',
  'rename_path',
  'delete_path',
  'run_command',
};

class JobService {
  JobService({
    required ToolService toolService,
    JobStorageService? storage,
    WorkspaceSandbox? sandbox,
  }) : _toolService = toolService,
       _storage = storage ?? JobStorageService(),
       _sandbox = sandbox ?? WorkspaceSandbox();

  final ToolService _toolService;
  final JobStorageService _storage;
  final WorkspaceSandbox _sandbox;
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  JobStorageService get storage => _storage;

  Future<List<JobSummary>> listJobs(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.listJobs(workspace.rootPath, chatSessionId: chatSessionId);
  }

  Future<JobDocument?> loadLatestJob(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.loadLatestJob(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<JobDocument?> loadJob(
    WorkspaceAttachment workspace,
    String jobId, {
    String? chatSessionId,
  }) {
    return _storage.loadJob(
      workspace.rootPath,
      jobId,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteJobsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _storage.deleteJobsForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatJobs(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _storage.deleteOrphanedChatJobs(
      workspace.rootPath,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<JobDocument> updateJobChatSessionId({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
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

  Future<JobDocument> recoverJob({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
  }) async {
    if (snapshot.status != JobStatus.running) return snapshot;
    final now = DateTime.now();
    final steps = snapshot.steps.map((step) {
      if (step.status == JobStepStatus.running) {
        return step.copyWith(status: JobStepStatus.blocked);
      }
      return step;
    }).toList();
    final recovered = snapshot.copyWith(
      status: JobStatus.blocked,
      steps: steps,
      updatedAt: now,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        'Recovered an interrupted job. Review the current step before continuing.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, recovered);
    return recovered;
  }

  String encodeJob(JobDocument job) => '${_encoder.convert(job.toJson())}\n';

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

  Future<RefinedJobBrief> refineTaskBrief({
    required ChatClient client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
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
Refine this request into a concise brief for a long-horizon job planner.

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
      return _normaliseBrief(RefinedJobBrief.fromJson(json), userPrompt);
    } on JobCancelledException {
      rethrow;
    } catch (_) {
      return _fallbackBrief(userPrompt);
    }
  }

  Future<JobDocument> createJob({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final jobId = _newJobId(userPrompt);
    final metadata = await _collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );

    JobDocument job;
    try {
      final json = await _completeJson(
        client: client,
        system: '$baseSystemPrompt\n\n$_plannerSystemInstruction',
        label: 'Job Planner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Create a linear multi-step job plan.

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
      "artifacts": [{"path": ".agent/jobs/$jobId/output.md", "description": "..."}]
    }
  ]
}

Use this exact job id when referencing job-owned artifacts: $jobId
Prefer 2-6 concrete steps. Artifacts are optional.

Workspace metadata:
${_encoder.convert(metadata.toJson())}

Request:
$userPrompt
''',
      );
      job = _jobFromPlannerJson(
        json,
        jobId: jobId,
        originalPrompt: userPrompt,
        chatSessionId: chatSessionId,
        now: now,
      );
    } on JobCancelledException {
      rethrow;
    } catch (_) {
      job = _fallbackJob(
        jobId: jobId,
        userPrompt: userPrompt,
        chatSessionId: chatSessionId,
        now: now,
      );
    }

    await _storage.saveSnapshot(workspace.rootPath, job);
    return job;
  }

  Future<JobDocument> updateJobPlan({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
    required String rawJson,
  }) async {
    final parsed = JobDocument.fromJson(JobJson.parseObject(rawJson));
    final now = DateTime.now();
    final normalised = _normaliseEditedJob(
      parsed.copyWith(id: snapshot.id, chatSessionId: snapshot.chatSessionId),
      snapshot,
      now,
    );
    await _storage.saveSnapshot(workspace.rootPath, normalised);
    return normalised;
  }

  Future<JobDocument> runNextStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    var working = await recoverJob(workspace: workspace, snapshot: snapshot);
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
        step.status != JobStepStatus.approved) {
      final blocked =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: JobStepStatus.blocked),
          ).copyWith(
            status: JobStatus.blocked,
            currentStepId: step.id,
            pendingApproval: PendingJobApproval(
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
    final run = JobRun(
      runId: 'run_${uuid.v7()}',
      stepId: step.id,
      status: JobRunStatus.running,
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
          step.copyWith(status: JobStepStatus.running),
        ).copyWith(
          status: JobStatus.running,
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
        job: working,
        step: step,
        run: run,
        baseSystemPrompt: baseSystemPrompt,
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
    } on JobCancelledException catch (e) {
      final cancelledAt = DateTime.now();
      final cancelledRun = run.copyWith(
        status: JobRunStatus.cancelled,
        completedAt: cancelledAt,
        summary: 'Step cancelled by the user.',
        error: e.toString(),
      );
      working = _replaceLastRun(working, cancelledRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: JobStepStatus.pending),
          ).copyWith(
            status: JobStatus.paused,
            currentStepId: step.id,
            pendingApproval: null,
            pendingQuestion: null,
            updatedAt: cancelledAt,
          );
      await _storage.saveSnapshot(workspace.rootPath, working);
      return working;
    } catch (e) {
      final failedRun = run.copyWith(
        status: JobRunStatus.failed,
        completedAt: DateTime.now(),
        summary: 'Step failed: $e',
        error: e.toString(),
      );
      working = _replaceLastRun(working, failedRun);
      working =
          _replaceStep(
            working,
            step.id,
            step.copyWith(status: JobStepStatus.failed),
          ).copyWith(
            status: JobStatus.failed,
            currentStepId: step.id,
            updatedAt: DateTime.now(),
          );
      await _storage.saveSnapshot(workspace.rootPath, working);
      return working;
    }
  }

  Future<JobDocument> approvePendingStep({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
  }) async {
    final approval = snapshot.pendingApproval;
    if (approval == null) return snapshot;
    final step = snapshot.stepById(approval.stepId);
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: JobStepStatus.approved),
        ).copyWith(
          status: JobStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          updatedAt: DateTime.now(),
        );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobDocument> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: JobStepStatus.pending),
        ).copyWith(
          status: JobStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          pendingQuestion: null,
          updatedAt: DateTime.now(),
        );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobDocument> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final now = DateTime.now();
    final updatedStep = step.copyWith(status: JobStepStatus.skipped);
    var updated = _replaceStep(snapshot, step.id, updatedStep);
    updated = _advanceAfterStep(updated, now).copyWith(
      runs: [
        ...updated.runs,
        JobRun(
          runId: 'run_${uuid.v7()}',
          stepId: step.id,
          status: JobRunStatus.skipped,
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

  Future<JobDocument> stopJob({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      status: JobStatus.cancelled,
      currentStepId: null,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: now,
      updatedAt: now,
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
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
                status: JobStepStatus.pending,
              ) ??
              JobStep(
                id: question.stepId,
                title: question.stepId,
                objective: '',
                instructions: const [],
                mayEditFiles: false,
                artifacts: const [],
                status: JobStepStatus.pending,
              ),
        ).copyWith(
          status: JobStatus.paused,
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

  Future<JobDocument> replanUnfinished({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
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
      existingJobIds: (await _storage.listJobs(
        workspace.rootPath,
        chatSessionId: chatSessionId,
      )).map((job) => job.id).toList(),
    );
  }

  Future<_StepExecutionOutput> _executeStep({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobDocument job,
    required JobStep step,
    required JobRun run,
    required String baseSystemPrompt,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) async {
    final allowedToolIds = _allowedToolIdsForStep(step);
    final toolDefs = _toolService.getToolDefinitions(
      ids: allowedToolIds.toList(),
      includeWorkspaceTools: true,
    );
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: baseSystemPrompt),
      const ChatMessage(role: 'system', content: _executorSystemInstruction),
      ChatMessage(role: 'user', content: _buildStepPrompt(job, step)),
    ];
    final context = WorkspaceToolContext(workspace: workspace);
    final toolCalls = <JobToolCallRecord>[];
    var finalText = '';
    var finalContent = '';
    _StepExecutionOutput? forcedOutput;
    String? previousToolKey;
    var consecutiveRepeatCount = 0;

    while (true) {
      cancellationToken?.throwIfCancelled();
      final completion = await _completeChatForJob(
        client: client,
        label: 'Step Executor: ${step.title}',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        messages: messages,
        extraParams: ToolCaller.buildExtraParams(
          addGenerationPrompt: true,
          toolDefs: toolDefs,
        ),
      );

      cancellationToken?.throwIfCancelled();
      finalContent = completion.content.trim();
      finalText = [
        if (completion.reasoning.trim().isNotEmpty)
          'Reasoning summary:\n${completion.reasoning.trim()}',
        if (finalContent.isNotEmpty) finalContent,
      ].join('\n\n').trim();

      if (completion.toolCalls.isEmpty) break;

      if (_isStepResultJson(finalContent)) {
        for (var i = 0; i < completion.toolCalls.length; i++) {
          _emitJobModelOutput(
            onModelOutput,
            JobModelOutputEvent(
              type: JobModelOutputEventType.toolResult,
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
                  'arguments': JobJson.decodeJsonOrString(
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
        final args = JobJson.decodeJsonOrString(call.arguments);
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

        final resultJson = await _executeJobToolCall(
          call: call,
          job: job,
          step: step,
          allowedToolIds: allowedToolIds,
          context: context,
          blockedReason: loopGuardReason,
        );
        cancellationToken?.throwIfCancelled();
        final error = _toolError(resultJson);
        toolCalls.add(
          JobToolCallRecord(
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
        _emitJobModelOutput(
          onModelOutput,
          JobModelOutputEvent(
            type: JobModelOutputEventType.toolResult,
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
          forcedOutput = _parseStepOutput(finalContent, job, step, toolCalls);
        } else {
          forcedOutput = _StepExecutionOutput(
            status: _StepExecutionStatus.failed,
            runStatus: JobRunStatus.failed,
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
      job.id,
      '${step.id}-${run.runId}.md',
      finalText,
    );

    return forcedOutput ??
        _parseStepOutput(
          finalContent.isEmpty ? finalText : finalContent,
          job,
          step,
          toolCalls,
        );
  }

  Set<String> _allowedToolIdsForStep(JobStep step) {
    if (!step.mayEditFiles) return _readOnlyJobToolIds;
    return {..._readOnlyJobToolIds, ..._mutatingJobToolIds};
  }

  Future<String> _executeJobToolCall({
    required ChatCompletionToolCall call,
    required JobDocument job,
    required JobStep step,
    required Set<String> allowedToolIds,
    required WorkspaceToolContext context,
    required String? blockedReason,
  }) async {
    if (blockedReason != null) {
      return jsonEncode({
        'error': 'Tool call skipped by job runner.',
        'reason': blockedReason,
      });
    }

    if (!allowedToolIds.contains(call.name)) {
      return jsonEncode({
        'error': 'Tool is not available for this job step.',
        'tool': call.name,
        'mayEditFiles': step.mayEditFiles,
        'availableTools': allowedToolIds.toList()..sort(),
        'reason': step.mayEditFiles
            ? 'The tool was not exposed to the job runner.'
            : 'This read-only step can read files and create new job-owned artifact files, but cannot edit source files, overwrite files, run terminal commands, rename paths, or delete paths.',
      });
    }

    if (!step.mayEditFiles && call.name == 'write_file') {
      return _executeReadOnlyArtifactWrite(
        call: call,
        job: job,
        step: step,
        context: context,
      );
    }
    if (step.mayEditFiles && call.name == 'write_file') {
      final artifactWriteError = await _jobArtifactWriteError(
        call: call,
        job: job,
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
    required JobDocument job,
    required JobStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = JobJson.decodeJsonOrString(call.arguments);
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
      if (!_isInsideJobDirectory(resolved.relativePath, job.id)) {
        return jsonEncode({
          'error': 'Read-only steps may only create job-owned artifact files.',
          'path': resolved.relativePath,
          'allowedPrefix': path.join('.agent', 'jobs', job.id),
        });
      }
      final allowedPaths = _declaredCurrentStepArtifactPaths(job.id, step);
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

  Future<String?> _jobArtifactWriteError({
    required ChatCompletionToolCall call,
    required JobDocument job,
    required JobStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = JobJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) return null;
      final rawPath = decoded['path'];
      if (rawPath is! String || rawPath.trim().isEmpty) return null;

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      final artifactPath = path.normalize(resolved.relativePath);
      if (!_isInsideJobDirectory(artifactPath, job.id)) return null;

      final allowedPaths = _declaredCurrentStepArtifactPaths(job.id, step);
      if (allowedPaths.contains(artifactPath)) return null;

      return jsonEncode({
        'error':
            'Job steps may only create artifacts declared on the current step.',
        'path': resolved.relativePath,
        'allowedArtifactPaths': allowedPaths.toList()..sort(),
      });
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  bool _isInsideJobDirectory(String relativePath, String jobId) {
    final segments = path.split(path.normalize(relativePath));
    return segments.length > 3 &&
        segments[0] == '.agent' &&
        segments[1] == 'jobs' &&
        segments[2] == jobId;
  }

  Set<String> _declaredCurrentStepArtifactPaths(String jobId, JobStep step) {
    return {
          for (final artifact in step.artifacts)
            if (artifact.path.trim().isNotEmpty)
              path.normalize(artifact.path.trim()),
        }
        .where((artifactPath) => _isInsideJobDirectory(artifactPath, jobId))
        .toSet();
  }

  List<JobArtifact> _filterCurrentStepArtifacts(
    String jobId,
    JobStep step,
    List<JobArtifact> artifacts,
  ) {
    final allowedPaths = _declaredCurrentStepArtifactPaths(jobId, step);
    final seen = <String>{};
    final filtered = <JobArtifact>[];
    for (final artifact in artifacts) {
      final normalizedPath = path.normalize(artifact.path.trim());
      if (!allowedPaths.contains(normalizedPath) || !seen.add(normalizedPath)) {
        continue;
      }
      filtered.add(
        JobArtifact(
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
    required JobStep step,
    required List<ChatMessage> messages,
    required String reason,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) {
    return _completeChatForJob(
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
The job runner has stopped tool use for this step.

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
    );
  }

  bool _isStepResultJson(String value) {
    final json = JobJson.tryParseObject(value);
    if (json == null) return false;
    final rawStatus = json['status']?.toString().trim().toLowerCase();
    return rawStatus == 'completed' ||
        rawStatus == 'blocked' ||
        rawStatus == 'needs_replan' ||
        rawStatus == 'failed';
  }

  String _toolCallKey(ChatCompletionToolCall call) {
    final decoded = JobJson.decodeJsonOrString(call.arguments);
    final args = decoded is String ? decoded.trim() : _encoder.convert(decoded);
    return '${call.name}:$args';
  }

  Future<JobDocument> _replanUnfinished({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobDocument snapshot,
    required String baseSystemPrompt,
    required String reason,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now();
    final completed = snapshot.steps
        .where(
          (step) =>
              step.status == JobStepStatus.completed ||
              step.status == JobStepStatus.skipped,
        )
        .toList();

    List<JobStep> replacement;
    try {
      final json = await _completeJson(
        client: client,
        system: '$baseSystemPrompt\n\n$_replannerSystemInstruction',
        label: 'Unfinished Work Replanner',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        user:
            '''
Rewrite only the unfinished steps for this job.

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

Current job:
${_encoder.convert(snapshot.toJson())}
''',
      );
      replacement = _stepsFromJson(json['steps'], snapshot.id);
      if (replacement.isEmpty) {
        replacement = [_fallbackExecutionStep(snapshot.id, snapshot.goal)];
      }
    } on JobCancelledException {
      rethrow;
    } catch (_) {
      replacement = [_fallbackExecutionStep(snapshot.id, snapshot.goal)];
    }

    final existingIds = completed.map((step) => step.id).toSet();
    replacement = [
      for (var i = 0; i < replacement.length; i++)
        _dedupeStepId(replacement[i], existingIds, i),
    ];

    final replanRun = JobRun(
      runId: 'run_${uuid.v7()}',
      stepId: snapshot.currentStepId ?? 'replan',
      status: JobRunStatus.replanned,
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
      status: currentStepId == null ? JobStatus.completed : JobStatus.paused,
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
    JobDocument job,
    JobStep step,
    List<JobToolCallRecord> toolCalls,
  ) {
    final json = JobJson.tryParseObject(raw);
    if (json == null) {
      return _StepExecutionOutput(
        status: _StepExecutionStatus.completed,
        runStatus: JobRunStatus.completed,
        summary: raw.trim().isEmpty ? 'Step completed.' : raw.trim(),
        memoryUpdate: raw.trim(),
        artifacts: const [],
        toolCalls: toolCalls,
      );
    }

    final status = _parseStepExecutionStatus(json['status']);
    final artifacts = _filterCurrentStepArtifacts(
      job.id,
      step,
      _artifactsFromJson(json['artifacts'], step.id),
    );
    final summary = _string(
      json['summary'],
      fallback: status == _StepExecutionStatus.completed
          ? 'Step completed.'
          : 'Step stopped.',
    );
    return _StepExecutionOutput(
      status: status,
      runStatus: switch (status) {
        _StepExecutionStatus.completed => JobRunStatus.completed,
        _StepExecutionStatus.blocked => JobRunStatus.blocked,
        _StepExecutionStatus.failed => JobRunStatus.failed,
        _StepExecutionStatus.needsReplan => JobRunStatus.needsReplan,
      },
      summary: summary,
      memoryUpdate: _string(json['memoryUpdate'] ?? json['memory_update']),
      artifacts: artifacts,
      userQuestion: _nullableString(
        json['userQuestion'] ?? json['user_question'],
      ),
      replanRequest: _nullableString(
        json['replanRequest'] ?? json['replan_request'],
      ),
      error: _nullableString(json['error']),
      toolCalls: toolCalls,
    );
  }

  JobDocument _completeStep(
    JobDocument snapshot,
    JobStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    final stepArtifacts = output.artifacts.isEmpty
        ? step.artifacts
        : output.artifacts;
    final updatedStep = step.copyWith(
      status: JobStepStatus.completed,
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

  JobDocument _blockStep(
    JobDocument snapshot,
    JobStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    return _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: JobStepStatus.blocked),
    ).copyWith(
      status: JobStatus.blocked,
      currentStepId: step.id,
      pendingQuestion: output.userQuestion?.trim().isNotEmpty == true
          ? PendingJobQuestion(
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

  JobDocument _failStep(
    JobDocument snapshot,
    JobStep step,
    _StepExecutionOutput output,
    DateTime now,
  ) {
    return _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: JobStepStatus.failed),
    ).copyWith(
      status: JobStatus.failed,
      currentStepId: step.id,
      memorySummary: _appendMemory(snapshot.memorySummary, output.summary),
      updatedAt: now,
    );
  }

  JobDocument _advanceAfterStep(JobDocument snapshot, DateTime now) {
    final currentStepId = _nextStepId(snapshot.steps);
    return snapshot.copyWith(
      status: currentStepId == null ? JobStatus.completed : JobStatus.paused,
      currentStepId: currentStepId,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: currentStepId == null ? now : null,
      updatedAt: now,
    );
  }

  JobDocument _markCompleted(JobDocument snapshot) {
    final now = DateTime.now();
    return snapshot.copyWith(
      status: JobStatus.completed,
      currentStepId: null,
      completedAt: now,
      updatedAt: now,
    );
  }

  JobDocument _replaceStep(JobDocument snapshot, String stepId, JobStep step) {
    final index = snapshot.steps.indexWhere((item) => item.id == stepId);
    if (index < 0) return snapshot;
    final steps = [...snapshot.steps];
    steps[index] = step;
    return snapshot.copyWith(steps: steps);
  }

  JobDocument _replaceLastRun(JobDocument snapshot, JobRun run) {
    if (snapshot.runs.isEmpty) return snapshot.copyWith(runs: [run]);
    final runs = [...snapshot.runs];
    runs[runs.length - 1] = run;
    return snapshot.copyWith(runs: runs);
  }

  String? _nextStepId(List<JobStep> steps) {
    for (final step in steps) {
      if (step.status == JobStepStatus.pending ||
          step.status == JobStepStatus.approved ||
          step.status == JobStepStatus.blocked ||
          step.status == JobStepStatus.failed) {
        return step.id;
      }
    }
    return null;
  }

  String _buildStepPrompt(JobDocument job, JobStep step) {
    final previousRuns = job.runs
        .where((run) => run.status != JobRunStatus.running)
        .map((run) => '- ${run.stepId}: ${run.summary}')
        .join('\n');
    final availableArtifacts = _buildAvailableArtifactInputs(job, step);
    return '''
Job goal:
${job.goal}

Original request:
${job.originalPrompt}

Constraints:
${job.constraints.map((item) => '- $item').join('\n')}

Success criteria:
${job.successCriteria.map((item) => '- $item').join('\n')}

Current memory:
${job.memorySummary.trim().isEmpty ? 'None yet.' : job.memorySummary}

Full plan:
${_encoder.convert(job.steps.map((item) => item.toJson()).toList())}

Current step:
${_encoder.convert(step.toJson())}

Available artifact inputs:
$availableArtifacts

Step tool permissions:
${step.mayEditFiles ? '- This step may edit files after any required user approval. Mutating workspace tools and terminal commands may be available.' : '- This is a read-only step. It may read workspace files and create only this step\'s declared job-owned artifact files under `.agent/jobs/${job.id}/`, but it must not overwrite existing files, edit source files, rename paths, delete paths, or run terminal commands.'}

Previous run summaries:
${previousRuns.trim().isEmpty ? 'None yet.' : previousRuns}

When finished, return only JSON:
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

  String _buildAvailableArtifactInputs(JobDocument job, JobStep step) {
    final currentIndex = job.steps.indexWhere((item) => item.id == step.id);
    final priorStepIds = <String>{};
    if (currentIndex > 0) {
      for (final priorStep in job.steps.take(currentIndex)) {
        if (priorStep.status == JobStepStatus.completed ||
            priorStep.status == JobStepStatus.skipped) {
          priorStepIds.add(priorStep.id);
        }
      }
    }

    final artifacts = <JobArtifact>[
      for (final run in job.runs)
        if (priorStepIds.contains(run.stepId)) ...run.artifacts,
      for (final priorStep in job.steps)
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
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) async {
    final completion = await _completeChatForJob(
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
    return JobJson.parseObject(text);
  }

  Future<ChatCompletionResponse> _completeChatForJob({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    JobModelOutputSink? onModelOutput,
    JobCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    _emitJobModelOutput(
      onModelOutput,
      JobModelOutputEvent(type: JobModelOutputEventType.start, label: label),
    );
    try {
      if (!client.supportsStreamingCancellation) {
        final completion = await client.completeChatStreamed(
          messages: messages,
          extraParams: extraParams,
          onToken: (token) => _emitJobModelToken(
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
      final toolCalls = <int, _StreamingJobToolCall>{};
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
        _emitJobModelToken(sink: onModelOutput, label: label, token: token);
        final contentToken = token.content;
        if (contentToken != null) content.write(contentToken);
        final reasoningToken = token.reasoning;
        if (reasoningToken != null) reasoning.write(reasoningToken);
        final tool = token.tool;
        if (tool != null) {
          final call = toolCalls.putIfAbsent(
            tool.index,
            () => _StreamingJobToolCall(),
          );
          if (tool.id != null) call.id = tool.id;
          if (tool.name != null) call.name = tool.name;
          if (tool.argumentsChunk != null) {
            call.arguments.write(tool.argumentsChunk);
          }
        }
      }

      sub = client
          .streamMessage(messages: messages, extraParams: extraParams)
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
        failIfNeeded(const JobCancelledException());
      });

      try {
        return await completer.future;
      } finally {
        unregister?.call();
      }
    } finally {
      _emitJobModelOutput(
        onModelOutput,
        JobModelOutputEvent(type: JobModelOutputEventType.done, label: label),
      );
    }
  }

  void _emitJobModelToken({
    required JobModelOutputSink? sink,
    required String label,
    required ChatToken token,
  }) {
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emitJobModelOutput(
        sink,
        JobModelOutputEvent(
          type: JobModelOutputEventType.content,
          label: label,
          text: content,
          token: token,
        ),
      );
    }
    final reasoning = token.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      _emitJobModelOutput(
        sink,
        JobModelOutputEvent(
          type: JobModelOutputEventType.reasoning,
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
        _emitJobModelOutput(
          sink,
          JobModelOutputEvent(
            type: JobModelOutputEventType.toolCall,
            label: label,
            text: text,
            token: token,
            toolIndex: tool.index,
          ),
        );
      }
    }
  }

  void _emitJobModelOutput(
    JobModelOutputSink? sink,
    JobModelOutputEvent event,
  ) {
    sink?.call(event);
  }

  JobDocument _jobFromPlannerJson(
    Map<String, dynamic> json, {
    required String jobId,
    required String originalPrompt,
    required String? chatSessionId,
    required DateTime now,
  }) {
    final steps = _stepsFromJson(json['steps'], jobId);
    final safeSteps = steps.isEmpty
        ? [_fallbackExecutionStep(jobId, originalPrompt)]
        : steps;
    return JobDocument(
      id: jobId,
      title: _string(json['title'], fallback: _titleFromPrompt(originalPrompt)),
      originalPrompt: originalPrompt,
      goal: _string(
        json['goal'] ?? json['objective'],
        fallback: originalPrompt,
      ),
      constraints: _stringList(json['constraints']),
      successCriteria: _stringList(
        json['successCriteria'] ?? json['success_criteria'],
      ),
      steps: safeSteps,
      status: JobStatus.paused,
      currentStepId: _nextStepId(safeSteps),
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      createdAt: now,
      updatedAt: now,
    );
  }

  JobDocument _normaliseEditedJob(
    JobDocument candidate,
    JobDocument original,
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
      schemaVersion: JobDocument.currentSchemaVersion,
      title: candidate.title.trim().isEmpty ? original.title : candidate.title,
      originalPrompt: candidate.originalPrompt.trim().isEmpty
          ? original.originalPrompt
          : candidate.originalPrompt,
      goal: candidate.goal.trim().isEmpty ? original.goal : candidate.goal,
      steps: steps,
      status: currentStepId == null ? JobStatus.completed : JobStatus.paused,
      currentStepId: currentStepId,
      createdAt: original.createdAt,
      updatedAt: now,
    );
  }

  List<JobStep> _stepsFromJson(Object? value, String jobId) {
    if (value is! List) return const [];
    final usedIds = <String>{};
    final steps = <JobStep>[];
    for (var i = 0; i < value.length; i++) {
      final raw = value[i];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final fallbackId = 'step_${i + 1}';
      final id = _safeId(_string(map['id'], fallback: fallbackId), fallbackId);
      final uniqueId = usedIds.add(id) ? id : '${id}_${i + 1}';
      steps.add(
        _normaliseStep(
          JobStep(
            id: uniqueId,
            title: _string(map['title'], fallback: 'Step ${i + 1}'),
            objective: _string(map['objective']),
            instructions: _stringList(map['instructions']),
            mayEditFiles: _bool(map['mayEditFiles'] ?? map['may_edit_files']),
            artifacts: _artifactsFromJson(map['artifacts'], uniqueId)
                .map(
                  (artifact) => artifact.path.contains('{{job_id}}')
                      ? JobArtifact(
                          path: artifact.path.replaceAll('{{job_id}}', jobId),
                          description: artifact.description,
                          stepId: artifact.stepId ?? uniqueId,
                          createdAt: artifact.createdAt,
                        )
                      : artifact,
                )
                .toList(),
            status: JobStepStatus.pending,
          ),
        ),
      );
    }
    return steps;
  }

  List<JobArtifact> _artifactsFromJson(Object? value, String stepId) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final artifact = JobArtifact.fromJson(Map<String, dynamic>.from(raw));
          return JobArtifact(
            path: artifact.path,
            description: artifact.description,
            stepId: artifact.stepId ?? stepId,
            createdAt: artifact.createdAt,
          );
        })
        .where((artifact) => artifact.path.trim().isNotEmpty)
        .toList();
  }

  JobStep _normaliseStep(JobStep step) {
    return step.copyWith(
      id: _safeId(step.id, 'step'),
      title: step.title.trim().isEmpty ? step.id : step.title,
      objective: step.objective.trim().isEmpty ? step.title : step.objective,
      instructions: step.instructions,
      status: switch (step.status) {
        JobStepStatus.running => JobStepStatus.pending,
        _ => step.status,
      },
    );
  }

  JobStep _dedupeStepId(JobStep step, Set<String> existingIds, int index) {
    if (existingIds.add(step.id)) return step;
    final next = '${step.id}_${index + 1}';
    existingIds.add(next);
    return step.copyWith(id: next);
  }

  RefinedJobBrief _normaliseBrief(RefinedJobBrief brief, String prompt) {
    return RefinedJobBrief(
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

  RefinedJobBrief _fallbackBrief(String prompt) {
    return RefinedJobBrief(
      title: _titleFromPrompt(prompt),
      goal: prompt,
      successCriteria: const ['Complete the requested task.'],
      assumptions: const ['Use the attached workspace as the source of truth.'],
    );
  }

  JobDocument _fallbackJob({
    required String jobId,
    required String userPrompt,
    required String? chatSessionId,
    required DateTime now,
  }) {
    final step = _fallbackExecutionStep(jobId, userPrompt);
    return JobDocument(
      id: jobId,
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      goal: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      successCriteria: const ['Complete the requested task.'],
      steps: [step],
      status: JobStatus.paused,
      currentStepId: step.id,
      memorySummary: '',
      runs: const [],
      chatSessionId: chatSessionId,
      createdAt: now,
      updatedAt: now,
    );
  }

  JobStep _fallbackExecutionStep(String jobId, String objective) {
    return JobStep(
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
        JobArtifact(
          path: '.agent/jobs/$jobId/job-output.md',
          description: 'Final job output',
          stepId: 'execute_task',
        ),
      ],
      status: JobStepStatus.pending,
    );
  }

  String _newJobId(String prompt) {
    final slug = _titleFromPrompt(prompt)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = slug.isEmpty ? 'job' : slug;
    return 'job_${prefix.length > 32 ? prefix.substring(0, 32) : prefix}_${uuid.v7().substring(0, 8)}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled job';
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
  final List<String> existingJobIds;

  const _WorkspaceMetadata({
    this.workspaceName,
    this.rootFiles = const [],
    this.gitAvailable = false,
    this.existingJobIds = const [],
  });

  Map<String, dynamic> toJson() => {
    if (workspaceName != null) 'workspaceName': workspaceName,
    'rootFiles': rootFiles,
    'gitAvailable': gitAvailable,
    'existingJobIds': existingJobIds,
  };
}

enum _StepExecutionStatus { completed, blocked, needsReplan, failed }

class _StepExecutionOutput {
  final _StepExecutionStatus status;
  final JobRunStatus runStatus;
  final String summary;
  final String memoryUpdate;
  final List<JobArtifact> artifacts;
  final List<JobToolCallRecord> toolCalls;
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
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final string = value.toString();
  return string.trim().isEmpty ? fallback : string;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final string = value.toString().trim();
  return string.isEmpty ? null : string;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalised = value.trim().toLowerCase();
    if (normalised == 'true' || normalised == 'yes' || normalised == '1') {
      return true;
    }
    if (normalised == 'false' || normalised == 'no' || normalised == '0') {
      return false;
    }
  }
  return fallback;
}

const String _refinerSystemInstruction = '''
You refine user requests for a long-horizon AI job runner.
Do not perform the task.
Prefer useful assumptions over broad questioning.
Ask at most three questions.
Return only valid JSON.
''';

const String _plannerSystemInstruction = '''
You create simple linear plans for long-horizon workspace jobs.
The plan should be small, clear, and robust.
Each step must be independently executable from the shared goal, plan, memory summary, and previous run summaries.
Read-only steps may create new job-owned artifact files under `.agent/jobs/<jobId>/`.
Declare an artifact only on the step that will actually create it.
Do not split broad "explore" and "analyze" work into separate steps when the exploration exists only to support the analysis.
Mark mayEditFiles true only when a step may edit existing files, write outside the job folder, rename paths, delete paths, or run terminal commands.
Keep research/design/planning/reporting-to-job-folder steps read-only when they only read files and create new job-owned artifacts.
Do not include review, retry, validation, terminal policy, or approval policy fields.
Return only valid JSON.
''';

const String _executorSystemInstruction = '''
You execute one step of a larger linear job.
Use the full plan and memory to keep long-horizon context.
Complete only the current step.
Do not perform future steps early.
Use tools only when needed. When you have enough information, stop using tools and return the requested JSON.
You may read artifacts from completed prior steps and any artifact already created during the current step.
Write and report only artifacts declared on the current step.
If the current step needs a different artifact path, return status "needs_replan" instead of writing it.
If the current step is read-only, you may create only the current step's declared job-owned artifact files under `.agent/jobs/<jobId>/`, but you must not overwrite existing files, edit source files, rename paths, delete paths, or try to use terminal commands as a workaround.
If a later step is responsible for writing a report or changing files, leave that work for the later step.
If the current plan is wrong or missing necessary follow-up work, return status "needs_replan" with a concrete replanRequest.
If user input is required, return status "blocked" with userQuestion.
When done, return only the requested JSON object.
''';

const String _replannerSystemInstruction = '''
You replan unfinished work for a linear long-horizon job.
Preserve completed and skipped steps.
Rewrite only unfinished work into a short, concrete sequence.
Read-only steps may create new job-owned artifact files under `.agent/jobs/<jobId>/`.
Declare an artifact only on the step that will actually create it.
Do not split broad "explore" and "analyze" work into separate steps when the exploration exists only to support the analysis.
Mark mayEditFiles true only when a step may edit existing files, write outside the job folder, rename paths, delete paths, or run terminal commands.
Do not include review, retry, validation, terminal policy, or approval policy fields.
Return only valid JSON.
''';
