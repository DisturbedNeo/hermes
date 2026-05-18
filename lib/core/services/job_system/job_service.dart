import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/job_system/job_model_output.dart';
import 'package:hermes/core/services/job_system/job_model_validator.dart';
import 'package:hermes/core/services/job_system/job_json.dart';
import 'package:hermes/core/services/job_system/job_phase_validator.dart';
import 'package:hermes/core/services/job_system/job_spec_validator.dart';
import 'package:hermes/core/services/job_system/job_storage_service.dart';
import 'package:hermes/core/services/job_system/job_summary.dart';
import 'package:hermes/core/services/job_system/job_template_registry.dart';
import 'package:hermes/core/services/job_system/job_tool_policy_resolver.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

class JobService {
  JobService({
    required ToolService toolService,
    JobStorageService? storage,
    WorkspaceSandbox? sandbox,
    JobTemplateRegistry? templateRegistry,
    List<PhaseValidator>? phaseValidators,
    JobSpecValidator? specValidator,
  }) : _toolService = toolService,
       _storage = storage ?? JobStorageService(),
       _sandbox = sandbox ?? WorkspaceSandbox(),
       _templateRegistry = templateRegistry ?? const JobTemplateRegistry(),
       _phaseValidators =
           phaseValidators ?? BuiltInPhaseValidators.deterministic,
       _specValidator = specValidator ?? const JobSpecValidator();

  final ToolService _toolService;
  final JobStorageService _storage;
  final WorkspaceSandbox _sandbox;
  final JobTemplateRegistry _templateRegistry;
  final List<PhaseValidator> _phaseValidators;
  final JobSpecValidator _specValidator;
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  JobStorageService get storage => _storage;

  JobToolPolicyResolver get _toolPolicyResolver => JobToolPolicyResolver(
    availableToolIds: _toolService
        .getToolDefinitions(includeWorkspaceTools: true)
        .map((tool) => tool.id)
        .toSet(),
  );

  Future<List<JobSummary>> listJobs(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.listJobs(workspace.rootPath, chatSessionId: chatSessionId);
  }

  Future<JobSnapshot?> loadLatestJob(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _storage.loadLatestJob(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<JobSnapshot?> loadJob(
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

  Future<JobSnapshot> updateJobChatSessionId({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.state.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      state: snapshot.state.copyWith(
        chatSessionId: chatSessionId,
        updatedAt: DateTime.now(),
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> recoverJob({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
  }) async {
    final result = await _recoverSnapshot(
      workspace: workspace,
      snapshot: snapshot,
    );
    return result.snapshot;
  }

  String encodeTaskBrief(TaskBrief brief) =>
      '${_encoder.convert(brief.toJson())}\n';

  String encodeJobSpec(JobSpec spec) => '${_encoder.convert(spec.toJson())}\n';

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

  Future<JobSnapshot> updateTaskBrief({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String rawJson,
  }) async {
    final now = DateTime.now();
    final parsed = TaskBrief.fromJson(JobJson.parseObject(rawJson)).copyWith(
      id: snapshot.taskBrief.id,
      createdAt: snapshot.taskBrief.createdAt,
      updatedAt: now,
      originalPrompt: snapshot.taskBrief.originalPrompt,
    );
    final updated = snapshot.copyWith(
      taskBrief: parsed,
      spec: snapshot.spec.copyWith(
        updatedAt: now,
        title: snapshot.spec.title.trim().isEmpty
            ? parsed.title
            : snapshot.spec.title,
      ),
      state: snapshot.state.copyWith(
        updatedAt: now,
        assumptions: parsed.assumptions,
        latestSummary: 'Task brief updated by the user.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> updateJobSpec({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String rawJson,
  }) async {
    final now = DateTime.now();
    final parsed = JobSpec.fromJson(JobJson.parseObject(rawJson)).copyWith(
      id: snapshot.spec.id,
      taskBriefId: snapshot.taskBrief.id,
      createdAt: snapshot.spec.createdAt,
      updatedAt: now,
    );
    final normalised = _normaliseSpec(
      parsed,
      snapshot.taskBrief,
      snapshot.spec.id,
      now,
    );
    final phases = _preserveCompletedPhaseStatuses(
      original: snapshot.spec.phases,
      updated: normalised.phases,
    );
    final nextPhaseId = _nextRunnablePhaseId(phases);
    final status = nextPhaseId == null ? JobStatus.completed : JobStatus.paused;
    final spec = normalised.copyWith(
      status: status,
      updatedAt: now,
      phases: phases,
    );
    _specValidator.throwIfInvalid(spec);
    final updated = snapshot.copyWith(
      spec: spec,
      state: snapshot.state.copyWith(
        status: status,
        currentPhaseId: nextPhaseId,
        completedAt: status == JobStatus.completed
            ? now
            : snapshot.state.completedAt,
        updatedAt: now,
        failedPhases: _retainExistingPhaseIds(
          snapshot.state.failedPhases,
          phases,
        ),
        latestSummary: 'Job spec updated by the user.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> replanRemaining({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    JobModelOutputSink? onModelOutput,
  }) async {
    return replanJob(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      scope: ReplanScope.remainingPhases,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> replanCurrentPhase({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    JobModelOutputSink? onModelOutput,
  }) async {
    return replanJob(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      scope: ReplanScope.currentPhase,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> replanEntireJob({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    JobModelOutputSink? onModelOutput,
  }) async {
    return replanJob(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      scope: ReplanScope.entireJob,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> replanJob({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    required ReplanScope scope,
    JobModelOutputSink? onModelOutput,
  }) async {
    return _buildReplannedSnapshot(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      scope: scope,
      persist: true,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> proposeReplanJob({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    required ReplanScope scope,
    JobModelOutputSink? onModelOutput,
  }) async {
    return _buildReplannedSnapshot(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      scope: scope,
      persist: false,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> applyReplanProposal({
    required WorkspaceAttachment workspace,
    required JobSnapshot current,
    required JobSnapshot proposal,
  }) async {
    if (proposal.spec.id != current.spec.id ||
        proposal.taskBrief.id != current.taskBrief.id ||
        proposal.state.jobId != current.state.jobId) {
      throw const FormatException(
        'Replan proposal does not match the active job.',
      );
    }
    _specValidator.throwIfInvalid(proposal.spec);
    await _storage.saveSnapshot(workspace.rootPath, proposal);
    return proposal;
  }

  Future<JobSnapshot> _buildReplannedSnapshot({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    required ReplanScope scope,
    required bool persist,
    JobModelOutputSink? onModelOutput,
  }) async {
    final now = DateTime.now();
    final currentPhase = _currentOrRetryablePhase(snapshot);
    if (scope == ReplanScope.currentPhase && currentPhase == null) {
      return snapshot;
    }

    final protectedIds = scope == ReplanScope.entireJob
        ? <String>{}
        : <String>{
            ...snapshot.state.completedPhases,
            ...snapshot.state.skippedPhases,
          };
    final metadata = await collectWorkspaceMetadata(
      workspace,
      chatSessionId: snapshot.state.chatSessionId,
    );
    final availableTools = _toolService
        .getToolDefinitions(includeWorkspaceTools: true)
        .map((tool) => tool.id)
        .toList();

    JobSpec candidate;
    try {
      candidate = await _completeValidatedJobSpec(
        client: client,
        system: '$baseSystemPrompt\n\n$_replannerSystemInstruction',
        user:
            '''
Update this job plan with replan scope: ${scope.wire}.

Return only JSON matching the JobSpec schema. Use camelCase field names.
Use this exact job id: ${snapshot.spec.id}
Use this exact taskBriefId: ${snapshot.taskBrief.id}
Only use available tool ids listed below.

Completed or skipped phase ids that must not be changed:
${_encoder.convert(protectedIds.toList()..sort())}

Current target phase:
${_encoder.convert(currentPhase?.toJson() ?? {})}

Scope rules:
${_replanScopeRules(scope)}

Available tools:
${_encoder.convert(availableTools)}

Workspace metadata:
${_encoder.convert(metadata.toJson())}

Task brief:
${_encoder.convert(snapshot.taskBrief.toJson())}

Current JobSpec:
${_encoder.convert(snapshot.spec.toJson())}

Current JobState:
${_encoder.convert(snapshot.state.toJson())}
''',
        taskBrief: snapshot.taskBrief,
        jobId: snapshot.spec.id,
        now: now,
        label: '${scope.label} Replanner',
        onModelOutput: onModelOutput,
      );
    } catch (_) {
      candidate = _fallbackJobSpec(
        taskBrief: snapshot.taskBrief,
        jobId: snapshot.spec.id,
        now: now,
        autonomy: snapshot.spec.autonomy,
      );
    }

    final normalised = _normaliseSpec(
      candidate.copyWith(
        id: snapshot.spec.id,
        taskBriefId: snapshot.taskBrief.id,
        createdAt: snapshot.spec.createdAt,
      ),
      snapshot.taskBrief,
      snapshot.spec.id,
      now,
    );
    final phases = _mergeReplannedPhases(
      snapshot: snapshot,
      candidate: normalised,
      scope: scope,
      currentPhase: currentPhase,
      protectedIds: protectedIds,
    );
    final nextPhaseId = _nextRunnablePhaseId(phases);
    final status = nextPhaseId == null ? JobStatus.completed : JobStatus.paused;
    final phaseIds = phases.map((phase) => phase.id).toSet();
    final resetState = scope == ReplanScope.entireJob;
    final spec = scope == ReplanScope.currentPhase
        ? snapshot.spec.copyWith(status: status, updatedAt: now, phases: phases)
        : normalised.copyWith(
            status: status,
            createdAt: snapshot.spec.createdAt,
            updatedAt: now,
            phases: phases,
          );
    final validationIssues = _specValidator.validate(spec);
    if (validationIssues.isNotEmpty) {
      final blocked = snapshot.copyWith(
        spec: spec.copyWith(status: JobStatus.blocked, updatedAt: now),
        state: snapshot.state.copyWith(
          status: JobStatus.blocked,
          currentPhaseId: currentPhase?.id ?? nextPhaseId,
          updatedAt: now,
          latestSummary:
              'Replan produced an invalid job spec: ${validationIssues.join('; ')}',
        ),
      );
      if (persist) {
        await _storage.saveSnapshot(workspace.rootPath, blocked);
      } else {
        throw FormatException(
          'Replan produced an invalid job spec: ${validationIssues.join('; ')}',
        );
      }
      return blocked;
    }
    final updated = snapshot.copyWith(
      spec: spec,
      state: snapshot.state.copyWith(
        status: status,
        currentPhaseId: nextPhaseId,
        completedAt: status == JobStatus.completed && !resetState ? now : null,
        updatedAt: now,
        completedPhases: resetState
            ? const []
            : _retainExistingPhaseIds(snapshot.state.completedPhases, phases),
        failedPhases: resetState
            ? const []
            : _retainExistingPhaseIds(
                scope == ReplanScope.currentPhase
                    ? snapshot.state.failedPhases.where(
                        (id) => id != currentPhase?.id,
                      )
                    : snapshot.state.failedPhases.where(protectedIds.contains),
                phases,
              ),
        skippedPhases: resetState
            ? const []
            : _retainExistingPhaseIds(snapshot.state.skippedPhases, phases),
        openQuestions: snapshot.state.openQuestions
            .where(
              (question) =>
                  question.phaseId == null ||
                  (phaseIds.contains(question.phaseId) &&
                      (scope != ReplanScope.currentPhase ||
                          question.phaseId != currentPhase?.id)),
            )
            .toList(),
        latestSummary: status == JobStatus.completed
            ? '${scope.label} replan produced no pending phases.'
            : '${scope.label} replanned. Next phase: $nextPhaseId.',
      ),
    );
    if (persist) {
      await _storage.saveSnapshot(workspace.rootPath, updated);
    }
    return updated;
  }

  Future<JobSnapshot> stopJob({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      spec: snapshot.spec.copyWith(
        status: JobStatus.cancelled,
        updatedAt: now,
        phases: snapshot.spec.phases
            .map(
              (phase) => phase.status == PhaseStatus.running
                  ? phase.copyWith(status: PhaseStatus.blocked)
                  : phase,
            )
            .toList(),
      ),
      state: snapshot.state.copyWith(
        status: JobStatus.cancelled,
        currentPhaseId: null,
        updatedAt: now,
        completedAt: now,
        latestSummary: 'Job stopped by the user.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> retryCurrentPhase({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
  }) async {
    final index = _currentOrRetryablePhaseIndex(snapshot);
    if (index < 0) return snapshot;

    final now = DateTime.now();
    final phase = snapshot.spec.phases[index];
    var updated = _replacePhase(
      snapshot,
      index,
      phase.copyWith(status: PhaseStatus.pending),
    );
    updated = updated.copyWith(
      spec: updated.spec.copyWith(status: JobStatus.paused, updatedAt: now),
      state: updated.state.copyWith(
        status: JobStatus.paused,
        currentPhaseId: phase.id,
        updatedAt: now,
        latestSummary: 'Phase ${phase.id} queued for retry.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> skipCurrentPhase({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
  }) async {
    final index = _currentOrRetryablePhaseIndex(snapshot);
    if (index < 0) return snapshot;

    final now = DateTime.now();
    final phase = snapshot.spec.phases[index];
    var updated = _replacePhase(
      snapshot,
      index,
      phase.copyWith(status: PhaseStatus.skipped),
    );
    final noPending = updated.spec.phases.every(
      (phase) =>
          phase.status == PhaseStatus.completed ||
          phase.status == PhaseStatus.skipped,
    );
    final status = noPending ? JobStatus.completed : JobStatus.paused;
    updated = updated.copyWith(
      spec: updated.spec.copyWith(status: status, updatedAt: now),
      state: updated.state.copyWith(
        status: status,
        currentPhaseId: noPending ? null : updated.state.currentPhaseId,
        completedAt: noPending ? now : updated.state.completedAt,
        updatedAt: now,
        skippedPhases: _withUnique(updated.state.skippedPhases, phase.id),
        latestSummary: 'Phase ${phase.id} skipped by the user.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String questionId,
    required String answer,
  }) async {
    final trimmed = answer.trim();
    if (trimmed.isEmpty) return snapshot;
    final now = DateTime.now();

    var matched = false;
    final questions = snapshot.state.openQuestions.map((question) {
      if (question.id != questionId) return question;
      matched = true;
      return OpenQuestion(
        id: question.id,
        phaseId: question.phaseId,
        question: question.question,
        required: question.required,
        reason: question.reason,
        status: OpenQuestionStatus.answered,
        answer: trimmed,
      );
    }).toList();

    if (!matched) {
      final briefQuestion = _briefQuestion(snapshot.taskBrief, questionId);
      if (briefQuestion != null) {
        questions.add(
          OpenQuestion(
            id: briefQuestion.id,
            question: briefQuestion.question,
            required: briefQuestion.required,
            reason: briefQuestion.impactIfUnanswered,
            status: OpenQuestionStatus.answered,
            answer: trimmed,
          ),
        );
      }
    }

    final briefQuestions = snapshot.taskBrief.clarifyingQuestions
        .map(
          (question) => question.id == questionId
              ? question.copyWith(answer: trimmed)
              : question,
        )
        .toList();

    final stillBlocked = questions.any(
      (question) =>
          question.required && question.status == OpenQuestionStatus.open,
    );
    final draft = snapshot.spec.status == JobStatus.draft;
    final status = stillBlocked
        ? JobStatus.blocked
        : draft
        ? JobStatus.draft
        : JobStatus.paused;
    final specStatus = draft ? JobStatus.draft : status;
    final updated = snapshot.copyWith(
      taskBrief: snapshot.taskBrief.copyWith(
        updatedAt: now,
        clarifyingQuestions: briefQuestions,
        assumptions: [...snapshot.taskBrief.assumptions, trimmed],
      ),
      spec: snapshot.spec.copyWith(status: specStatus, updatedAt: now),
      state: snapshot.state.copyWith(
        status: status,
        openQuestions: questions,
        assumptions: [...snapshot.state.assumptions, trimmed],
        updatedAt: now,
        latestSummary: stillBlocked
            ? 'Question answered. Required questions remain open.'
            : draft
            ? 'Required questions answered. Generate the job plan to continue.'
            : 'Question answered. Job can continue.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> dismissOpenQuestion({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String questionId,
  }) async {
    final briefQuestion = _briefQuestion(snapshot.taskBrief, questionId);
    if (briefQuestion?.required == true) return snapshot;

    final now = DateTime.now();
    var matched = false;
    final questions = snapshot.state.openQuestions.map((question) {
      if (question.id != questionId) return question;
      if (question.required) return question;
      matched = true;
      return OpenQuestion(
        id: question.id,
        phaseId: question.phaseId,
        question: question.question,
        required: question.required,
        reason: question.reason,
        status: OpenQuestionStatus.dismissed,
        answer: _questionDefaultAssumption(snapshot.taskBrief, question.id),
      );
    }).toList();

    if (!matched && briefQuestion != null) {
      questions.add(
        OpenQuestion(
          id: briefQuestion.id,
          question: briefQuestion.question,
          required: false,
          reason: briefQuestion.impactIfUnanswered,
          status: OpenQuestionStatus.dismissed,
          answer: briefQuestion.defaultAssumption,
        ),
      );
    }

    final assumption = _questionDefaultAssumption(
      snapshot.taskBrief,
      questionId,
    );
    final updated = snapshot.copyWith(
      taskBrief: snapshot.taskBrief.copyWith(
        updatedAt: now,
        assumptions: assumption == null
            ? snapshot.taskBrief.assumptions
            : _withUnique(snapshot.taskBrief.assumptions, assumption),
      ),
      state: snapshot.state.copyWith(
        openQuestions: questions,
        assumptions: assumption == null
            ? snapshot.state.assumptions
            : _withUnique(snapshot.state.assumptions, assumption),
        updatedAt: now,
        latestSummary: assumption == null
            ? 'Optional question dismissed.'
            : 'Optional question dismissed using its default assumption.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> dismissOptionalQuestions({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
  }) async {
    var updated = snapshot;
    final optionalQuestionIds = {
      for (final question in snapshot.state.openQuestions)
        if (!question.required && question.status == OpenQuestionStatus.open)
          question.id,
      for (final question in snapshot.taskBrief.clarifyingQuestions)
        if (!question.required && question.answer == null) question.id,
    };
    for (final questionId in optionalQuestionIds) {
      updated = await dismissOpenQuestion(
        workspace: workspace,
        snapshot: updated,
        questionId: questionId,
      );
    }
    return updated;
  }

  Future<JobSnapshot> resolveFileApproval({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String approvalId,
    required Set<String> approvedHunkIds,
  }) async {
    final approval = snapshot.state.pendingApprovals
        .where((approval) => approval.id == approvalId)
        .firstOrNull;
    if (approval == null || approval.status != 'pending') return snapshot;

    final now = DateTime.now();
    FileChangeSummary? appliedChange;
    if (approvedHunkIds.isNotEmpty) {
      appliedChange = await _applyApprovedFileHunks(
        workspace.rootPath,
        approval,
        approvedHunkIds,
      );
    }

    final resolvedApproval = approval.copyWith(
      status: approvedHunkIds.isEmpty
          ? 'rejected'
          : approvedHunkIds.length == approval.hunks.length
          ? 'applied'
          : 'partially_applied',
      updatedAt: now,
      hunks: [
        for (final hunk in approval.hunks)
          hunk.copyWith(
            status: approvedHunkIds.contains(hunk.id) ? 'applied' : 'rejected',
          ),
      ],
    );
    final approvals = snapshot.state.pendingApprovals
        .map(
          (existing) =>
              existing.id == approval.id ? resolvedApproval : existing,
        )
        .toList();
    final stillPending = approvals.any(
      (approval) => approval.status == 'pending',
    );
    final phases = snapshot.spec.phases
        .map(
          (phase) => phase.id == approval.phaseId && !stillPending
              ? phase.copyWith(status: PhaseStatus.pending)
              : phase,
        )
        .toList();
    final phaseRuns = appliedChange == null
        ? snapshot.state.phaseRuns
        : [
            for (final run in snapshot.state.phaseRuns)
              run.runId == approval.runId
                  ? run.copyWith(
                      fileChanges: [...run.fileChanges, appliedChange],
                      filesWritten: _approvalWritesFile(approval)
                          ? _withUnique(run.filesWritten, approval.path)
                          : run.filesWritten,
                      filesPatched: _approvalPatchesFile(approval)
                          ? _withUnique(run.filesPatched, approval.path)
                          : run.filesPatched,
                    )
                  : run,
          ];

    final status = stillPending ? JobStatus.blocked : JobStatus.paused;
    final updated = snapshot.copyWith(
      spec: snapshot.spec.copyWith(
        status: status,
        updatedAt: now,
        phases: phases,
      ),
      state: snapshot.state.copyWith(
        status: status,
        currentPhaseId: approval.phaseId,
        updatedAt: now,
        failedPhases: stillPending
            ? snapshot.state.failedPhases
            : snapshot.state.failedPhases
                  .where((phaseId) => phaseId != approval.phaseId)
                  .toList(),
        pendingApprovals: approvals,
        phaseRuns: phaseRuns,
        latestSummary: stillPending
            ? 'File approval resolved. Additional file approvals remain.'
            : 'File approvals resolved. Run phase ${approval.phaseId} again to continue.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<JobSnapshot> pauseAtCheckpoint({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required JobPhase phase,
  }) async {
    final now = DateTime.now();
    final updated = snapshot.copyWith(
      spec: snapshot.spec.copyWith(status: JobStatus.paused, updatedAt: now),
      state: snapshot.state.copyWith(
        status: JobStatus.paused,
        currentPhaseId: phase.id,
        updatedAt: now,
        latestSummary:
            'Paused at checkpoint before ${phase.id}: ${phase.title}.',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return updated;
  }

  Future<TaskBrief> refineTaskBrief({
    required ChatClient client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    JobModelOutputSink? onModelOutput,
  }) async {
    final now = DateTime.now();
    final jobId = _newJobId(userPrompt);
    final metadata = workspace == null || workspace.missing
        ? const WorkspaceMetadata()
        : await collectWorkspaceMetadata(workspace);
    final tools = _toolService.getToolDefinitions(
      includeWorkspaceTools: workspace != null && !workspace.missing,
    );

    final brief = await _refinePrompt(
      client: client,
      userPrompt: userPrompt,
      selectedMode: selectedMode,
      workspaceMetadata: metadata,
      availableTools: tools,
      fallbackId: 'task_brief_$jobId',
      now: now,
      onModelOutput: onModelOutput,
    );

    return _normaliseBrief(
      brief: brief,
      fallbackId: 'task_brief_$jobId',
      now: now,
      userPrompt: userPrompt,
      selectedMode: selectedMode,
      autonomyPreference: null,
    );
  }

  Future<JobSnapshot> createJob({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    AutonomyLevel? autonomyPreference,
    int? maxPhaseRetries,
    JobModelOutputSink? onModelOutput,
  }) async {
    final now = DateTime.now();
    final jobId = _newJobId(userPrompt);
    final metadata = await collectWorkspaceMetadata(
      workspace,
      chatSessionId: chatSessionId,
    );
    final tools = _toolService.getToolDefinitions(includeWorkspaceTools: true);

    var brief = await _refinePrompt(
      client: client,
      userPrompt: userPrompt,
      selectedMode: selectedMode,
      workspaceMetadata: metadata,
      availableTools: tools,
      fallbackId: 'task_brief_$jobId',
      now: now,
      onModelOutput: onModelOutput,
    );

    brief = _normaliseBrief(
      brief: brief,
      fallbackId: 'task_brief_$jobId',
      now: now,
      userPrompt: userPrompt,
      selectedMode: selectedMode,
      autonomyPreference: autonomyPreference,
    );

    if (_hasRequiredUnansweredQuestions(brief)) {
      final snapshot = _draftSnapshot(
        brief: brief,
        jobId: jobId,
        now: now,
        chatSessionId: chatSessionId,
        autonomy: autonomyPreference ?? brief.recommendedAutonomy,
      );
      await _storage.saveSnapshot(workspace.rootPath, snapshot);
      return snapshot;
    }

    return _planBrief(
      client: client,
      workspace: workspace,
      brief: brief,
      jobId: jobId,
      baseSystemPrompt: baseSystemPrompt,
      chatSessionId: chatSessionId,
      autonomyPreference: autonomyPreference ?? brief.recommendedAutonomy,
      now: now,
      maxPhaseRetries: maxPhaseRetries,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> planDraftJob({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    AutonomyLevel? autonomyPreference,
    int? maxPhaseRetries,
    JobModelOutputSink? onModelOutput,
  }) async {
    final requiredQuestions = snapshot.state.openQuestions
        .where(
          (question) =>
              question.required && question.status == OpenQuestionStatus.open,
        )
        .toList();
    if (requiredQuestions.isNotEmpty) {
      final blocked = _blockOnQuestions(snapshot, requiredQuestions);
      await _storage.saveSnapshot(workspace.rootPath, blocked);
      return blocked;
    }

    final now = DateTime.now();
    return _planBrief(
      client: client,
      workspace: workspace,
      brief: snapshot.taskBrief.copyWith(updatedAt: now),
      jobId: snapshot.spec.id,
      baseSystemPrompt: baseSystemPrompt,
      autonomyPreference: autonomyPreference ?? snapshot.spec.autonomy,
      now: now,
      maxPhaseRetries: maxPhaseRetries,
      existingState: snapshot.state,
      createdAt: snapshot.spec.createdAt,
      onModelOutput: onModelOutput,
    );
  }

  Future<JobSnapshot> _planBrief({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required TaskBrief brief,
    required String jobId,
    required String baseSystemPrompt,
    required AutonomyLevel autonomyPreference,
    required DateTime now,
    int? maxPhaseRetries,
    JobState? existingState,
    DateTime? createdAt,
    String? chatSessionId,
    JobModelOutputSink? onModelOutput,
  }) async {
    final metadata = await collectWorkspaceMetadata(workspace);
    final tools = _toolService.getToolDefinitions(includeWorkspaceTools: true);

    var spec = await _planJob(
      client: client,
      taskBrief: brief,
      workspaceMetadata: metadata,
      availableTools: tools.map((tool) => tool.id).toList(),
      jobId: jobId,
      baseSystemPrompt: baseSystemPrompt,
      autonomyPreference: autonomyPreference,
      now: now,
      onModelOutput: onModelOutput,
    );

    spec = _applyMaxPhaseRetries(
      _normaliseSpec(spec, brief, jobId, now),
      maxPhaseRetries,
    );
    final specIssues = _specValidator.validate(spec);
    if (specIssues.isNotEmpty) {
      spec = _applyMaxPhaseRetries(
        _normaliseSpec(
          _fallbackJobSpec(
            taskBrief: brief,
            jobId: jobId,
            now: now,
            autonomy: autonomyPreference,
          ),
          brief,
          jobId,
          now,
        ),
        maxPhaseRetries,
      );
      _specValidator.throwIfInvalid(spec);
    }

    final state = JobState(
      jobId: spec.id,
      chatSessionId: existingState?.chatSessionId ?? chatSessionId,
      status: JobStatus.planned,
      currentPhaseId: _nextRunnablePhaseId(spec.phases),
      startedAt: existingState?.startedAt,
      updatedAt: now,
      completedPhases: existingState?.completedPhases ?? const [],
      failedPhases: existingState?.failedPhases ?? const [],
      skippedPhases: existingState?.skippedPhases ?? const [],
      artifacts: existingState?.artifacts ?? const [],
      openQuestions:
          existingState?.openQuestions ?? _openQuestionsFromBrief(brief),
      assumptions: existingState?.assumptions ?? brief.assumptions,
      risks: existingState?.risks ?? const [],
      phaseRuns: existingState?.phaseRuns ?? const [],
      latestSummary: 'Job planned. ${spec.phases.length} phases are pending.',
    );

    final snapshot = JobSnapshot(
      taskBrief: brief,
      spec: spec.copyWith(createdAt: createdAt),
      state: state,
    );
    await _storage.saveSnapshot(workspace.rootPath, snapshot);
    return snapshot;
  }

  Future<JobSnapshot> runNextPhase({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required String baseSystemPrompt,
    bool requireFileEditApproval = false,
    JobModelOutputSink? onModelOutput,
  }) async {
    final recovery = await _recoverSnapshot(
      workspace: workspace,
      snapshot: snapshot,
    );
    if (recovery.blocking) return recovery.snapshot;
    snapshot = recovery.snapshot;

    final requiredQuestions = snapshot.state.openQuestions
        .where(
          (question) =>
              question.required && question.status == OpenQuestionStatus.open,
        )
        .toList();
    if (requiredQuestions.isNotEmpty) {
      final blocked = _blockOnQuestions(snapshot, requiredQuestions);
      await _storage.saveSnapshot(workspace.rootPath, blocked);
      return blocked;
    }

    final phaseIndex = snapshot.spec.phases.indexWhere(
      (phase) =>
          phase.status == PhaseStatus.pending ||
          phase.status == PhaseStatus.failed ||
          phase.status == PhaseStatus.blocked,
    );
    if (phaseIndex < 0) {
      final completed = _markCompleted(snapshot);
      await _storage.saveSnapshot(workspace.rootPath, completed);
      return completed;
    }

    final phase = snapshot.spec.phases[phaseIndex];
    final now = DateTime.now();
    final run = PhaseRun(
      phaseId: phase.id,
      runId: 'run_${uuid.v7()}',
      status: PhaseRunStatus.running,
      startedAt: now,
      toolCalls: const [],
      filesRead: const [],
      filesWritten: const [],
      filesPatched: const [],
      terminalCommands: const [],
      summary: '',
    );

    var working = _replacePhase(
      snapshot,
      phaseIndex,
      phase.copyWith(status: PhaseStatus.running),
    );
    working = working.copyWith(
      spec: working.spec.copyWith(status: JobStatus.running, updatedAt: now),
      state: working.state.copyWith(
        status: JobStatus.running,
        currentPhaseId: phase.id,
        startedAt: snapshot.state.startedAt ?? now,
        updatedAt: now,
        phaseRuns: [...snapshot.state.phaseRuns, run],
        latestSummary: 'Running phase ${phase.id}: ${phase.title}',
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, working);

    try {
      final execution = await _executePhase(
        client: client,
        workspace: workspace,
        snapshot: working,
        phase: phase,
        run: run,
        baseSystemPrompt: baseSystemPrompt,
        requireFileEditApproval: requireFileEditApproval,
        onModelOutput: onModelOutput,
      );

      if (execution.pendingApprovals.isNotEmpty) {
        final blockedRun = run.copyWith(
          status: PhaseRunStatus.blocked,
          completedAt: DateTime.now(),
          toolCalls: execution.toolCalls,
          filesRead: execution.filesRead,
          filesWritten: execution.filesWritten,
          filesPatched: execution.filesPatched,
          fileChanges: execution.fileChanges,
          terminalCommands: execution.terminalCommands,
          summary:
              'Phase is blocked pending ${execution.pendingApprovals.length} file change approval${execution.pendingApprovals.length == 1 ? '' : 's'}.',
        );
        final updatedRuns = [...working.state.phaseRuns]..removeLast();
        updatedRuns.add(blockedRun);
        var blocked = _replacePhase(
          working,
          phaseIndex,
          phase.copyWith(status: PhaseStatus.blocked),
        );
        blocked = blocked.copyWith(
          spec: blocked.spec.copyWith(
            status: JobStatus.blocked,
            updatedAt: DateTime.now(),
          ),
          state: blocked.state.copyWith(
            status: JobStatus.blocked,
            currentPhaseId: phase.id,
            updatedAt: DateTime.now(),
            failedPhases: _withUnique(working.state.failedPhases, phase.id),
            pendingApprovals: _mergePendingApprovals(
              working.state.pendingApprovals,
              execution.pendingApprovals,
            ),
            phaseRuns: updatedRuns,
            latestSummary:
                'File change approval required for phase ${phase.id}.',
          ),
        );
        await _storage.saveSnapshot(workspace.rootPath, blocked);
        return blocked;
      }

      final materialised = await _materialiseMissingOutputs(
        workspace: workspace,
        jobId: working.spec.id,
        phase: phase,
        content: execution.finalText,
      );

      final completedRun = run.copyWith(
        status: PhaseRunStatus.completed,
        completedAt: DateTime.now(),
        toolCalls: execution.toolCalls,
        filesRead: execution.filesRead,
        filesWritten: [...execution.filesWritten, ...materialised],
        filesPatched: execution.filesPatched,
        fileChanges: execution.fileChanges,
        terminalCommands: execution.terminalCommands,
        summary: _phaseSummary(execution.finalText),
      );

      final review = await _reviewPhase(
        client: client,
        workspace: workspace,
        snapshot: working,
        phase: phase,
        phaseRun: completedRun,
        baseSystemPrompt: baseSystemPrompt,
        onModelOutput: onModelOutput,
      );

      await _storage.saveReview(
        workspace.rootPath,
        working.spec.id,
        phase.id,
        review,
      );

      final runWithReview = completedRun.copyWith(
        status:
            review.status == ReviewStatus.passed ||
                review.status == ReviewStatus.warning
            ? PhaseRunStatus.completed
            : review.recommendation == ReviewRecommendation.askUser
            ? PhaseRunStatus.blocked
            : PhaseRunStatus.reviewFailed,
        reviewResult: review,
      );

      final phasePassed =
          review.status == ReviewStatus.passed ||
          review.status == ReviewStatus.warning;
      final reviewQuestion = _openQuestionFromReview(
        phase: phase,
        run: runWithReview,
        review: review,
      );
      final updatedPhase = phase.copyWith(
        status: phasePassed ? PhaseStatus.completed : PhaseStatus.blocked,
      );
      final artifacts = phasePassed
          ? _mergeArtifacts(working.state.artifacts, phase, DateTime.now())
          : working.state.artifacts;
      final completedPhases = phasePassed
          ? _withUnique(working.state.completedPhases, phase.id)
          : working.state.completedPhases;
      final failedPhases = phasePassed
          ? working.state.failedPhases
          : _withUnique(working.state.failedPhases, phase.id);
      final updatedRuns = [...working.state.phaseRuns]..removeLast();
      updatedRuns.add(runWithReview);

      var updated = _replacePhase(working, phaseIndex, updatedPhase);
      final noPending = updated.spec.phases.every(
        (phase) =>
            phase.status == PhaseStatus.completed ||
            phase.status == PhaseStatus.skipped,
      );
      var status = phasePassed
          ? (noPending ? JobStatus.completed : JobStatus.paused)
          : JobStatus.blocked;

      final shouldRetry =
          !phasePassed && _shouldRetryPhase(working, phase, review);
      if (shouldRetry) {
        status = JobStatus.running;
        updated = _replacePhase(
          working,
          phaseIndex,
          phase.copyWith(status: PhaseStatus.pending),
        );
      }

      updated = updated.copyWith(
        spec: updated.spec.copyWith(status: status, updatedAt: DateTime.now()),
        state: updated.state.copyWith(
          status: status,
          completedAt: noPending ? DateTime.now() : updated.state.completedAt,
          currentPhaseId: noPending ? null : phase.id,
          updatedAt: DateTime.now(),
          completedPhases: completedPhases,
          failedPhases: failedPhases,
          artifacts: artifacts,
          openQuestions: _mergeOpenQuestion(
            updated.state.openQuestions,
            reviewQuestion,
          ),
          phaseRuns: updatedRuns,
          latestSummary: shouldRetry
              ? 'Phase ${phase.id} failed review and will retry once.'
              : reviewQuestion != null
              ? 'Review requested user input for phase ${phase.id}.'
              : review.summary.isNotEmpty
              ? review.summary
              : runWithReview.summary,
        ),
      );

      await _storage.saveSnapshot(workspace.rootPath, updated);
      if (shouldRetry) {
        return runNextPhase(
          client: client,
          workspace: workspace,
          snapshot: updated,
          baseSystemPrompt: baseSystemPrompt,
          requireFileEditApproval: requireFileEditApproval,
          onModelOutput: onModelOutput,
        );
      }
      return updated;
    } on _PhaseBlockedException catch (e) {
      final blockedRun = run.copyWith(
        status: PhaseRunStatus.blocked,
        completedAt: DateTime.now(),
        error: e.message,
        summary: e.message,
      );
      final updatedRuns = [...working.state.phaseRuns]..removeLast();
      updatedRuns.add(blockedRun);
      var blocked = _replacePhase(
        working,
        phaseIndex,
        phase.copyWith(status: PhaseStatus.blocked),
      );
      blocked = blocked.copyWith(
        spec: blocked.spec.copyWith(
          status: JobStatus.blocked,
          updatedAt: DateTime.now(),
        ),
        state: blocked.state.copyWith(
          status: JobStatus.blocked,
          currentPhaseId: phase.id,
          updatedAt: DateTime.now(),
          failedPhases: _withUnique(working.state.failedPhases, phase.id),
          phaseRuns: updatedRuns,
          latestSummary: e.message,
        ),
      );
      await _storage.saveSnapshot(workspace.rootPath, blocked);
      return blocked;
    } catch (e) {
      final failedRun = run.copyWith(
        status: PhaseRunStatus.failed,
        completedAt: DateTime.now(),
        error: e.toString(),
        summary: 'Phase failed: $e',
      );
      final updatedRuns = [...working.state.phaseRuns]..removeLast();
      updatedRuns.add(failedRun);
      var failed = _replacePhase(
        working,
        phaseIndex,
        phase.copyWith(status: PhaseStatus.failed),
      );
      failed = failed.copyWith(
        spec: failed.spec.copyWith(
          status: JobStatus.failed,
          updatedAt: DateTime.now(),
        ),
        state: failed.state.copyWith(
          status: JobStatus.failed,
          updatedAt: DateTime.now(),
          failedPhases: _withUnique(working.state.failedPhases, phase.id),
          phaseRuns: updatedRuns,
          latestSummary: 'Phase ${phase.id} failed: $e',
        ),
      );
      await _storage.saveSnapshot(workspace.rootPath, failed);
      return failed;
    }
  }

  Future<WorkspaceMetadata> collectWorkspaceMetadata(
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

    final packageFiles = rootFiles
        .where(
          (name) => const {
            'pubspec.yaml',
            'package.json',
            'pnpm-lock.yaml',
            'yarn.lock',
            'package-lock.json',
            'Cargo.toml',
            'go.mod',
            'pyproject.toml',
            'requirements.txt',
            'pom.xml',
            'build.gradle',
            'Gemfile',
            'composer.json',
          }.contains(name),
        )
        .toList();

    return WorkspaceMetadata(
      workspaceName: workspace.displayName,
      rootFiles: rootFiles,
      detectedProjectType: _detectProjectType(rootFiles),
      packageManagerFiles: packageFiles,
      gitAvailable: rootFiles.contains('.git'),
      existingJobIds: (await _storage.listJobs(
        workspace.rootPath,
        chatSessionId: chatSessionId,
      )).map((job) => job.id).toList(),
    );
  }

  Future<TaskBrief> _refinePrompt({
    required ChatClient client,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required WorkspaceMetadata workspaceMetadata,
    required List<ToolDefinition> availableTools,
    required String fallbackId,
    required DateTime now,
    JobModelOutputSink? onModelOutput,
  }) async {
    final input = {
      'userPrompt': userPrompt,
      'workspaceMetadata': workspaceMetadata.toJson(),
      'availableTools': availableTools.map((tool) {
        return {
          'id': tool.id,
          'name': tool.name,
          'description': tool.description,
        };
      }).toList(),
      'userSelectedMode': selectedMode.wire,
    };

    try {
      final json = await _completeJson(
        client: client,
        system: _promptRefinerSystemInstruction,
        label: 'Prompt Refiner',
        onModelOutput: onModelOutput,
        user:
            '''
Create a TaskBrief for this request.

Return only JSON matching the TaskBrief shape. Use camelCase field names.

Input:
${_encoder.convert(input)}
''',
      );
      return TaskBrief.fromJson(json);
    } catch (_) {
      return _fallbackTaskBrief(
        id: fallbackId,
        now: now,
        userPrompt: userPrompt,
        selectedMode: selectedMode,
      );
    }
  }

  TaskBrief _normaliseBrief({
    required TaskBrief brief,
    required String fallbackId,
    required DateTime now,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required AutonomyLevel? autonomyPreference,
  }) {
    return brief.copyWith(
      id: brief.id.isEmpty ? fallbackId : brief.id,
      createdAt: brief.createdAt,
      updatedAt: now,
      originalPrompt: brief.originalPrompt.isEmpty
          ? userPrompt
          : brief.originalPrompt,
      objective: brief.objective.isEmpty ? userPrompt : brief.objective,
      recommendedMode:
          selectedMode == ExecutionMode.job ||
              selectedMode == ExecutionMode.plan ||
              selectedMode == ExecutionMode.refine
          ? selectedMode
          : brief.recommendedMode,
      recommendedAutonomy: autonomyPreference ?? brief.recommendedAutonomy,
    );
  }

  Future<JobSpec> _planJob({
    required ChatClient client,
    required TaskBrief taskBrief,
    required WorkspaceMetadata workspaceMetadata,
    required List<String> availableTools,
    required String jobId,
    required String baseSystemPrompt,
    required AutonomyLevel autonomyPreference,
    required DateTime now,
    JobModelOutputSink? onModelOutput,
  }) async {
    try {
      return await _completeValidatedJobSpec(
        client: client,
        system: _jobPlannerSystemInstruction,
        user:
            '''
Convert this TaskBrief into a JobSpec.

Return only JSON matching the JobSpec schema. Use camelCase field names.
Use this exact job id: $jobId
Use this exact taskBriefId: ${taskBrief.id}
Only use available tool ids listed below.
When a phase needs filesystem output but no file-writing tool is appropriate, still declare expectedOutputs; the app runner can materialize final text into the artifact.

Available tools:
${_encoder.convert(availableTools)}

Workspace metadata:
${_encoder.convert(workspaceMetadata.toJson())}

TaskBrief:
${_encoder.convert(taskBrief.toJson())}

Available MVP templates:
${_encoder.convert(_templateRegistry.summaries(jobId))}
''',
        taskBrief: taskBrief,
        jobId: jobId,
        now: now,
        label: 'Job Planner',
        onModelOutput: onModelOutput,
      );
    } catch (_) {
      return _fallbackJobSpec(
        taskBrief: taskBrief,
        jobId: jobId,
        now: now,
        autonomy: autonomyPreference,
      );
    }
  }

  Future<JobSpec> _completeValidatedJobSpec({
    required ChatClient client,
    required String system,
    required String user,
    required TaskBrief taskBrief,
    required String jobId,
    required DateTime now,
    required String label,
    JobModelOutputSink? onModelOutput,
  }) async {
    final json = await _completeJson(
      client: client,
      system: system,
      user: user,
      label: label,
      onModelOutput: onModelOutput,
    );
    final candidate = JobSpec.fromJson(json);
    final normalised = _normaliseSpec(candidate, taskBrief, jobId, now);
    final issues = _specValidator.validate(normalised);
    if (issues.isEmpty) return candidate;

    final repairedJson = await _completeJson(
      client: client,
      system: 'Repair the JobSpec JSON. Return only one valid JSON object.',
      label: '$label Repair',
      onModelOutput: onModelOutput,
      user:
          '''
The previous JobSpec failed validation.

Validation issues:
${issues.map((issue) => '- $issue').join('\n')}

Original planning request:
$user

Invalid JobSpec:
${_encoder.convert(candidate.toJson())}

Return a corrected JobSpec using:
- id: $jobId
- taskBriefId: ${taskBrief.id}
- camelCase field names
- safe workspace-relative artifact paths
- unique non-empty phase ids
- explicit expected outputs for every phase
''',
    );
    final repaired = JobSpec.fromJson(repairedJson);
    final repairedIssues = _specValidator.validate(
      _normaliseSpec(repaired, taskBrief, jobId, now),
    );
    if (repairedIssues.isEmpty) return repaired;
    throw FormatException(
      'Model returned invalid JobSpec after repair: ${repairedIssues.join('; ')}',
    );
  }

  JobSpec _applyMaxPhaseRetries(JobSpec spec, int? maxPhaseRetries) {
    if (maxPhaseRetries == null) return spec;
    final normalisedMaxRetries = maxPhaseRetries.clamp(0, 5).toInt();
    return spec.copyWith(
      stopPolicy: StopPolicy(
        maxTotalPhases: spec.stopPolicy.maxTotalPhases,
        maxPhaseTerminalCommands: spec.stopPolicy.maxPhaseTerminalCommands,
        maxPhaseFilesRead: spec.stopPolicy.maxPhaseFilesRead,
        maxPhaseRetries: normalisedMaxRetries,
        maxRuntimeSeconds: spec.stopPolicy.maxRuntimeSeconds,
        stopOnRequiredQuestion: spec.stopPolicy.stopOnRequiredQuestion,
        stopOnLowConfidence: spec.stopPolicy.stopOnLowConfidence,
      ),
      phases: [
        for (final phase in spec.phases)
          phase.copyWith(
            retryPolicy: RetryPolicy(
              maxRetries: normalisedMaxRetries,
              retryOnReviewFailure:
                  phase.retryPolicy?.retryOnReviewFailure ?? true,
              retryOnMissingOutput:
                  phase.retryPolicy?.retryOnMissingOutput ?? true,
            ),
          ),
      ],
    );
  }

  JobSpec _normaliseSpec(
    JobSpec spec,
    TaskBrief brief,
    String jobId,
    DateTime now,
  ) {
    final toolPolicy = _toolPolicyResolver;
    final defaultDisallowed = toolPolicy.normaliseToolIds(
      spec.toolPolicy.defaultDisallowed,
    );
    final defaultAllowed = spec.toolPolicy.defaultAllowed.isEmpty
        ? toolPolicy.availableToolIds.toList()
        : toolPolicy.normaliseToolIds(spec.toolPolicy.defaultAllowed);
    final effectiveDefaultAllowed = defaultAllowed
        .where((tool) => !defaultDisallowed.contains(tool))
        .toList();

    final phases = spec.phases.isEmpty
        ? _fallbackJobSpec(
            taskBrief: brief,
            jobId: jobId,
            now: now,
            autonomy: spec.autonomy,
          ).phases
        : spec.phases.map((phase) {
            final phaseDisallowed = toolPolicy.normaliseToolIds(
              phase.disallowedTools,
            );
            var allowed = phase.allowedTools.isEmpty
                ? effectiveDefaultAllowed
                : toolPolicy
                      .normaliseToolIds(phase.allowedTools)
                      .where((tool) => !defaultDisallowed.contains(tool))
                      .toList();
            allowed = allowed
                .where((tool) => !phaseDisallowed.contains(tool))
                .toList();
            final terminal = spec.toolPolicy.terminal;
            if (phase.terminalPolicy == TerminalPolicy.none ||
                terminal?.allowed == false ||
                terminal?.policy == TerminalPolicy.none) {
              allowed = allowed.where((tool) => tool != 'run_command').toList();
            }
            return phase.copyWith(
              status: PhaseStatus.pending,
              stopPolicy: phase.stopPolicy,
              allowedTools: allowed,
              disallowedTools: phaseDisallowed,
              expectedOutputs: phase.expectedOutputs
                  .map(
                    (output) => PhaseOutput(
                      path: _replaceJobId(output.path, jobId),
                      required: output.required,
                      description: output.description,
                      format: output.format,
                    ),
                  )
                  .toList(),
              inputs: phase.inputs
                  .map(
                    (input) => PhaseInput(
                      path: _replaceJobId(input.path, jobId),
                      required: input.required,
                      description: input.description,
                    ),
                  )
                  .toList(),
            );
          }).toList();

    return spec.copyWith(
      id: spec.id.isEmpty ? jobId : spec.id,
      taskBriefId: spec.taskBriefId.isEmpty ? brief.id : spec.taskBriefId,
      status: JobStatus.planned,
      createdAt: spec.createdAt,
      updatedAt: now,
      title: spec.title.trim().isEmpty ? brief.title : spec.title,
      domain: spec.domain == JobDomain.unknown ? brief.domain : spec.domain,
      autonomy: spec.autonomy,
      globalConstraints: spec.globalConstraints.isEmpty
          ? brief.constraints
          : spec.globalConstraints,
      globalSuccessCriteria: spec.globalSuccessCriteria.isEmpty
          ? brief.successCriteria
          : spec.globalSuccessCriteria,
      toolPolicy: ToolPolicy(
        defaultAllowed: effectiveDefaultAllowed,
        defaultDisallowed: defaultDisallowed,
        terminal:
            spec.toolPolicy.terminal ??
            const TerminalToolPolicy(
              allowed: true,
              policy: TerminalPolicy.workspaceMutating,
            ),
      ),
      stopPolicy: _hasActionableStopPolicy(spec.stopPolicy)
          ? spec.stopPolicy
          : const StopPolicy(
              maxTotalPhases: 12,
              maxPhaseRetries: 1,
              stopOnRequiredQuestion: true,
              stopOnLowConfidence: false,
            ),
      phases: phases,
    );
  }

  bool _hasActionableStopPolicy(StopPolicy policy) {
    return policy.maxTotalPhases != null ||
        policy.maxPhaseTerminalCommands != null ||
        policy.maxPhaseFilesRead != null ||
        policy.maxPhaseRetries != null ||
        policy.maxRuntimeSeconds != null ||
        policy.stopOnRequiredQuestion != null ||
        policy.stopOnLowConfidence != null;
  }

  Future<_PhaseExecutionOutput> _executePhase({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required JobPhase phase,
    required PhaseRun run,
    required String baseSystemPrompt,
    required bool requireFileEditApproval,
    JobModelOutputSink? onModelOutput,
  }) async {
    final allowedTools = _phaseAllowedTools(snapshot.spec, phase);
    final toolDefs = allowedTools.isEmpty
        ? const <ToolDefinition>[]
        : _toolService.getToolDefinitions(
            ids: allowedTools,
            includeWorkspaceTools: true,
          );
    final context = WorkspaceToolContext(workspace: workspace);
    final prompt = await _buildPhasePrompt(
      workspace: workspace,
      snapshot: snapshot,
      phase: phase,
    );
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: baseSystemPrompt),
      const ChatMessage(role: 'system', content: _phaseExecutorInstruction),
      ChatMessage(role: 'user', content: prompt),
    ];
    final toolCalls = <ToolCallRecord>[];
    final filesRead = <String>{};
    final filesWritten = <String>{};
    final filesPatched = <String>{};
    final fileChanges = <FileChangeSummary>[];
    final pendingApprovals = <PendingFileApproval>[];
    final terminalCommands = <String>{};
    final beforeMutations =
        _shouldDetectWorkspaceMutations(snapshot.spec, phase)
        ? await _workspaceMutationSnapshot(workspace.rootPath)
        : null;

    var finalText = '';

    while (true) {
      final completion = await _completeChatForJob(
        client: client,
        label: 'Phase Executor: ${phase.title}',
        onModelOutput: onModelOutput,
        messages: messages,
        extraParams: ToolCaller.buildExtraParams(
          addGenerationPrompt: true,
          toolDefs: toolDefs,
        ),
      );

      finalText = [
        if (completion.reasoning.trim().isNotEmpty)
          'Reasoning summary:\n${completion.reasoning.trim()}',
        if (completion.content.trim().isNotEmpty) completion.content.trim(),
      ].join('\n\n').trim();

      if (completion.toolCalls.isEmpty) break;

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
        if (pendingApprovals.isNotEmpty) break;
        final call = completion.toolCalls[i];
        final callId = call.id ?? 'call_$i';
        final args = JobJson.decodeJsonOrString(call.arguments);
        final beforeFileChange = await _captureFileChangeBefore(
          workspace.rootPath,
          call.name,
          args,
        );
        String resultJson;
        String? error;
        var approvalCaptured = false;

        if (!allowedTools.contains(call.name)) {
          resultJson = jsonEncode({
            'error': 'Tool is not allowed in this phase.',
          });
          error = 'Tool is not allowed in this phase.';
        } else if (requireFileEditApproval &&
            _requiresFileEditApproval(call.name)) {
          final approval = await _pendingFileApprovalFromToolCall(
            workspaceRoot: workspace.rootPath,
            phase: phase,
            run: run,
            callId: callId,
            toolName: call.name,
            arguments: args,
          );
          if (approval == null) {
            resultJson = jsonEncode({
              'error':
                  'File edit approval could not be prepared for ${call.name}.',
            });
            error = 'File edit approval could not be prepared.';
          } else {
            pendingApprovals.add(approval);
            approvalCaptured = true;
            resultJson = jsonEncode({
              'approval_required': true,
              'approval_id': approval.id,
              'path': approval.path,
              'hunks': approval.hunks.length,
              'message':
                  'File edit proposal captured. The user must approve selected hunks before this edit is applied.',
            });
          }
        } else if (call.name == 'run_command') {
          error = _terminalPolicyViolation(
            spec: snapshot.spec,
            phase: phase,
            arguments: args,
          );
          if (error != null) {
            resultJson = jsonEncode({'error': error});
          } else {
            resultJson = await _toolService.execute(
              toolId: call.name,
              argumentsJson: call.arguments,
              context: context,
            );
            error = _toolError(resultJson);
          }
        } else {
          resultJson = await _toolService.execute(
            toolId: call.name,
            argumentsJson: call.arguments,
            context: context,
          );
          error = _toolError(resultJson);
        }

        if (error == null && !approvalCaptured) {
          final fileChange = await _buildFileChangeSummary(
            workspace.rootPath,
            call.name,
            args,
            beforeFileChange,
          );
          if (fileChange != null) fileChanges.add(fileChange);
        }
        if (!approvalCaptured) {
          _recordToolSideEffects(
            toolName: call.name,
            arguments: args,
            resultJson: resultJson,
            filesRead: filesRead,
            filesWritten: filesWritten,
            filesPatched: filesPatched,
            terminalCommands: terminalCommands,
          );
        }
        toolCalls.add(
          ToolCallRecord(
            id: callId,
            jobId: snapshot.spec.id,
            phaseId: phase.id,
            runId: run.runId,
            toolName: call.name,
            arguments: args,
            resultSummary: _cap(resultJson, 800),
            error: error,
            timestamp: DateTime.now(),
          ),
        );
        _emitJobModelOutput(
          onModelOutput,
          JobModelOutputEvent(
            type: JobModelOutputEventType.toolResult,
            label: 'Phase Executor: ${phase.title}',
            text: '${call.name}: ${_cap(resultJson, 1600)}',
          ),
        );
        messages.add(
          ChatMessage(role: 'tool', content: resultJson, toolCallId: callId),
        );
      }

      if (pendingApprovals.isNotEmpty) break;
    }

    if (beforeMutations != null) {
      final afterMutations = await _workspaceMutationSnapshot(
        workspace.rootPath,
      );
      filesPatched.addAll(
        _workspaceMutationChanges(beforeMutations, afterMutations),
      );
    }

    await _storage.saveLog(
      workspace.rootPath,
      snapshot.spec.id,
      '${phase.id}-${run.runId}.md',
      finalText,
    );

    return _PhaseExecutionOutput(
      finalText: finalText,
      toolCalls: toolCalls,
      filesRead: filesRead.toList()..sort(),
      filesWritten: filesWritten.toList()..sort(),
      filesPatched: filesPatched.toList()..sort(),
      fileChanges: fileChanges,
      pendingApprovals: pendingApprovals,
      terminalCommands: terminalCommands.toList(),
    );
  }

  Future<ReviewResult> _reviewPhase({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required JobPhase phase,
    required PhaseRun phaseRun,
    required String baseSystemPrompt,
    JobModelOutputSink? onModelOutput,
  }) async {
    final deterministic = await _deterministicReview(
      workspace: workspace,
      snapshot: snapshot,
      phase: phase,
      phaseRun: phaseRun,
    );
    final deterministicPassed = deterministic.every((check) => check.passed);
    if (!deterministicPassed) {
      return ReviewResult(
        phaseId: phase.id,
        status: ReviewStatus.failed,
        deterministicChecks: deterministic,
        summary: 'Deterministic review failed for ${phase.title}.',
        issues: deterministic
            .where((check) => !check.passed)
            .map(
              (check) => ReviewIssue(
                severity: 'error',
                message: check.message,
                suggestedAction: 'Retry or revise this phase.',
              ),
            )
            .toList(),
        recommendation: ReviewRecommendation.retryPhase,
      );
    }

    final reviewer = phase.review.reviewer;
    if (!phase.review.required ||
        reviewer == ReviewerType.none ||
        reviewer == ReviewerType.deterministic ||
        reviewer == ReviewerType.human) {
      return ReviewResult(
        phaseId: phase.id,
        status: ReviewStatus.passed,
        deterministicChecks: deterministic,
        summary: 'Deterministic review passed for ${phase.title}.',
        issues: const [],
        recommendation: ReviewRecommendation.continueJob,
      );
    }

    try {
      final artifacts = await _artifactContents(workspace.rootPath, phase);
      final reviewProfile = BuiltInModelValidators.select(
        taskBrief: snapshot.taskBrief,
        jobSpec: snapshot.spec,
        phase: phase,
      );
      final reviewJson = await _completeJson(
        client: client,
        system:
            '$baseSystemPrompt\n\n$_reviewerSystemInstruction\n\n${reviewProfile.instruction}',
        label: 'Phase Reviewer: ${phase.title}',
        onModelOutput: onModelOutput,
        user:
            '''
Review profile:
${reviewProfile.id}

Specialized review criteria:
${reviewProfile.criteria.map((criterion) => '- $criterion').join('\n')}

Review this phase output. Return only JSON with:
{
  "passed": true,
  "confidence": "low|medium|high",
  "summary": "...",
  "criteriaResults": [{"criterion":"...","passed":true,"evidence":"...","comment":"..."}],
  "issues": [{"severity":"info|warning|error|blocking","message":"...","suggestedAction":"..."}],
  "recommendation": "continue|retry_phase|ask_user|revise_plan|stop_job"
}

Task brief:
${_encoder.convert(snapshot.taskBrief.toJson())}

Global constraints:
${_encoder.convert(snapshot.spec.globalConstraints)}

Phase:
${_encoder.convert(phase.toJson())}

Phase run summary:
${_encoder.convert(phaseRun.toJson())}

Produced artifacts:
${_encoder.convert(artifacts)}
''',
      );

      final modelReview = ModelReviewResult.fromJson(reviewJson);
      final issues = _mapList(
        reviewJson['issues'],
      ).map(ReviewIssue.fromJson).toList();
      final recommendation = parseReviewRecommendation(
        reviewJson['recommendation'],
      );
      final passed = modelReview.passed;

      return ReviewResult(
        phaseId: phase.id,
        status: passed ? ReviewStatus.passed : ReviewStatus.failed,
        deterministicChecks: deterministic,
        modelReview: modelReview,
        summary: modelReview.summary,
        issues: issues,
        recommendation: passed
            ? ReviewRecommendation.continueJob
            : recommendation,
      );
    } catch (e) {
      return ReviewResult(
        phaseId: phase.id,
        status: ReviewStatus.warning,
        deterministicChecks: deterministic,
        summary:
            'Deterministic review passed. Model review could not be parsed: $e',
        issues: [
          ReviewIssue(
            severity: 'warning',
            message: 'Model review failed to return parseable JSON.',
            suggestedAction: 'Continue with deterministic review only.',
          ),
        ],
        recommendation: ReviewRecommendation.continueJob,
      );
    }
  }

  Future<List<DeterministicCheckResult>> _deterministicReview({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required JobPhase phase,
    required PhaseRun phaseRun,
  }) async {
    final artifacts = await _artifactContents(workspace.rootPath, phase);
    final allowedTools = _phaseAllowedTools(snapshot.spec, phase).toSet();
    final effectiveTerminalPolicy = _effectiveTerminalPolicy(
      snapshot.spec,
      phase,
    );
    final effectiveStopPolicy = _effectiveStopPolicy(snapshot.spec, phase);
    final input = PhaseValidationInput(
      workspaceRoot: workspace.rootPath,
      sandbox: _sandbox,
      jobSpec: snapshot.spec,
      jobState: snapshot.state,
      phase: phase,
      phaseRun: phaseRun,
      artifacts: artifacts,
      allowedTools: allowedTools,
      terminalPolicy: effectiveTerminalPolicy,
      stopPolicy: effectiveStopPolicy,
      classifyCommand: _classifyCommand,
    );

    final results = <PhaseValidationResult>[];
    for (final validator in _phaseValidators.where(
      (validator) => validator.type == PhaseValidatorType.deterministic,
    )) {
      results.addAll(await validator.validate(input));
    }

    return results.map((result) => result.toDeterministicCheck()).toList();
  }

  Future<List<String>> _materialiseMissingOutputs({
    required WorkspaceAttachment workspace,
    required String jobId,
    required JobPhase phase,
    required String content,
  }) async {
    if (content.trim().isEmpty) return const [];
    final written = <String>[];
    final missingOutputs = <PhaseOutput>[];
    for (final output in phase.expectedOutputs.where((o) => o.required)) {
      final resolved = await _resolveMaybe(workspace.rootPath, output.path);
      final exists =
          resolved != null && await File(resolved.absolutePath).exists();
      if (!exists) missingOutputs.add(output);
    }
    if (missingOutputs.isEmpty) return const [];

    final output = missingOutputs.first;
    final resolved = await _sandbox.resolve(
      workspace.rootPath,
      output.path,
      mustExist: false,
    );
    await File(resolved.absolutePath).parent.create(recursive: true);
    await File(resolved.absolutePath).writeAsString(content.trimRight());
    written.add(resolved.relativePath);
    return written;
  }

  Future<String> _buildPhasePrompt({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
    required JobPhase phase,
  }) async {
    final effectiveAllowedTools = _phaseAllowedTools(snapshot.spec, phase);
    final effectiveDisallowedTools = _phaseDisallowedTools(
      snapshot.spec,
      phase,
    );
    final effectiveTerminalPolicy = _effectiveTerminalPolicy(
      snapshot.spec,
      phase,
    );
    final inputContents = <String, String>{};
    for (final input in phase.inputs) {
      final resolved = await _resolveMaybe(workspace.rootPath, input.path);
      if (resolved == null) {
        if (input.required) {
          throw _PhaseBlockedException(
            'Required phase input is missing: ${input.path}',
          );
        }
        continue;
      }
      final file = File(resolved.absolutePath);
      if (await file.exists()) {
        inputContents[input.path] = _cap(await file.readAsString(), 12000);
      }
    }

    final previousSummaries = snapshot.state.phaseRuns
        .where((run) => run.status == PhaseRunStatus.completed)
        .map((run) => '${run.phaseId}: ${run.summary}')
        .join('\n');

    return '''
You are executing one phase of a larger job.

Do not attempt to complete the entire job.
Complete only the current phase.

Job title:
${snapshot.spec.title}

Overall objective:
${snapshot.taskBrief.objective}

Global constraints:
${snapshot.spec.globalConstraints.map((item) => '- $item').join('\n')}

Current phase:
${phase.id} - ${phase.title}

Phase objective:
${phase.objective}

Allowed tools:
${effectiveAllowedTools.map((item) => '- $item').join('\n')}

Terminal policy:
${effectiveTerminalPolicy.wire}

Disallowed tools:
${effectiveDisallowedTools.map((item) => '- $item').join('\n')}

Required inputs:
${phase.inputs.map((item) => '- ${item.path} (${item.required ? 'required' : 'optional'})').join('\n')}

Input artifact contents:
${_encoder.convert(inputContents)}

Expected outputs:
${_encoder.convert(phase.expectedOutputs.map((output) => output.toJson()).toList())}

Completion criteria:
${phase.completionCriteria.map((item) => '- $item').join('\n')}

Relevant previous phase summaries:
$previousSummaries

Retry feedback:
${_retryFeedback(snapshot, phase.id)}

When complete:
1. Produce the expected output artifacts.
2. Provide a short phase summary.
3. Stop.
''';
  }

  List<String> _phaseAllowedTools(JobSpec spec, JobPhase phase) =>
      _toolPolicyResolver.phaseAllowedTools(spec, phase);

  List<String> _phaseDisallowedTools(JobSpec spec, JobPhase phase) =>
      _toolPolicyResolver.phaseDisallowedTools(spec, phase);

  StopPolicy _effectiveStopPolicy(JobSpec spec, JobPhase phase) =>
      _toolPolicyResolver.effectiveStopPolicy(spec, phase);

  TerminalPolicy _effectiveTerminalPolicy(JobSpec spec, JobPhase phase) =>
      _toolPolicyResolver.effectiveTerminalPolicy(spec, phase);

  List<JobArtifact> _mergeArtifacts(
    List<JobArtifact> current,
    JobPhase phase,
    DateTime now,
  ) {
    final byPath = {for (final artifact in current) artifact.path: artifact};
    for (final output in phase.expectedOutputs) {
      byPath[output.path] = JobArtifact(
        path: output.path,
        producedByPhaseId: phase.id,
        createdAt: byPath[output.path]?.createdAt ?? now,
        updatedAt: now,
        description: output.description,
      );
    }
    return byPath.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  }

  JobSnapshot _replacePhase(
    JobSnapshot snapshot,
    int index,
    JobPhase replacement,
  ) {
    final phases = [...snapshot.spec.phases];
    phases[index] = replacement;
    return snapshot.copyWith(spec: snapshot.spec.copyWith(phases: phases));
  }

  JobSnapshot _markCompleted(JobSnapshot snapshot) {
    final now = DateTime.now();
    return snapshot.copyWith(
      spec: snapshot.spec.copyWith(status: JobStatus.completed, updatedAt: now),
      state: snapshot.state.copyWith(
        status: JobStatus.completed,
        completedAt: now,
        currentPhaseId: null,
        updatedAt: now,
        latestSummary: 'Job completed.',
      ),
    );
  }

  String _retryFeedback(JobSnapshot snapshot, String phaseId) {
    final failedRun = snapshot.state.phaseRuns.reversed
        .where(
          (run) =>
              run.phaseId == phaseId &&
              run.reviewResult != null &&
              (run.status == PhaseRunStatus.reviewFailed ||
                  run.reviewResult!.status == ReviewStatus.failed),
        )
        .firstOrNull;
    final review = failedRun?.reviewResult;
    if (review == null || review.issues.isEmpty) return 'None.';

    final buffer = StringBuffer()
      ..writeln('The previous attempt failed review. Address these issues:')
      ..writeln(review.summary);
    for (final issue in review.issues) {
      buffer.writeln('- ${issue.severity}: ${issue.message}');
      if (issue.suggestedAction != null) {
        buffer.writeln('  Suggested action: ${issue.suggestedAction}');
      }
    }
    return buffer.toString().trim();
  }

  Future<_RecoveryResult> _recoverSnapshot({
    required WorkspaceAttachment workspace,
    required JobSnapshot snapshot,
  }) async {
    final now = DateTime.now();
    final issues = <_RecoveryIssue>[];

    for (final phase in snapshot.spec.phases) {
      if (phase.status == PhaseStatus.running ||
          phase.status == PhaseStatus.reviewing) {
        issues.add(
          _RecoveryIssue(
            phaseId: phase.id,
            message:
                'Recovered interrupted phase ${phase.id}: ${phase.title}. Retry the phase to continue.',
          ),
        );
      }
    }

    for (final phase in snapshot.spec.phases.where(
      (phase) => phase.status == PhaseStatus.completed,
    )) {
      for (final output in phase.expectedOutputs.where((o) => o.required)) {
        if (await _fileExistsAndIsNonEmpty(workspace.rootPath, output.path)) {
          continue;
        }
        issues.add(
          _RecoveryIssue(
            phaseId: phase.id,
            artifactPath: output.path,
            message:
                'Required artifact ${output.path} from completed phase ${phase.id} is missing or empty. Retry, skip, or replan this phase.',
          ),
        );
      }
    }

    final nextPhase = snapshot.spec.phases
        .where(
          (phase) =>
              phase.status == PhaseStatus.pending ||
              phase.status == PhaseStatus.failed ||
              phase.status == PhaseStatus.blocked,
        )
        .firstOrNull;
    if (nextPhase != null) {
      for (final input in nextPhase.inputs.where((input) => input.required)) {
        if (await _fileExistsAndIsNonEmpty(workspace.rootPath, input.path)) {
          continue;
        }
        final producer = snapshot.spec.phases
            .where(
              (phase) => phase.expectedOutputs.any(
                (output) => output.path == input.path,
              ),
            )
            .firstOrNull;
        if (producer != null &&
            producer.status != PhaseStatus.completed &&
            producer.status != PhaseStatus.skipped) {
          continue;
        }
        issues.add(
          _RecoveryIssue(
            phaseId: producer?.id ?? nextPhase.id,
            artifactPath: input.path,
            message:
                'Required input ${input.path} for phase ${nextPhase.id} is missing or empty. Retry the producing phase or replan remaining work.',
          ),
        );
      }
    }

    final interruptedOrMissing = issues.isNotEmpty;
    var changed = false;
    final issuePhaseIds = issues.map((issue) => issue.phaseId).toSet();
    final missingPaths = issues
        .map((issue) => issue.artifactPath)
        .whereType<String>()
        .toSet();

    final phases = snapshot.spec.phases.map((phase) {
      if (phase.status == PhaseStatus.running ||
          phase.status == PhaseStatus.reviewing ||
          issuePhaseIds.contains(phase.id)) {
        if (phase.status != PhaseStatus.blocked) changed = true;
        return phase.copyWith(status: PhaseStatus.blocked);
      }
      return phase;
    }).toList();

    var status = snapshot.state.status;
    var currentPhaseId = snapshot.state.currentPhaseId;
    var completedAt = snapshot.state.completedAt;
    var latestSummary = snapshot.state.latestSummary;
    var risks = snapshot.state.risks;
    var completedPhases = snapshot.state.completedPhases;
    var failedPhases = snapshot.state.failedPhases;
    var artifacts = snapshot.state.artifacts;
    var openQuestions = snapshot.state.openQuestions;
    final knownQuestionIds = openQuestions
        .map((question) => question.id)
        .toSet();
    final missingQuestions = _openQuestionsFromBrief(
      snapshot.taskBrief,
    ).where((question) => !knownQuestionIds.contains(question.id)).toList();
    if (missingQuestions.isNotEmpty) {
      changed = true;
      openQuestions = [...openQuestions, ...missingQuestions];
    }

    if (interruptedOrMissing) {
      changed = true;
      status = JobStatus.blocked;
      currentPhaseId = issues.first.phaseId;
      completedAt = null;
      latestSummary = issues.first.message;
      risks = [
        ...snapshot.state.risks,
        for (final issue in issues)
          if (!snapshot.state.risks.contains(issue.message)) issue.message,
      ];
      completedPhases = snapshot.state.completedPhases
          .where((phaseId) => !issuePhaseIds.contains(phaseId))
          .toList();
      failedPhases = [
        ...snapshot.state.failedPhases,
        for (final phaseId in issuePhaseIds)
          if (!snapshot.state.failedPhases.contains(phaseId)) phaseId,
      ];
      artifacts = snapshot.state.artifacts
          .where((artifact) => !missingPaths.contains(artifact.path))
          .toList();
    } else if (snapshot.state.status == JobStatus.running ||
        snapshot.spec.status == JobStatus.running) {
      changed = true;
      final noPending = phases.every(
        (phase) =>
            phase.status == PhaseStatus.completed ||
            phase.status == PhaseStatus.skipped,
      );
      status = noPending ? JobStatus.completed : JobStatus.paused;
      currentPhaseId = noPending ? null : _nextRunnablePhaseId(phases);
      completedAt = noPending ? now : snapshot.state.completedAt;
      latestSummary = noPending
          ? 'Recovered running job as completed.'
          : 'Recovered running job as paused.';
    }

    if (!changed) return _RecoveryResult(snapshot: snapshot, blocking: false);

    final updated = snapshot.copyWith(
      spec: snapshot.spec.copyWith(
        status: status,
        updatedAt: now,
        phases: phases,
      ),
      state: snapshot.state.copyWith(
        status: status,
        currentPhaseId: currentPhaseId,
        completedAt: completedAt,
        updatedAt: now,
        completedPhases: completedPhases,
        failedPhases: failedPhases,
        artifacts: artifacts,
        openQuestions: openQuestions,
        risks: risks,
        latestSummary: latestSummary,
      ),
    );
    await _storage.saveSnapshot(workspace.rootPath, updated);
    return _RecoveryResult(snapshot: updated, blocking: interruptedOrMissing);
  }

  JobSnapshot _blockOnQuestions(
    JobSnapshot snapshot,
    List<OpenQuestion> requiredQuestions,
  ) {
    final now = DateTime.now();
    final specStatus = snapshot.spec.status == JobStatus.draft
        ? JobStatus.draft
        : JobStatus.blocked;
    return snapshot.copyWith(
      spec: snapshot.spec.copyWith(status: specStatus, updatedAt: now),
      state: snapshot.state.copyWith(
        status: JobStatus.blocked,
        updatedAt: now,
        latestSummary:
            'Job is blocked on ${requiredQuestions.length} required question${requiredQuestions.length == 1 ? '' : 's'}.',
      ),
    );
  }

  List<OpenQuestion> _openQuestionsFromBrief(TaskBrief brief) {
    return brief.clarifyingQuestions
        .where((question) => question.answer == null)
        .map(
          (question) => OpenQuestion(
            id: question.id,
            question: question.question,
            required: question.required,
            reason: question.impactIfUnanswered ?? question.defaultAssumption,
            status: OpenQuestionStatus.open,
          ),
        )
        .toList();
  }

  OpenQuestion? _openQuestionFromReview({
    required JobPhase phase,
    required PhaseRun run,
    required ReviewResult review,
  }) {
    if (review.recommendation != ReviewRecommendation.askUser) return null;

    final issue = review.issues
        .where((issue) => issue.severity.toLowerCase() == 'blocking')
        .firstOrNull;
    final fallbackIssue = issue ?? review.issues.firstOrNull;
    final detail = fallbackIssue?.suggestedAction?.trim().isNotEmpty == true
        ? fallbackIssue!.suggestedAction!.trim()
        : fallbackIssue?.message.trim().isNotEmpty == true
        ? fallbackIssue!.message.trim()
        : review.summary.trim();
    final question = detail.isEmpty
        ? 'Reviewer requested user input before phase "${phase.title}" can continue. What should happen next?'
        : detail.endsWith('?')
        ? detail
        : 'Reviewer requested user input before phase "${phase.title}" can continue: $detail What should happen next?';
    final reasonParts = [
      review.summary.trim(),
      if (fallbackIssue != null) fallbackIssue.message.trim(),
    ].where((part) => part.isNotEmpty).toList();

    return OpenQuestion(
      id: 'review_${phase.id}_${run.runId}',
      phaseId: phase.id,
      question: question,
      required: true,
      reason: reasonParts.isEmpty ? null : reasonParts.join('\n'),
      status: OpenQuestionStatus.open,
    );
  }

  List<OpenQuestion> _mergeOpenQuestion(
    List<OpenQuestion> questions,
    OpenQuestion? question,
  ) {
    if (question == null) return questions;
    if (questions.any((existing) => existing.id == question.id)) {
      return questions;
    }
    return [...questions, question];
  }

  List<PendingFileApproval> _mergePendingApprovals(
    List<PendingFileApproval> existing,
    List<PendingFileApproval> additions,
  ) {
    if (additions.isEmpty) return existing;
    final seen = existing.map((approval) => approval.id).toSet();
    return [
      ...existing,
      for (final approval in additions)
        if (seen.add(approval.id)) approval,
    ];
  }

  ClarifyingQuestion? _briefQuestion(TaskBrief brief, String questionId) {
    for (final question in brief.clarifyingQuestions) {
      if (question.id == questionId) return question;
    }
    return null;
  }

  String? _questionDefaultAssumption(TaskBrief brief, String questionId) {
    final assumption = _briefQuestion(brief, questionId)?.defaultAssumption;
    if (assumption == null || assumption.trim().isEmpty) return null;
    return assumption.trim();
  }

  bool _shouldRetryPhase(
    JobSnapshot snapshot,
    JobPhase phase,
    ReviewResult review,
  ) {
    final retryPolicy = phase.retryPolicy;
    if (retryPolicy == null || retryPolicy.maxRetries <= 0) return false;
    if (review.recommendation != ReviewRecommendation.retryPhase) return false;
    if (!retryPolicy.retryOnReviewFailure) return false;

    final failedAttempts = snapshot.state.phaseRuns
        .where(
          (run) =>
              run.phaseId == phase.id &&
              (run.status == PhaseRunStatus.failed ||
                  run.status == PhaseRunStatus.reviewFailed),
        )
        .length;
    return failedAttempts < retryPolicy.maxRetries;
  }

  int _currentOrRetryablePhaseIndex(JobSnapshot snapshot) {
    final currentId = snapshot.state.currentPhaseId;
    if (currentId != null) {
      final currentIndex = snapshot.spec.phases.indexWhere(
        (phase) => phase.id == currentId,
      );
      if (currentIndex >= 0) return currentIndex;
    }
    return snapshot.spec.phases.indexWhere(
      (phase) =>
          phase.status == PhaseStatus.blocked ||
          phase.status == PhaseStatus.failed ||
          phase.status == PhaseStatus.pending,
    );
  }

  JobPhase? _currentOrRetryablePhase(JobSnapshot snapshot) {
    final index = _currentOrRetryablePhaseIndex(snapshot);
    return index < 0 ? null : snapshot.spec.phases[index];
  }

  List<JobPhase> _mergeReplannedPhases({
    required JobSnapshot snapshot,
    required JobSpec candidate,
    required ReplanScope scope,
    required JobPhase? currentPhase,
    required Set<String> protectedIds,
  }) {
    final candidatePhases = candidate.phases
        .where((phase) => !protectedIds.contains(phase.id))
        .toList();
    if (scope == ReplanScope.entireJob) {
      return candidatePhases.isEmpty
          ? snapshot.spec.phases
                .map((phase) => phase.copyWith(status: PhaseStatus.pending))
                .toList()
          : candidatePhases;
    }

    if (scope == ReplanScope.remainingPhases) {
      final protectedPhases = snapshot.spec.phases
          .where((phase) => protectedIds.contains(phase.id))
          .toList();
      final remainingPhases = candidatePhases.isEmpty
          ? snapshot.spec.phases
                .where((phase) => !protectedIds.contains(phase.id))
                .map((phase) => phase.copyWith(status: PhaseStatus.pending))
                .toList()
          : candidatePhases;
      return [...protectedPhases, ...remainingPhases];
    }

    final targetPhase = currentPhase;
    if (targetPhase == null) return snapshot.spec.phases;
    final currentIndex = snapshot.spec.phases.indexWhere(
      (phase) => phase.id == targetPhase.id,
    );
    if (currentIndex < 0) return snapshot.spec.phases;

    final outsideIds = <String>{
      for (var i = 0; i < snapshot.spec.phases.length; i++)
        if (i != currentIndex) snapshot.spec.phases[i].id,
    };
    final replacements = candidatePhases
        .where((phase) => !outsideIds.contains(phase.id))
        .toList();
    final resolvedReplacements = replacements.isEmpty
        ? [targetPhase.copyWith(status: PhaseStatus.pending)]
        : replacements;
    final phases = <JobPhase>[];
    for (var i = 0; i < snapshot.spec.phases.length; i++) {
      if (i == currentIndex) {
        phases.addAll(resolvedReplacements);
      } else {
        phases.add(snapshot.spec.phases[i]);
      }
    }
    return phases;
  }

  String _replanScopeRules(ReplanScope scope) {
    return switch (scope) {
      ReplanScope.currentPhase =>
        'Revise only the current target phase. Return replacement phase(s) in the phases array. Do not change completed, skipped, or unrelated future phases.',
      ReplanScope.remainingPhases =>
        'Revise only pending, failed, or blocked phases. Preserve completed and skipped phases.',
      ReplanScope.entireJob =>
        'Revise the whole executable plan. The app will preserve historical runs and artifacts, but completed/skipped phase status will be reset for the new plan.',
    };
  }

  List<JobPhase> _preserveCompletedPhaseStatuses({
    required List<JobPhase> original,
    required List<JobPhase> updated,
  }) {
    final originalById = {for (final phase in original) phase.id: phase};
    return updated.map((phase) {
      final originalPhase = originalById[phase.id];
      if (originalPhase == null) return phase;
      if (originalPhase.status == PhaseStatus.completed ||
          originalPhase.status == PhaseStatus.skipped) {
        return phase.copyWith(status: originalPhase.status);
      }
      return phase;
    }).toList();
  }

  String? _nextRunnablePhaseId(List<JobPhase> phases) {
    return phases
        .where(
          (phase) =>
              phase.status == PhaseStatus.pending ||
              phase.status == PhaseStatus.failed ||
              phase.status == PhaseStatus.blocked,
        )
        .firstOrNull
        ?.id;
  }

  List<String> _retainExistingPhaseIds(
    Iterable<String> phaseIds,
    List<JobPhase> phases,
  ) {
    final existing = phases.map((phase) => phase.id).toSet();
    return phaseIds.where(existing.contains).toList();
  }

  bool _hasRequiredUnansweredQuestions(TaskBrief brief) {
    return brief.clarifyingQuestions.any(
      (question) => question.required && question.answer == null,
    );
  }

  JobSnapshot _draftSnapshot({
    required TaskBrief brief,
    required String jobId,
    required DateTime now,
    String? chatSessionId,
    required AutonomyLevel autonomy,
  }) {
    final openQuestions = _openQuestionsFromBrief(brief);
    return JobSnapshot(
      taskBrief: brief,
      spec: JobSpec(
        version: 1,
        id: jobId,
        title: brief.title,
        description: brief.objective,
        createdAt: now,
        updatedAt: now,
        taskBriefId: brief.id,
        status: JobStatus.draft,
        domain: brief.domain,
        autonomy: autonomy,
        globalConstraints: brief.constraints,
        globalSuccessCriteria: brief.successCriteria,
        toolPolicy: const ToolPolicy(),
        stopPolicy: const StopPolicy(
          maxTotalPhases: 12,
          maxPhaseRetries: 1,
          stopOnRequiredQuestion: true,
          stopOnLowConfidence: false,
        ),
        phases: const [],
      ),
      state: JobState(
        jobId: jobId,
        chatSessionId: chatSessionId,
        status: JobStatus.blocked,
        updatedAt: now,
        completedPhases: const [],
        failedPhases: const [],
        skippedPhases: const [],
        artifacts: const [],
        openQuestions: openQuestions,
        assumptions: brief.assumptions,
        risks: const [],
        phaseRuns: const [],
        latestSummary:
            'Task brief created. Answer required questions before planning.',
      ),
    );
  }

  Future<ChatCompletionResponse> _completeChatForJob({
    required ChatClient client,
    required String label,
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    JobModelOutputSink? onModelOutput,
  }) async {
    _emitJobModelOutput(
      onModelOutput,
      JobModelOutputEvent(type: JobModelOutputEventType.start, label: label),
    );

    try {
      final completion = await client.completeChatStreamed(
        messages: messages,
        extraParams: extraParams,
        onToken: (token) => _emitJobModelToken(
          onModelOutput: onModelOutput,
          label: label,
          token: token,
        ),
      );
      for (final call in completion.toolCalls) {
        _emitJobModelOutput(
          onModelOutput,
          JobModelOutputEvent(
            type: JobModelOutputEventType.toolCall,
            label: label,
            text:
                '${call.name}${call.id == null ? '' : ' (${call.id})'}\n${call.arguments}',
          ),
        );
      }
      _emitJobModelOutput(
        onModelOutput,
        JobModelOutputEvent(type: JobModelOutputEventType.done, label: label),
      );
      return completion;
    } catch (e) {
      _emitJobModelOutput(
        onModelOutput,
        JobModelOutputEvent(
          type: JobModelOutputEventType.error,
          label: label,
          text: e.toString(),
        ),
      );
      rethrow;
    }
  }

  void _emitJobModelToken({
    required JobModelOutputSink? onModelOutput,
    required String label,
    required ChatToken token,
  }) {
    final reasoning = token.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      _emitJobModelOutput(
        onModelOutput,
        JobModelOutputEvent(
          type: JobModelOutputEventType.reasoning,
          label: label,
          text: reasoning,
        ),
      );
    }
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emitJobModelOutput(
        onModelOutput,
        JobModelOutputEvent(
          type: JobModelOutputEventType.content,
          label: label,
          text: content,
        ),
      );
    }
  }

  void _emitJobModelOutput(
    JobModelOutputSink? sink,
    JobModelOutputEvent event,
  ) {
    sink?.call(event);
  }

  Future<Map<String, dynamic>> _completeJson({
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    JobModelOutputSink? onModelOutput,
  }) async {
    final completion = await _completeChatForJob(
      client: client,
      label: label,
      onModelOutput: onModelOutput,
      messages: [
        ChatMessage(role: 'system', content: system),
        ChatMessage(role: 'user', content: user),
      ],
      extraParams: const {'temperature': 0.1},
    );
    final raw = completion.content.isNotEmpty
        ? completion.content
        : completion.reasoning;
    final parsed = JobJson.tryParseObject(raw);
    if (parsed != null) return parsed;

    final repairedCompletion = await _completeChatForJob(
      client: client,
      label: '$label JSON Repair',
      onModelOutput: onModelOutput,
      messages: [
        ChatMessage(role: 'system', content: 'Return valid JSON only.'),
        ChatMessage(
          role: 'user',
          content:
              'Repair this response into one valid JSON object. Do not add prose.\n\n$raw',
        ),
      ],
      extraParams: const {'temperature': 0},
    );
    final repaired = repairedCompletion.content.isNotEmpty
        ? repairedCompletion.content
        : repairedCompletion.reasoning;
    final repairedParsed = JobJson.tryParseObject(repaired);
    if (repairedParsed != null) return repairedParsed;
    throw const FormatException('Model did not return parseable JSON.');
  }

  TaskBrief _fallbackTaskBrief({
    required String id,
    required DateTime now,
    required String userPrompt,
    required ExecutionMode selectedMode,
  }) {
    final domain = _inferDomain(userPrompt);
    return TaskBrief(
      id: id,
      createdAt: now,
      updatedAt: now,
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      objective: userPrompt,
      successCriteria: const [
        'Produce the requested durable output artifacts.',
        'Keep assumptions explicit.',
        'Separate confirmed work from speculation.',
      ],
      constraints: const [
        'Use workspace-relative paths for file operations.',
        'Do not run destructive commands.',
        'Do not rely on chat history as canonical job memory.',
      ],
      nonGoals: const ['Do not expand beyond the requested task.'],
      assumptions: const [
        'The attached workspace is the canonical workspace for this job.',
        'The user wants practical progress with concise status updates.',
      ],
      clarifyingQuestions: const [],
      recommendedMode: selectedMode,
      recommendedAutonomy: domain == JobDomain.development
          ? AutonomyLevel.checkpointed
          : AutonomyLevel.automatic,
      requiredOutputs: [
        RequiredOutput(
          path: domain == JobDomain.creativeWriting
              ? 'planning-package.md'
              : 'job-output.md',
          required: true,
        ),
      ],
      domain: domain,
      riskLevel: domain == JobDomain.development
          ? RiskLevel.medium
          : RiskLevel.low,
    );
  }

  JobSpec _fallbackJobSpec({
    required TaskBrief taskBrief,
    required String jobId,
    required DateTime now,
    required AutonomyLevel autonomy,
  }) {
    final template = _templateRegistry.selectTemplate(taskBrief);
    if (template != null) {
      return _specFromTemplate(
        template: template,
        taskBrief: taskBrief,
        jobId: jobId,
        now: now,
        autonomy: autonomy,
      );
    }

    final outputs = taskBrief.requiredOutputs.isEmpty
        ? [
            PhaseOutput(
              path: '.agent/jobs/$jobId/job-output.md',
              required: true,
              format: ArtifactFormat.markdown,
            ),
          ]
        : taskBrief.requiredOutputs
              .map(
                (output) => PhaseOutput(
                  path: output.path,
                  required: output.required,
                  description: output.description,
                  format: ArtifactFormat.markdown,
                ),
              )
              .toList();

    return _baseSpec(
      taskBrief: taskBrief,
      jobId: jobId,
      now: now,
      autonomy: autonomy,
      phases: [
        JobPhase(
          id: 'execute',
          title: 'Execute requested task',
          objective: taskBrief.objective,
          status: PhaseStatus.pending,
          inputs: const [],
          expectedOutputs: outputs,
          allowedTools: const [
            'list_directory',
            'read_file',
            'search_files',
            'write_file',
          ],
          terminalPolicy: TerminalPolicy.none,
          completionCriteria: taskBrief.successCriteria,
          review: const ReviewPolicy(
            required: true,
            reviewer: ReviewerType.hybrid,
          ),
          humanCheckpoint: false,
          retryPolicy: const RetryPolicy(),
        ),
      ],
    );
  }

  JobSpec _specFromTemplate({
    required JobTemplate template,
    required TaskBrief taskBrief,
    required String jobId,
    required DateTime now,
    required AutonomyLevel autonomy,
  }) {
    final effectiveAutonomy =
        template.id == BuiltInJobTemplateIds.novelPlanningPack &&
            autonomy == AutonomyLevel.checkpointed
        ? template.defaultAutonomy
        : autonomy;
    return _baseSpec(
      taskBrief: taskBrief,
      jobId: jobId,
      now: now,
      autonomy: effectiveAutonomy,
      phases: template.phases,
      globalConstraints: _mergeUnique([
        ...template.defaultConstraints,
        ...taskBrief.constraints,
      ]),
      globalSuccessCriteria: _mergeUnique([
        ...template.defaultSuccessCriteria,
        ...taskBrief.successCriteria,
      ]),
      promptModules: template.recommendedPromptModules,
    );
  }

  JobSpec _baseSpec({
    required TaskBrief taskBrief,
    required String jobId,
    required DateTime now,
    required AutonomyLevel autonomy,
    required List<JobPhase> phases,
    List<String>? globalConstraints,
    List<String>? globalSuccessCriteria,
    List<String>? promptModules,
  }) {
    return JobSpec(
      version: 1,
      id: jobId,
      title: taskBrief.title,
      description: taskBrief.objective,
      createdAt: now,
      updatedAt: now,
      taskBriefId: taskBrief.id,
      status: JobStatus.planned,
      domain: taskBrief.domain,
      autonomy: autonomy,
      promptModules: promptModules ?? const [],
      globalConstraints: globalConstraints ?? taskBrief.constraints,
      globalSuccessCriteria: globalSuccessCriteria ?? taskBrief.successCriteria,
      toolPolicy: const ToolPolicy(
        defaultAllowed: [
          'calculator',
          'list_directory',
          'read_file',
          'write_file',
          'patch_file',
          'search_files',
          'create_directory',
          'rename_path',
          'delete_path',
          'run_command',
        ],
        defaultDisallowed: [],
        terminal: TerminalToolPolicy(
          allowed: true,
          policy: TerminalPolicy.workspaceMutating,
        ),
      ),
      stopPolicy: const StopPolicy(
        maxTotalPhases: 12,
        maxPhaseRetries: 1,
        stopOnRequiredQuestion: true,
        stopOnLowConfidence: false,
      ),
      phases: phases,
    );
  }

  String _detectProjectType(List<String> rootFiles) {
    if (rootFiles.contains('pubspec.yaml')) return 'dart_flutter';
    if (rootFiles.contains('package.json')) return 'node_javascript';
    if (rootFiles.contains('Cargo.toml')) return 'rust';
    if (rootFiles.contains('go.mod')) return 'go';
    if (rootFiles.contains('pyproject.toml') ||
        rootFiles.contains('requirements.txt')) {
      return 'python';
    }
    if (rootFiles.contains('pom.xml') || rootFiles.contains('build.gradle')) {
      return 'jvm';
    }
    return 'unknown';
  }

  String _newJobId(String prompt) {
    final prefix = _looksLikeNovelPlanningText(prompt)
        ? 'novel_plan'
        : _looksLikeAuditText(prompt)
        ? 'code_audit'
        : 'job';
    final now = DateTime.now().toUtc();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '${prefix}_${timestamp}_${uuid.v7().split('-').first}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled job';
    return singleLine.length <= 72
        ? singleLine
        : '${singleLine.substring(0, 69)}...';
  }

  JobDomain _inferDomain(String prompt) {
    if (_looksLikeNovelPlanningText(prompt)) return JobDomain.creativeWriting;
    if (_looksLikeAuditText(prompt) ||
        RegExp(
          r'\b(code|repo|repository|feature|refactor|bug|test|build|architecture)\b',
          caseSensitive: false,
        ).hasMatch(prompt)) {
      return JobDomain.development;
    }
    if (RegExp(
      r'\b(research|analyse|analyze|sources)\b',
      caseSensitive: false,
    ).hasMatch(prompt)) {
      return JobDomain.research;
    }
    return JobDomain.general;
  }

  bool _looksLikeAuditText(String text) {
    return RegExp(
      r'\b(audit|analyse this codebase|analyze this codebase|review this repo|major issues|critical issues)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _looksLikeNovelPlanningText(String text) {
    return RegExp(
      r'\b(novel|story|chapter outline|characters|worldbuilding|plot spine)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  String _replaceJobId(String value, String jobId) =>
      value.replaceAll('{{job_id}}', jobId);

  Future<WorkspacePath?> _resolveMaybe(
    String rootPath,
    String relativePath,
  ) async {
    try {
      return await _sandbox.resolve(rootPath, relativePath);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _fileExistsAndIsNonEmpty(
    String rootPath,
    String relativePath,
  ) async {
    final resolved = await _resolveMaybe(rootPath, relativePath);
    if (resolved == null) return false;
    final file = File(resolved.absolutePath);
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 0;
  }

  bool _shouldDetectWorkspaceMutations(JobSpec spec, JobPhase phase) =>
      _toolPolicyResolver.shouldDetectWorkspaceMutations(spec, phase);

  Future<_WorkspaceMutationSnapshot> _workspaceMutationSnapshot(
    String rootPath,
  ) async {
    final root = Directory(rootPath);
    final signatures = <String, String>{};
    var truncated = false;
    if (!await root.exists()) {
      return const _WorkspaceMutationSnapshot(signatures: {}, truncated: false);
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (signatures.length >= 2500) {
        truncated = true;
        break;
      }
      if (entity is! File) continue;
      final relativePath = _normaliseRelativePath(
        path.relative(entity.path, from: rootPath),
      );
      if (_ignoreMutationPath(relativePath)) continue;
      final stat = await entity.stat();
      signatures[relativePath] =
          '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    }

    return _WorkspaceMutationSnapshot(
      signatures: signatures,
      truncated: truncated,
    );
  }

  List<String> _workspaceMutationChanges(
    _WorkspaceMutationSnapshot before,
    _WorkspaceMutationSnapshot after,
  ) {
    if (before.truncated || after.truncated) return const [];

    final changed = <String>{};
    for (final entry in after.signatures.entries) {
      if (before.signatures[entry.key] != entry.value) {
        changed.add(entry.key);
      }
    }
    for (final path in before.signatures.keys) {
      if (!after.signatures.containsKey(path)) changed.add(path);
    }
    return changed.toList()..sort();
  }

  bool _ignoreMutationPath(String relativePath) {
    return relativePath == '.agent' ||
        relativePath.startsWith('.agent/') ||
        relativePath == '.git' ||
        relativePath.startsWith('.git/');
  }

  Future<Map<String, String>> _artifactContents(
    String workspaceRoot,
    JobPhase phase,
  ) async {
    final result = <String, String>{};
    for (final output in phase.expectedOutputs) {
      final resolved = await _resolveMaybe(workspaceRoot, output.path);
      if (resolved == null) continue;
      final file = File(resolved.absolutePath);
      if (await file.exists()) {
        result[output.path] = _cap(await file.readAsString(), 16000);
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
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

  String? _terminalPolicyViolation({
    required JobSpec spec,
    required JobPhase phase,
    required Object arguments,
  }) {
    final toolPolicy = spec.toolPolicy.terminal;
    final effectivePolicy = _effectiveTerminalPolicy(spec, phase);
    if (effectivePolicy == TerminalPolicy.none) {
      return 'Terminal access is disabled for this phase.';
    }
    if (toolPolicy?.allowed == false) {
      return 'Terminal access is disabled by the job tool policy.';
    }

    final args = arguments is Map ? arguments : const {};
    final executable = args['command']?.toString().trim() ?? '';
    final rawArgs = args['args'];
    final argList = rawArgs is List
        ? rawArgs.map((arg) => arg.toString()).toList()
        : const <String>[];
    final command = [executable, ...argList].join(' ').trim();
    if (command.isEmpty) return 'Terminal command is empty.';

    final denied = toolPolicy?.deniedCommands ?? const [];
    if (denied.any((prefix) => command.startsWith(prefix))) {
      return 'Terminal command is denied by job policy: $command';
    }

    final allowed = toolPolicy?.allowedCommands ?? const [];
    if (allowed.isNotEmpty &&
        !allowed.any((prefix) => command.startsWith(prefix))) {
      return 'Terminal command is not in the job allow-list: $command';
    }

    final commandClass = _classifyCommand(command);
    if (effectivePolicy == TerminalPolicy.readonly &&
        TerminalCommandClassifier.isClearlyMutating(commandClass)) {
      return 'Readonly phase rejected ${commandClass.wire} terminal command: $command';
    }

    return null;
  }

  Future<_FileChangeCapture?> _captureFileChangeBefore(
    String rootPath,
    String toolName,
    Object arguments,
  ) async {
    final args = arguments is Map ? arguments : const {};
    switch (toolName) {
      case 'write_file':
      case 'patch_file':
      case 'delete_path':
      case 'create_directory':
        final targetPath = args['path']?.toString();
        if (targetPath == null || targetPath.trim().isEmpty) return null;
        return _FileChangeCapture(
          path: targetPath,
          beforeContent: await _readChangeText(rootPath, targetPath),
        );
      case 'rename_path':
        final from = args['from']?.toString();
        final to = args['to']?.toString();
        if (from == null ||
            from.trim().isEmpty ||
            to == null ||
            to.trim().isEmpty) {
          return null;
        }
        return _FileChangeCapture(
          path: to,
          sourcePath: from,
          beforeContent: await _readChangeText(rootPath, from),
        );
      default:
        return null;
    }
  }

  bool _requiresFileEditApproval(String toolName) {
    return const {
      'write_file',
      'patch_file',
      'create_directory',
      'rename_path',
      'delete_path',
    }.contains(toolName);
  }

  Future<PendingFileApproval?> _pendingFileApprovalFromToolCall({
    required String workspaceRoot,
    required JobPhase phase,
    required PhaseRun run,
    required String callId,
    required String toolName,
    required Object arguments,
  }) async {
    final args = arguments is Map ? Map<String, dynamic>.from(arguments) : null;
    if (args == null) return null;

    final now = DateTime.now();
    final pathValue = switch (toolName) {
      'rename_path' => args['to']?.toString(),
      _ => args['path']?.toString(),
    };
    if (pathValue == null || pathValue.trim().isEmpty) return null;

    final sourcePath = toolName == 'rename_path'
        ? args['from']?.toString()
        : null;
    final before = switch (toolName) {
      'rename_path' when sourcePath != null => await _readChangeText(
        workspaceRoot,
        sourcePath,
      ),
      'create_directory' => null,
      _ => await _readChangeText(workspaceRoot, pathValue),
    };
    final after = await _approvalAfterContent(
      toolName: toolName,
      arguments: args,
      before: before,
    );
    if (after == null &&
        toolName != 'delete_path' &&
        toolName != 'rename_path') {
      return null;
    }

    final changeType = switch (toolName) {
      'write_file' => before == null ? 'created' : 'modified',
      'patch_file' => 'modified',
      'delete_path' => 'deleted',
      'create_directory' => 'directory_created',
      'rename_path' => 'renamed',
      _ => 'modified',
    };
    final hunks = _approvalHunks(
      before: before,
      after: after,
      summary: switch (toolName) {
        'create_directory' => 'Create directory $pathValue.',
        'delete_path' => 'Delete $pathValue.',
        'rename_path' => 'Rename ${sourcePath ?? 'path'} to $pathValue.',
        _ => null,
      },
    );
    if (hunks.isEmpty) return null;

    return PendingFileApproval(
      id: 'approval_${uuid.v7()}',
      phaseId: phase.id,
      runId: run.runId,
      toolCallId: callId,
      toolName: toolName,
      arguments: args,
      path: _normaliseRelativePath(pathValue),
      sourcePath: sourcePath == null
          ? null
          : _normaliseRelativePath(sourcePath),
      changeType: changeType,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
      hunks: hunks,
      summary: 'Approve selected hunks before applying $toolName.',
    );
  }

  Future<String?> _approvalAfterContent({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String? before,
  }) async {
    switch (toolName) {
      case 'write_file':
        return arguments['content']?.toString() ?? '';
      case 'patch_file':
        final oldText = arguments['old_text']?.toString() ?? '';
        final newText = arguments['new_text']?.toString() ?? '';
        final replaceAll = arguments['replace_all'] == true;
        if (before == null || oldText.isEmpty || !before.contains(oldText)) {
          return null;
        }
        return replaceAll
            ? before.replaceAll(oldText, newText)
            : before.replaceFirst(oldText, newText);
      case 'delete_path':
        return null;
      case 'rename_path':
        return before;
      case 'create_directory':
        return null;
    }
    return null;
  }

  List<FileApprovalHunk> _approvalHunks({
    required String? before,
    required String? after,
    required String? summary,
  }) {
    final beforeLines = before == null
        ? const <String>[]
        : const LineSplitter().convert(before);
    final afterLines = after == null
        ? const <String>[]
        : const LineSplitter().convert(after);

    if (before == after && summary == null) return const [];
    final rawHunks = _lineDiffHunks(beforeLines, afterLines);
    if (rawHunks.isEmpty && summary != null) {
      return [
        FileApprovalHunk(
          id: 'hunk_${uuid.v7()}',
          status: 'pending',
          oldStart: 0,
          newStart: 0,
          oldLines: beforeLines,
          newLines: afterLines,
          diff: summary,
          summary: summary,
        ),
      ];
    }

    return [
      for (final hunk in rawHunks)
        FileApprovalHunk(
          id: 'hunk_${uuid.v7()}',
          status: 'pending',
          oldStart: hunk.oldStart,
          newStart: hunk.newStart,
          oldLines: hunk.oldLines,
          newLines: hunk.newLines,
          diff: _formatApprovalHunkDiff(hunk),
          summary:
              '+${hunk.newLines.length}/-${hunk.oldLines.length} line changes',
        ),
    ];
  }

  List<_RawApprovalHunk> _lineDiffHunks(
    List<String> beforeLines,
    List<String> afterLines,
  ) {
    if (beforeLines.isEmpty && afterLines.isEmpty) return const [];
    if (beforeLines.length * afterLines.length > 40000) {
      return [
        _RawApprovalHunk(
          oldStart: 0,
          newStart: 0,
          oldLines: beforeLines,
          newLines: afterLines,
        ),
      ];
    }

    final matrix = List.generate(
      beforeLines.length + 1,
      (_) => List<int>.filled(afterLines.length + 1, 0),
    );
    for (var i = beforeLines.length - 1; i >= 0; i--) {
      for (var j = afterLines.length - 1; j >= 0; j--) {
        matrix[i][j] = beforeLines[i] == afterLines[j]
            ? matrix[i + 1][j + 1] + 1
            : matrix[i + 1][j] > matrix[i][j + 1]
            ? matrix[i + 1][j]
            : matrix[i][j + 1];
      }
    }

    final hunks = <_RawApprovalHunk>[];
    var i = 0;
    var j = 0;
    int? oldStart;
    int? newStart;
    final oldLines = <String>[];
    final newLines = <String>[];

    void flush() {
      if (oldStart == null || newStart == null) return;
      if (oldLines.isNotEmpty || newLines.isNotEmpty) {
        hunks.add(
          _RawApprovalHunk(
            oldStart: oldStart!,
            newStart: newStart!,
            oldLines: [...oldLines],
            newLines: [...newLines],
          ),
        );
      }
      oldStart = null;
      newStart = null;
      oldLines.clear();
      newLines.clear();
    }

    void startIfNeeded() {
      oldStart ??= i;
      newStart ??= j;
    }

    while (i < beforeLines.length || j < afterLines.length) {
      if (i < beforeLines.length &&
          j < afterLines.length &&
          beforeLines[i] == afterLines[j]) {
        flush();
        i++;
        j++;
      } else if (j < afterLines.length &&
          (i == beforeLines.length || matrix[i][j + 1] >= matrix[i + 1][j])) {
        startIfNeeded();
        newLines.add(afterLines[j]);
        j++;
      } else if (i < beforeLines.length) {
        startIfNeeded();
        oldLines.add(beforeLines[i]);
        i++;
      }
    }
    flush();
    return hunks;
  }

  String _formatApprovalHunkDiff(_RawApprovalHunk hunk) {
    final oldLength = hunk.oldLines.length;
    final newLength = hunk.newLines.length;
    final lines = <String>[
      '@@ -${hunk.oldStart + 1},$oldLength +${hunk.newStart + 1},$newLength @@',
      for (final line in hunk.oldLines) '-$line',
      for (final line in hunk.newLines) '+$line',
    ];
    return _cap(lines.join('\n'), 12000);
  }

  Future<FileChangeSummary?> _buildFileChangeSummary(
    String rootPath,
    String toolName,
    Object arguments,
    _FileChangeCapture? before,
  ) async {
    if (before == null) return null;
    final args = arguments is Map ? arguments : const {};
    final targetPath = switch (toolName) {
      'rename_path' => args['to']?.toString() ?? before.path,
      _ => args['path']?.toString() ?? before.path,
    };
    if (targetPath.trim().isEmpty) return null;

    final afterContent = switch (toolName) {
      'delete_path' || 'create_directory' => null,
      _ => await _readChangeText(rootPath, targetPath),
    };
    final changeType = switch (toolName) {
      'write_file' => before.beforeContent == null ? 'created' : 'modified',
      'patch_file' => 'modified',
      'delete_path' => 'deleted',
      'create_directory' => 'directory_created',
      'rename_path' => 'renamed',
      _ => 'modified',
    };
    final diff = _fileChangeDiff(
      path: targetPath,
      before: before.beforeContent,
      after: afterContent,
    );
    final summary = switch (toolName) {
      'rename_path' when before.sourcePath != null =>
        'Renamed ${before.sourcePath} to $targetPath.',
      'create_directory' => 'Created directory $targetPath.',
      'delete_path' => 'Deleted $targetPath.',
      _ => 'Changed $targetPath with $toolName.',
    };

    return FileChangeSummary(
      path: _normaliseRelativePath(targetPath),
      changeType: changeType,
      toolName: toolName,
      addedLines: diff.addedLines,
      removedLines: diff.removedLines,
      diff: diff.diff.trim().isEmpty ? null : _cap(diff.diff, 12000),
      summary: summary,
    );
  }

  Future<FileChangeSummary> _applyApprovedFileHunks(
    String rootPath,
    PendingFileApproval approval,
    Set<String> approvedHunkIds,
  ) async {
    final approvedHunks = approval.hunks
        .where((hunk) => approvedHunkIds.contains(hunk.id))
        .toList();
    if (approvedHunks.isEmpty) {
      throw StateError('No hunks were approved.');
    }

    final before = await _readChangeText(
      rootPath,
      approval.toolName == 'rename_path'
          ? approval.sourcePath ?? approval.path
          : approval.path,
    );

    switch (approval.toolName) {
      case 'create_directory':
        final resolved = await _sandbox.resolve(
          rootPath,
          approval.path,
          mustExist: false,
        );
        await Directory(resolved.absolutePath).create(recursive: true);
        break;
      case 'delete_path':
        final resolved = await _sandbox.resolve(rootPath, approval.path);
        final type = await FileSystemEntity.type(resolved.absolutePath);
        if (type == FileSystemEntityType.directory) {
          await Directory(
            resolved.absolutePath,
          ).delete(recursive: approval.arguments['recursive'] == true);
        } else {
          await File(resolved.absolutePath).delete();
        }
        break;
      case 'rename_path':
        final sourcePath = approval.sourcePath;
        if (sourcePath == null || sourcePath.trim().isEmpty) {
          throw StateError('Rename approval is missing source path.');
        }
        final source = await _sandbox.resolve(rootPath, sourcePath);
        final destination = await _sandbox.resolve(
          rootPath,
          approval.path,
          mustExist: false,
        );
        await Directory(
          path.dirname(destination.absolutePath),
        ).create(recursive: true);
        final type = await FileSystemEntity.type(source.absolutePath);
        if (type == FileSystemEntityType.directory) {
          await Directory(source.absolutePath).rename(destination.absolutePath);
        } else {
          await File(source.absolutePath).rename(destination.absolutePath);
        }
        break;
      default:
        final content = _applyTextHunks(before ?? '', approvedHunks);
        final resolved = await _sandbox.resolve(
          rootPath,
          approval.path,
          mustExist: false,
        );
        final file = File(resolved.absolutePath);
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
        break;
    }

    final after = approval.toolName == 'delete_path'
        ? null
        : await _readChangeText(rootPath, approval.path);
    final diff = _fileChangeDiff(
      path: approval.path,
      before: before,
      after: after,
    );
    return FileChangeSummary(
      path: approval.path,
      changeType: approval.changeType,
      toolName: approval.toolName,
      addedLines: diff.addedLines,
      removedLines: diff.removedLines,
      diff: diff.diff.trim().isEmpty ? null : _cap(diff.diff, 12000),
      summary:
          'Applied ${approvedHunks.length}/${approval.hunks.length} approved hunk${approvedHunks.length == 1 ? '' : 's'}.',
    );
  }

  String _applyTextHunks(String currentContent, List<FileApprovalHunk> hunks) {
    var lines = currentContent.isEmpty
        ? <String>[]
        : const LineSplitter().convert(currentContent);
    final ordered = [...hunks]
      ..sort((a, b) => b.oldStart.compareTo(a.oldStart));
    for (final hunk in ordered) {
      final index = _hunkApplyIndex(lines, hunk);
      if (index < 0) {
        throw StateError('Approved hunk no longer matches ${hunk.id}.');
      }
      lines = [
        ...lines.take(index),
        ...hunk.newLines,
        ...lines.skip(index + hunk.oldLines.length),
      ];
    }
    return lines.join('\n');
  }

  int _hunkApplyIndex(List<String> currentLines, FileApprovalHunk hunk) {
    if (_lineSliceMatches(currentLines, hunk.oldStart, hunk.oldLines)) {
      return hunk.oldStart;
    }
    for (var i = 0; i <= currentLines.length - hunk.oldLines.length; i++) {
      if (_lineSliceMatches(currentLines, i, hunk.oldLines)) return i;
    }
    return hunk.oldLines.isEmpty && hunk.oldStart <= currentLines.length
        ? hunk.oldStart
        : -1;
  }

  bool _lineSliceMatches(List<String> lines, int start, List<String> expected) {
    if (start < 0 || start + expected.length > lines.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (lines[start + i] != expected[i]) return false;
    }
    return true;
  }

  bool _approvalWritesFile(PendingFileApproval approval) {
    return const {
      'write_file',
      'create_directory',
      'rename_path',
    }.contains(approval.toolName);
  }

  bool _approvalPatchesFile(PendingFileApproval approval) {
    return const {'patch_file', 'delete_path'}.contains(approval.toolName);
  }

  Future<String?> _readChangeText(String rootPath, String relativePath) async {
    try {
      final resolved = await _sandbox.resolve(
        rootPath,
        relativePath,
        mustExist: false,
      );
      final type = await FileSystemEntity.type(resolved.absolutePath);
      if (type != FileSystemEntityType.file) return null;
      final file = File(resolved.absolutePath);
      if (await file.length() > WorkspaceSandbox.maxReadBytes) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  _FileChangeDiff _fileChangeDiff({
    required String path,
    required String? before,
    required String? after,
  }) {
    if (before == null && after == null) {
      return const _FileChangeDiff(diff: '', addedLines: 0, removedLines: 0);
    }
    final beforeLines = before == null
        ? const <String>[]
        : const LineSplitter().convert(before);
    final afterLines = after == null
        ? const <String>[]
        : const LineSplitter().convert(after);
    if (before == after) {
      return const _FileChangeDiff(diff: '', addedLines: 0, removedLines: 0);
    }
    if (beforeLines.length * afterLines.length > 40000) {
      final added = afterLines.length;
      final removed = beforeLines.length;
      return _FileChangeDiff(
        addedLines: added,
        removedLines: removed,
        diff:
            'Diff omitted for $path because the file is too large for inline review. Lines before: ${beforeLines.length}. Lines after: ${afterLines.length}.',
      );
    }

    final matrix = List.generate(
      beforeLines.length + 1,
      (_) => List<int>.filled(afterLines.length + 1, 0),
    );
    for (var i = beforeLines.length - 1; i >= 0; i--) {
      for (var j = afterLines.length - 1; j >= 0; j--) {
        matrix[i][j] = beforeLines[i] == afterLines[j]
            ? matrix[i + 1][j + 1] + 1
            : matrix[i + 1][j] > matrix[i][j + 1]
            ? matrix[i + 1][j]
            : matrix[i][j + 1];
      }
    }

    final lines = <String>['--- $path', '+++ $path'];
    var added = 0;
    var removed = 0;
    var i = 0;
    var j = 0;
    while (i < beforeLines.length || j < afterLines.length) {
      if (i < beforeLines.length &&
          j < afterLines.length &&
          beforeLines[i] == afterLines[j]) {
        lines.add(' ${beforeLines[i]}');
        i++;
        j++;
      } else if (j < afterLines.length &&
          (i == beforeLines.length || matrix[i][j + 1] >= matrix[i + 1][j])) {
        lines.add('+${afterLines[j]}');
        added++;
        j++;
      } else if (i < beforeLines.length) {
        lines.add('-${beforeLines[i]}');
        removed++;
        i++;
      }
      if (lines.length >= 220) {
        lines.add('... diff truncated ...');
        break;
      }
    }

    return _FileChangeDiff(
      diff: lines.join('\n'),
      addedLines: added,
      removedLines: removed,
    );
  }

  void _recordToolSideEffects({
    required String toolName,
    required Object arguments,
    required String resultJson,
    required Set<String> filesRead,
    required Set<String> filesWritten,
    required Set<String> filesPatched,
    required Set<String> terminalCommands,
  }) {
    final args = arguments is Map ? arguments : const {};
    final result = JobJson.decodeJsonOrString(resultJson);
    final resultMap = result is Map ? result : const {};
    final resultPath = resultMap['path']?.toString();
    final argPath = args['path']?.toString();

    switch (toolName) {
      case 'read_file':
        if (resultPath != null) filesRead.add(resultPath);
        if (argPath != null) filesRead.add(argPath);
        break;
      case 'write_file':
      case 'create_directory':
        if (resultPath != null) filesWritten.add(resultPath);
        if (argPath != null) filesWritten.add(argPath);
        break;
      case 'patch_file':
        if (resultPath != null) filesPatched.add(resultPath);
        if (argPath != null) filesPatched.add(argPath);
        break;
      case 'rename_path':
        final to = resultMap['to']?.toString() ?? args['to']?.toString();
        if (to != null) filesWritten.add(to);
        break;
      case 'delete_path':
        if (resultPath != null) filesPatched.add(resultPath);
        if (argPath != null) filesPatched.add(argPath);
        break;
      case 'run_command':
        final command = resultMap['command']?.toString();
        if (command != null) {
          terminalCommands.add(command);
        } else {
          final executable = args['command']?.toString() ?? '';
          final rawArgs = args['args'];
          final argList = rawArgs is List
              ? rawArgs.map((arg) => arg.toString()).join(' ')
              : '';
          terminalCommands.add('$executable $argList'.trim());
        }
        break;
    }
  }

  TerminalCommandClass _classifyCommand(String command) =>
      TerminalCommandClassifier.classify(command);

  String _normaliseRelativePath(String value) {
    final normalised = path.posix.normalize(value.replaceAll('\\', '/'));
    if (normalised == '.') return normalised;
    return normalised.startsWith('./') ? normalised.substring(2) : normalised;
  }

  String _phaseSummary(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return 'Phase completed without a text summary.';
    return trimmed.length <= 300 ? trimmed : '${trimmed.substring(0, 297)}...';
  }

  List<String> _withUnique(List<String> values, String? value) {
    if (value == null || values.contains(value)) return values;
    return [...values, value];
  }

  List<String> _mergeUnique(Iterable<String> values) {
    final seen = <String>{};
    final merged = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      merged.add(trimmed);
    }
    return merged;
  }

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n... truncated ...';
  }
}

class _PhaseExecutionOutput {
  final String finalText;
  final List<ToolCallRecord> toolCalls;
  final List<String> filesRead;
  final List<String> filesWritten;
  final List<String> filesPatched;
  final List<FileChangeSummary> fileChanges;
  final List<PendingFileApproval> pendingApprovals;
  final List<String> terminalCommands;

  const _PhaseExecutionOutput({
    required this.finalText,
    required this.toolCalls,
    required this.filesRead,
    required this.filesWritten,
    required this.filesPatched,
    required this.fileChanges,
    required this.pendingApprovals,
    required this.terminalCommands,
  });
}

class _FileChangeCapture {
  final String path;
  final String? sourcePath;
  final String? beforeContent;

  const _FileChangeCapture({
    required this.path,
    this.sourcePath,
    this.beforeContent,
  });
}

class _FileChangeDiff {
  final String diff;
  final int addedLines;
  final int removedLines;

  const _FileChangeDiff({
    required this.diff,
    required this.addedLines,
    required this.removedLines,
  });
}

class _RawApprovalHunk {
  final int oldStart;
  final int newStart;
  final List<String> oldLines;
  final List<String> newLines;

  const _RawApprovalHunk({
    required this.oldStart,
    required this.newStart,
    required this.oldLines,
    required this.newLines,
  });
}

class _RecoveryResult {
  final JobSnapshot snapshot;
  final bool blocking;

  const _RecoveryResult({required this.snapshot, required this.blocking});
}

class _RecoveryIssue {
  final String phaseId;
  final String message;
  final String? artifactPath;

  const _RecoveryIssue({
    required this.phaseId,
    required this.message,
    this.artifactPath,
  });
}

class _PhaseBlockedException implements Exception {
  final String message;

  const _PhaseBlockedException(this.message);

  @override
  String toString() => message;
}

class _WorkspaceMutationSnapshot {
  final Map<String, String> signatures;
  final bool truncated;

  const _WorkspaceMutationSnapshot({
    required this.signatures,
    required this.truncated,
  });
}

const String _promptRefinerSystemInstruction = '''
You are a task refinement agent.

Convert the user's request into a precise TaskBrief suitable for an AI job runner.

Do not perform the task.
Do not solve the task.
Do not inspect the full workspace.
Ask at most 3 clarifying questions.
Prefer reasonable assumptions over unnecessary questions.
Mark a question as required only if execution would likely fail or produce the wrong kind of result without the answer.

Return only valid JSON with:
- title
- objective
- successCriteria
- constraints
- nonGoals
- assumptions
- clarifyingQuestions
- recommendedMode
- recommendedAutonomy
- requiredOutputs
- domain
- riskLevel
''';

const String _jobPlannerSystemInstruction = '''
You are a job planning agent.

Convert a TaskBrief into a structured JobSpec that can be executed phase by phase.

Do not execute the task.
Do not solve the task.
Do not invent unavailable tools.
Use only tools listed in available_tools.
Prefer fewer, clearer phases over many vague phases.

Each phase must include:
- id
- title
- objective
- inputs
- expectedOutputs
- allowedTools
- terminalPolicy
- completionCriteria
- stopPolicy when needed
- review policy
- humanCheckpoint flag

The plan must be suitable for a weaker local model:
- narrow phase objectives
- explicit artifacts
- strict tool scope
- clear stop conditions
- low reliance on chat history

Return only valid JSON matching the JobSpec schema.
''';

const String _replannerSystemInstruction = '''
You are updating an existing job plan.

Do not discard completed or skipped phases.
Do not redo completed work unless explicitly instructed by the user.
Use the current JobState, artifacts, and review results.
Revise only the remaining phases.
Preserve the original objective and constraints unless the user changed them.
Use only available tools.

Return only valid JSON matching the JobSpec schema.
''';

const String _phaseExecutorInstruction = '''
You are executing one phase of a larger job.

Do not attempt to complete the entire job.
Complete only the current phase.
Use only the tools exposed to you.
If expected outputs are files and write_file is available, write them.
If write_file is not available, return the complete content for the primary expected output.
When complete, provide a short phase summary and stop.
''';

const String _reviewerSystemInstruction = '''
You are reviewing the output of one phase of a larger AI agent job.

Do not continue the job.
Do not perform the task yourself.
Evaluate whether the phase output satisfies the phase objective and completion criteria.

Be strict but fair.
Do not fail the phase for minor style preferences.
Fail the phase if required outputs are missing, constraints were violated, or the output does not support the next phase.

Return only valid JSON.
''';
