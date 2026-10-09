part of 'task_execution_coordinator.dart';

extension TaskExecutionPlanning on TaskPlanningUseCase {
  int _taskPlanningStepLimit(TaskAggregate task) {
    final effortLimit = switch (task.effort) {
      TaskEffort.small => 1,
      TaskEffort.medium => 4,
      TaskEffort.large => 6,
    };
    return task.steps.length > effortLimit
        ? task.steps.length.clamp(1, 6).toInt()
        : effortLimit;
  }

  Future<TaskIncrementalPlanAttempt> _completeTaskPlanWithCommands({
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
    final maxSteps = planningContext?.maxSteps.clamp(1, 6).toInt() ?? 3;
    final context = TaskPlanningToolContext(
      task: task,
      workspaceRoot: workspace.rootPath,
      maxSteps: maxSteps,
      projectGoal: planningContext?.projectGoal ?? '',
      // _taskPlanningSeed already places the effective acceptance on the
      // source task. Passing it again would duplicate refs in the builder's
      // draft; the context still exposes it through the source task.
      acceptance: const [],
      inheritedAcceptance: planningContext?.acceptance ?? const [],
      taskNumber: planningContext?.taskAgentNumber ?? 1,
      criterionAgentNumbers: planningContext?.criterionAgentNumbers ?? const {},
      taskIdsByAgentNumber: {
        for (final entry
            in (planningContext?.taskAgentNumbers ?? const <String, int>{})
                .entries)
          entry.value: entry.key,
      },
      milestoneIdsByAgentNumber: {
        for (final entry
            in (planningContext?.milestoneAgentNumbers ?? const <String, int>{})
                .entries)
          entry.value: entry.key,
      },
      outOfScope: planningContext?.outOfScope ?? const [],
      readPaths: planningContext?.readPaths ?? const [],
      writePaths: planningContext?.writePaths ?? const [],
      requireDeclaredWriteBoundary: planningContext != null,
      persistTask: (candidate) =>
          _context.persistTask(workspace.rootPath, candidate),
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
Plan this task with the task planning tools. Hermes owns task number
${context.taskNumber}; never use it as a step ID and never supply persistent IDs.

For a bounded Project task, the Project goal is context only: do not plan or
perform the whole Project. Plan only the selected task objective.

User request:
$userPrompt

Planning frontier:
${_encoder.convert(TaskPlanningFrontierBuilder.build(task: task, taskNumber: context.taskNumber, metadata: metadata, planningContext: planningContext, inheritedAcceptance: planningContext?.acceptance ?? const [], criterionAgentNumbers: planningContext?.criterionAgentNumbers ?? const {}, taskAgentNumbers: planningContext?.taskAgentNumbers ?? const {}, milestoneAgentNumbers: planningContext?.milestoneAgentNumbers ?? const {}))}

Workspace context is read-only task context. Do not mutate the project
workspace graph directly; durable graph changes belong to the project planner
or an explicit user command. Task memories remain separate from that graph.
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );

    return TaskIncrementalPlanAttempt(
      task: context.committedTask,
      usedPlanningTools: context.committedTask != null,
      planningMetrics: planningResult.planningMetrics,
      planningError: planningResult.error,
    );
  }

  TaskAggregate _taskPlanningSeed({
    required String taskId,
    required String userPrompt,
    required TaskPlanningContext? planningContext,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  }) {
    final acceptance = _effectiveAcceptance(planningContext);
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
    return TaskAggregate(
      id: taskId,
      title: title,
      originalPrompt: userPrompt,
      objective: objective,
      constraints: constraints,
      acceptance: acceptance,
      readPaths: planningContext?.readPaths ?? const [],
      writePaths: planningContext?.writePaths ?? const [],
      outOfScope: planningContext?.outOfScope ?? const [],
      context: planningContext?.knownFacts ?? const [],
      status: TaskStatus.paused,
      chatSessionId: chatSessionId,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<AcceptanceItem> _effectiveAcceptance(
    TaskPlanningContext? planningContext,
  ) {
    final supplied = planningContext?.acceptance ?? const <AcceptanceItem>[];
    return supplied;
  }

  /// Converts an already-bounded Project task directly into one executable
  /// task step without invoking the Task Planner model.

  TaskAggregate _fallbackReplannedTask(
    TaskAggregate snapshot,
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
    var replacement = _fallbackExecutionStep(
      snapshot.id,
      snapshot.objective,
      snapshot.acceptance,
    );
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

  TaskStepExecutionOutput _parseStepOutput(
    String raw,
    TaskAggregate task,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
    TaskExecutionRequest executionRequest,
  ) {
    final json = TaskJson.tryParseObject(raw);
    if (json == null) {
      return TaskStepExecutionOutput(
        status: TaskStepExecutionStatus.failed,
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
      return TaskStepExecutionOutput(
        status: TaskStepExecutionStatus.failed,
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
      fallback: status == TaskStepExecutionStatus.completed
          ? 'Step completed.'
          : 'Step stopped.',
    );
    final rawUserQuestion = json['userQuestion'] ?? json['user_question'];
    final agentQuestion = const QuestionProtocolAdapter().decode(
      rawUserQuestion,
    );
    return TaskStepExecutionOutput(
      status: status,
      runStatus: switch (status) {
        TaskStepExecutionStatus.completed => TaskRunStatus.completed,
        TaskStepExecutionStatus.blocked => TaskRunStatus.blocked,
        TaskStepExecutionStatus.failed => TaskRunStatus.failed,
        TaskStepExecutionStatus.needsReplan => TaskRunStatus.needsReplan,
      },
      summary: summary,
      memoryUpdate: jsonString(json['memoryUpdate'] ?? json['memory_update']),
      artifacts: artifacts,
      evidenceClaims: _evidenceClaimsFromJson(
        json['evidenceClaims'] ?? json['evidence_claims'],
        acceptance: executionRequest.acceptance.isNotEmpty
            ? executionRequest.acceptance
            : task.acceptance,
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

  TaskAggregate _completeStep(
    TaskAggregate snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
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

  TaskAggregate _blockStep(
    TaskAggregate snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
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

  TaskAggregate _failStep(
    TaskAggregate snapshot,
    TaskStep step,
    TaskStepExecutionOutput output,
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

  TaskAggregate _advanceAfterStep(TaskAggregate snapshot, DateTime now) {
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

  TaskAggregate _markCompleted(TaskAggregate snapshot) {
    final now = DateTime.now();
    return snapshot.copyWith(
      status: TaskStatus.completed,
      currentStepId: null,
      completedAt: now,
      updatedAt: now,
    );
  }

  TaskAggregate _replaceStep(
    TaskAggregate snapshot,
    String stepId,
    TaskStep step,
  ) {
    final index = snapshot.steps.indexWhere((item) => item.id == stepId);
    if (index < 0) return snapshot;
    final steps = [...snapshot.steps];
    steps[index] = step;
    return snapshot.copyWith(steps: steps);
  }

  TaskAggregate _replaceLastRun(TaskAggregate snapshot, TaskRun run) {
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
    TaskAggregate task,
    TaskStep step,
    WorkspaceAttachment workspace,
    TaskExecutionRequest executionRequest,
  ) {
    final acceptance = executionRequest.acceptance.isNotEmpty
        ? executionRequest.acceptance
        : task.acceptance;
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

Acceptance:
${_encoder.convert(acceptance.map((item) => snakeCaseWire(ModelJson.encode(item))).toList())}

Linked Project criteria:
${executionRequest.criteria.isEmpty ? _encoder.convert({for (final item in acceptance) ...item.criterionIds}.toList()) : _encoder.convert(executionRequest.criteria.map((item) => snakeCaseWire(ModelJson.encode(item))).toList())}

Verifier status is derived by Hermes from the acceptance items. Do not invent
gate or evidence identifiers and do not claim a verifier passed without its
observed result.

Current memory:
${task.memorySummary.trim().isEmpty ? 'None yet.' : task.memorySummary}

Full plan:
${_encoder.convert(task.steps.map((item) => snakeCaseWire(ModelJson.encode(item))).toList())}

Current step:
${_encoder.convert(snakeCaseWire(ModelJson.encode(step)))}

Available artifact inputs:
$availableArtifacts

Step tool permissions:
${_stepToolPermissionText(task, step, workspace)}

Previous run summaries:
${previousRuns.trim().isEmpty ? 'None yet.' : previousRuns}

This ${isFinalPlannedStep ? 'is' : 'is not'} the final planned task step.
${acceptance.any((item) => item.criterionIds.isNotEmpty) ? 'Project evidence is derived from successful workspace calls and evaluated acceptance verifiers. Your summary is advisory; do not claim that a verifier passed unless its result confirms it.' : 'Do not claim work that has not been verified.'}

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
    TaskAggregate task,
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

  String _buildAvailableArtifactInputs(TaskAggregate task, TaskStep step) {
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

  TaskAggregate _normaliseEditedTask(
    TaskAggregate candidate,
    TaskAggregate original,
    DateTime now,
  ) {
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
      steps: steps,
      status: currentStepId == null ? TaskStatus.completed : TaskStatus.paused,
      currentStepId: currentStepId,
      createdAt: original.createdAt,
      updatedAt: now,
    );
  }

  List<TaskEvidenceClaim> _evidenceClaimsFromJson(
    Object? value, {
    List<AcceptanceItem> acceptance = const [],
  }) {
    if (value is! List || acceptance.isEmpty) {
      return const [];
    }
    final acceptanceByRef = {for (final item in acceptance) item.ref: item};
    final seen = <String>{};
    final claims = <TaskEvidenceClaim>[];
    for (final raw in value.whereType<Map>()) {
      final map = Map<String, dynamic>.from(raw);
      final acceptanceRef = jsonNullableString(
        map['acceptanceRef'] ?? map['acceptance_ref'],
      );
      final acceptanceItem = acceptanceRef == null
          ? null
          : acceptanceByRef[acceptanceRef];
      if (acceptanceItem == null) continue;
      // Model claims are keyed only by the canonical acceptance ref. Criteria
      // and compiled expectation IDs are Hermes-owned and are never accepted
      // as model-authored routing inputs.
      final claim = jsonString(map['claim']);
      final sourceRef = jsonString(map['sourceRef'] ?? map['source_ref']);
      if (claim.isEmpty || sourceRef.isEmpty) {
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
      for (final criterionId in acceptanceItem.criterionIds) {
        final key = '$criterionId|${evidenceType.name}|$sourceRef|$claim';
        if (!seen.add(key)) continue;
        claims.add(
          TaskEvidenceClaim(
            criterionId: criterionId,
            acceptanceRef: acceptanceItem.ref,
            claim: claim,
            evidenceType: evidenceType,
            sourceRef: sourceRef,
            suggestedStrength: strength,
          ),
        );
      }
    }
    return claims;
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
      assumptions: brief.assumptions,
      questions: brief.questions.take(3).toList(),
    );
  }

  RefinedTaskBrief _fallbackBrief(String prompt) {
    return RefinedTaskBrief(
      title: _titleFromPrompt(prompt),
      goal: prompt,
      assumptions: const ['Use the attached workspace as the source of truth.'],
    );
  }

  TaskAggregate _fallbackTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required DateTime now,
  }) {
    const acceptance = [
      AcceptanceItem(
        ref: 'task-complete',
        statement: 'Complete the requested task.',
        verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
      ),
    ];
    final step = _fallbackExecutionStep(taskId, userPrompt, acceptance);
    return TaskAggregate(
      id: taskId,
      title: _titleFromPrompt(userPrompt),
      originalPrompt: userPrompt,
      objective: userPrompt,
      constraints: const ['Stay within the attached workspace.'],
      acceptance: acceptance,
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

  TaskAggregate _fallbackProjectBoundedTask({
    required String taskId,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    required DateTime now,
  }) {
    final acceptance = _effectiveAcceptance(planningContext);
    final artifactPaths = [
      for (final item in acceptance)
        for (final verifier in item.verifiers)
          if (verifier.kind == AcceptanceVerifierKind.artifact &&
              verifier.path?.trim().isNotEmpty == true)
            TaskArtifact(
              path: verifier.path!.replaceAll('{{task_id}}', taskId),
              description: verifier.description ?? item.statement,
              kind: verifier.artifactKind,
              stepId: 'execute_project_task',
            ),
    ];
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
      acceptanceRefs: [for (final item in acceptance) item.ref],
      status: TaskStepStatus.pending,
    );
    return TaskAggregate(
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
      acceptance: acceptance,
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

  TaskStep _fallbackExecutionStep(
    String taskId,
    String objective,
    Iterable<AcceptanceItem> acceptance,
  ) {
    final artifacts = <TaskArtifact>[];
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
      acceptanceRefs: [for (final item in acceptance) item.ref],
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

  TaskStepExecutionStatus? _parseStepExecutionStatusStrict(String raw) {
    return switch (raw) {
      'blocked' => TaskStepExecutionStatus.blocked,
      'needs_replan' || 'replan' => TaskStepExecutionStatus.needsReplan,
      'failed' || 'failure' => TaskStepExecutionStatus.failed,
      'completed' || 'complete' => TaskStepExecutionStatus.completed,
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
}
