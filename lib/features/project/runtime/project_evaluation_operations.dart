// ignore_for_file: unused_element, unused_field
part of 'project_runtime_collaborators.dart';

extension ProjectEvaluationOperations on ProjectRuntimeContext {
  Future<ProjectDocument> _applyCompletionEvaluation({
    required ModelCompletionPort client,
    required ProjectDocument project,
    required String baseSystemPrompt,
    ProjectCompletionReviewReason? reviewReason,
    String? reviewMilestoneId,
    ModelOutputSink? onModelOutput,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    CancellationToken? cancellationToken,
  }) async {
    if (project.isTerminal ||
        project.status == ProjectStatus.blocked ||
        project.openQuestions.isNotEmpty ||
        project.recoveryIncidents.any(
          (incident) =>
              incident.status == ProjectRecoveryIncidentStatus.active ||
              incident.status == ProjectRecoveryIncidentStatus.exhausted,
        ) ||
        _projectFailureBudgetCount(
              project.tasks
                  .where((task) => task.status == TaskStatus.failed)
                  .toList(),
              project.recoveryIncidents,
            ) >=
            project.maxFailedTasks) {
      return project;
    }
    final now = DateTime.now();
    final remainingByState = _remainingCriteria(project);
    if (remainingByState.isEmpty) {
      return _completeProjectFromEvidence(project, now);
    }
    if (reviewReason == null || !_hasReviewableCriterionEvidence(project)) {
      return _transitionProject(
        snapshot: project,
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: 'No completion review is required at this boundary.',
        now: now,
      );
    }

    final evidenceFingerprint = _completionEvidenceFingerprint(project);
    final checkpoint = project.completionReviewCheckpoint;
    if (checkpoint?.reason == reviewReason &&
        checkpoint?.evidenceFingerprint == evidenceFingerprint &&
        checkpoint?.milestoneId == reviewMilestoneId) {
      return _transitionProject(
        snapshot: project,
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: 'Completion evidence is unchanged since the last review.',
        now: now,
      );
    }

    final assessment = await _completionEvaluator.evaluateCompletion(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: project,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final assessedProject = project.copyWith(
      completionReviewCheckpoint: ProjectCompletionReviewCheckpoint(
        reason: reviewReason,
        evidenceFingerprint: evidenceFingerprint,
        milestoneId: reviewMilestoneId,
        reviewedAt: now,
      ),
      diagnostics: project.diagnostics.copyWith(
        projectModelCalls: project.diagnostics.projectModelCalls + 1,
      ),
    );
    if (assessment.openQuestions.isNotEmpty) {
      final filtered = _filterProjectQuestions(
        assessment.openQuestions,
        autonomy: questionAutonomy,
      );
      if (filtered.blocking.isEmpty) {
        final resumed = _transitionProject(
          snapshot: assessedProject.copyWith(blocker: null, updatedAt: now),
          to: ProjectStatus.active,
          trigger: ProjectLifecycleTrigger.taskReview,
          reason: 'Completion review questions were resolved automatically.',
          now: now,
        );
        return _recordAssumptions(
          resumed,
          filtered.assumptions,
          sourceId: 'completion_review',
        );
      }
      final waiting = _transitionProject(
        snapshot: assessedProject.copyWith(
          openQuestions: filtered.blocking,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.question,
            message: filtered.blocking.first.question,
            createdAt: now,
          ),
          diagnostics: assessedProject.diagnostics.copyWith(
            userQuestions:
                assessedProject.diagnostics.userQuestions +
                filtered.blocking.length,
          ),
          updatedAt: now,
        ),
        to: ProjectStatus.waitingForUser,
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: filtered.blocking.first.question,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.question,
          message: filtered.blocking.first.question,
          createdAt: now,
        ),
        now: now,
      );
      return _recordAssumptions(
        waiting,
        filtered.assumptions,
        sourceId: 'completion_review',
      );
    }
    var reviewed = _criterionEvaluator.applyModelReview(
      assessedProject,
      projectComplete: assessment.complete,
      remainingCriteria: assessment.remainingCriteria,
      supportedCriterionIds: assessment.supportedCriterionIds,
      rationale: assessment.finalSummary,
      evaluatedAt: now,
    );
    reviewed = reviewed.copyWith(
      completionReviewCheckpoint: ProjectCompletionReviewCheckpoint(
        reason: reviewReason,
        evidenceFingerprint: _completionEvidenceFingerprint(reviewed),
        milestoneId: reviewMilestoneId,
        reviewedAt: now,
      ),
    );
    if (_remainingCriteria(reviewed).isEmpty) {
      return _completeProjectFromEvidence(
        reviewed,
        now,
        summary: assessment.finalSummary,
      );
    }
    return _transitionProject(
      snapshot: reviewed,
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.taskReview,
      reason: 'Completion review left criteria outstanding.',
      now: now,
    );
  }

  bool _hasReviewableCriterionEvidence(ProjectDocument project) {
    for (final criterion in project.criteria) {
      if (!criterion.required ||
          criterion.status == ProjectCriterionStatus.satisfied ||
          criterion.status == ProjectCriterionStatus.invalidated ||
          (criterion.verificationMode != ProjectVerificationMode.modelReview &&
              criterion.verificationMode != ProjectVerificationMode.mixed)) {
        continue;
      }
      if (project.evidence.any(
        (item) =>
            item.criterionIds.contains(criterion.id) &&
            (item.status == ProjectEvidenceStatus.proposed ||
                item.status == ProjectEvidenceStatus.accepted),
      )) {
        return true;
      }
    }
    return false;
  }

  ProjectCompletionReviewReason? _completionReviewReason({
    required ProjectDocument project,
    required Set<String> newEvidenceIds,
    required String? endedMilestoneId,
    required bool batchEnded,
  }) {
    if (_activeProjectTask(project) == null &&
        _nonTerminalTasks(project).isEmpty) {
      return ProjectCompletionReviewReason.noRemainingTasks;
    }
    if (endedMilestoneId != null) {
      return ProjectCompletionReviewReason.milestoneEnded;
    }
    if (batchEnded) {
      return ProjectCompletionReviewReason.batchEnded;
    }
    final unresolved = project.criteria.where((criterion) {
      return criterion.required &&
          criterion.status != ProjectCriterionStatus.satisfied &&
          criterion.status != ProjectCriterionStatus.invalidated;
    }).toList();
    if (unresolved.length != 1) return null;
    final criterion = unresolved.single;
    if (criterion.verificationMode != ProjectVerificationMode.modelReview &&
        criterion.verificationMode != ProjectVerificationMode.mixed) {
      return null;
    }
    final hasNewRelevantEvidence = project.evidence.any(
      (item) =>
          newEvidenceIds.contains(item.id) &&
          item.criterionIds.contains(criterion.id) &&
          (item.status == ProjectEvidenceStatus.proposed ||
              item.status == ProjectEvidenceStatus.accepted),
    );
    return hasNewRelevantEvidence
        ? ProjectCompletionReviewReason.finalCriterionEvidence
        : null;
  }

  bool _isBatchEnd(ProjectDocument project, String taskId) {
    if (project.currentBatchTaskIds.isEmpty) return true;
    final taskIndex = project.currentBatchTaskIds.indexOf(taskId);
    return taskIndex < 0 || taskIndex == project.currentBatchTaskIds.length - 1;
  }

  String _completionEvidenceFingerprint(ProjectDocument project) {
    final criteria = [
      for (final criterion in project.criteria)
        '${criterion.id}:${criterion.status.name}:${criterion.notes}',
    ]..sort();
    final evidence = [
      for (final item in project.evidence)
        '${item.id}:${item.status.name}:${item.strength.name}:${item.criterionIds.toList()..sort()}',
    ]..sort();
    return jsonEncode({'criteria': criteria, 'evidence': evidence});
  }

  bool _isTerminalMilestoneStatus(ProjectMilestoneStatus status) {
    return status == ProjectMilestoneStatus.completed ||
        status == ProjectMilestoneStatus.blocked ||
        status == ProjectMilestoneStatus.cancelled;
  }

  ProjectDocument _completeProjectFromEvidence(
    ProjectDocument project,
    DateTime now, {
    String summary = '',
  }) {
    return completionService
        .completeFromEvidence(project: project, summary: summary, now: now)
        .project;
  }

  _ProjectTaskValidation _validateProjectTask(
    ProjectTaskNode task,
    ProjectDocument project,
  ) {
    final violations = <String>[];
    if (task.objective.trim().isEmpty) {
      violations.add('Task objective is empty.');
    }
    if (task.doneCriteria.isEmpty) {
      violations.add('Task has no done criteria.');
    }
    if (task.outOfScope.isEmpty) {
      violations.add('Task has no out-of-scope boundaries.');
    }
    final projectCriterionIds = project.criteria.map((item) => item.id).toSet();
    if (task.criterionIds.isEmpty) {
      violations.add('Task has no project criterion IDs.');
    }
    for (final criterionId in task.criterionIds) {
      if (!projectCriterionIds.contains(criterionId)) {
        violations.add('Task references unknown criterion $criterionId.');
      }
    }
    for (final expectation in task.expectedEvidence) {
      if (expectation.criterionIds.isEmpty) {
        violations.add(
          'Evidence expectation ${expectation.id} has no criterion IDs.',
        );
      }
      for (final criterionId in expectation.criterionIds) {
        if (!projectCriterionIds.contains(criterionId)) {
          violations.add(
            'Evidence expectation ${expectation.id} references unknown criterion $criterionId.',
          );
        } else if (!task.criterionIds.contains(criterionId)) {
          violations.add(
            'Evidence expectation ${expectation.id} references criterion $criterionId outside the task.',
          );
        }
      }
    }
    if (task.recoveryIncidentId == null &&
        _knownFingerprints(
          project,
          excludingTaskId: task.id,
        ).contains(task.fingerprint)) {
      violations.add(
        'Task duplicates previous, current, failed, or queued work.',
      );
    }
    if (task.recoveryIncidentId == null &&
        project.decisions.any(
          (decision) =>
              decision.taskPrompt?.trim().isNotEmpty == true &&
              _normalise(decision.taskPrompt!) == _normalise(task.objective),
        )) {
      violations.add('Task repeats a previous project task prompt.');
    }
    if (_normalise(task.objective) == _normalise(project.refinedGoal) ||
        _normalise(task.objective) == _normalise(project.originalGoal)) {
      violations.add('Task objective matches the whole project goal.');
    }
    if (_looksOversized(task.objective)) {
      violations.add('Task objective is too broad for a project task.');
    }
    if (task.criterionIds.length > 3) {
      violations.add('Task covers too many success criteria.');
    }
    if (project.criteria.length > 1 &&
        task.criterionIds.length >= project.criteria.length) {
      violations.add('Task covers the entire project success criteria set.');
    }
    if (task.doneCriteria.length > 5) {
      violations.add('Task has too many done criteria.');
    }
    if (task.objective.length > 700) {
      violations.add('Task objective is too long.');
    }
    return _ProjectTaskValidation(violations.isEmpty, violations);
  }

  _DuplicateProjectTaskMatch? _duplicateMatchForTask(
    ProjectDocument project,
    ProjectTaskNode task,
  ) {
    if (task.recoveryIncidentId != null) return null;
    final fingerprint = task.fingerprint;
    for (final queued in project.tasks) {
      if (queued.id != task.id &&
          queued.status == TaskStatus.queued &&
          queued.fingerprint == fingerprint) {
        return _QueuedDuplicateProjectTask(queued);
      }
    }
    final current = _activeProjectTask(project);
    if (current != null &&
        current.id != task.id &&
        current.fingerprint == fingerprint) {
      return _QueuedDuplicateProjectTask(current);
    }
    for (final failed in project.tasks.where(
      (item) => item.status == TaskStatus.failed,
    )) {
      if (failed.id != task.id &&
          failed.status == TaskStatus.failed &&
          failed.recoveryIncidentId == null &&
          failed.fingerprint == fingerprint) {
        return _FailedDuplicateProjectTask(failed);
      }
    }
    return null;
  }

  ProjectTaskNode _retryTaskForFailedDuplicate({
    required ProjectTaskNode failedTask,
    required ProjectTaskNode duplicateTask,
    required List<String> violations,
    required DateTime now,
  }) {
    final criteria = <String>{
      ...failedTask.criterionIds,
      ...duplicateTask.criterionIds,
    }.toList();
    final objective =
        'Retry failed project task after addressing the previous failure: ${failedTask.objective}';
    return ProjectTaskNode(
      id: 'project_retry_${uuid.v7()}',
      title: 'Retry ${failedTask.title}',
      objective: objective,
      criterionIds: criteria,
      doneCriteria: duplicateTask.doneCriteria.isEmpty
          ? failedTask.doneCriteria
          : duplicateTask.doneCriteria,
      outOfScope: duplicateTask.outOfScope.isEmpty
          ? failedTask.outOfScope
          : duplicateTask.outOfScope,
      context: [
        ...failedTask.context,
        ...duplicateTask.context,
        if (failedTask.rejectionReason?.trim().isNotEmpty == true)
          'Previous failure: ${failedTask.rejectionReason!.trim()}',
        'Duplicate proposal was converted into a retry instead of halting the project.',
        ...violations,
      ],
      expectedEvidence: _replacementExpectedEvidence(
        source: failedTask.expectedEvidence,
        additions: duplicateTask.expectedEvidence,
        criterionIds: criteria,
        idPrefix: 'retry_expectation',
      ),
      expectedArtifacts: duplicateTask.expectedArtifacts.isEmpty
          ? failedTask.expectedArtifacts
          : duplicateTask.expectedArtifacts,
      readPaths: duplicateTask.readPaths.isEmpty
          ? failedTask.readPaths
          : duplicateTask.readPaths,
      writePaths: duplicateTask.writePaths.isEmpty
          ? failedTask.writePaths
          : duplicateTask.writePaths,
      status: TaskStatus.queued,
      recoveryIncidentId: null,
      fingerprint: projectTaskFingerprint(objective, criteria),
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool _looksOversized(String value) {
    final text = _normalise(value);
    return text.contains('entire project') ||
        text.contains('whole project') ||
        text.contains('complete the project') ||
        text.contains('finish the project') ||
        text.contains('build the app') ||
        text.contains('implement all') ||
        text.contains('end to end') ||
        text.contains('end-to-end');
  }

  TaskPlanningContext _planningContext(
    ProjectDocument project,
    ProjectTaskNode task,
  ) {
    final plan = project.plan;
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    final workspaceContext = const ProjectWorkspaceContextService()
        .selectContext(project: project, task: task);
    return TaskPlanningContext(
      projectGoal: plan.refinedGoal,
      projectTaskTitle: task.title,
      projectTaskObjective: task.objective,
      knownFacts: [...memoryContext.lines, ...task.context],
      workspaceOrientation: workspaceContext.orientation,
      workspaceContext: workspaceContext.lines,
      doneCriteria: task.doneCriteria,
      outOfScope: task.outOfScope,
      expectedArtifacts: task.expectedArtifacts
          .map(
            (artifact) => TaskArtifact(
              path: artifact.path,
              description: artifact.description,
              kind: artifact.kind,
            ),
          )
          .toList(),
      requiredGates: _requiredGatesForTask(project, task),
      criterionIds: task.criterionIds,
      criteria: [
        for (final criterion in plan.criteria)
          if (task.criterionIds.contains(criterion.id))
            TaskProjectCriterion(
              id: criterion.id,
              statement: criterion.statement,
              required: criterion.required,
              verificationMode: criterion.verificationMode.name,
            ),
      ],
      expectedEvidence: [
        for (final expectation in task.expectedEvidence)
          TaskProjectEvidenceExpectation(
            id: expectation.id,
            type: _projectEvidenceTypeWire(expectation.type),
            criterionIds: expectation.criterionIds,
            description: expectation.description,
            required: expectation.required,
            sourceRef: expectation.sourceRef,
            details: expectation.details,
          ),
      ],
      readPaths: task.readPaths,
      writePaths: task.writePaths,
      maxSteps: taskStepLimit(task.effort),
    );
  }

  _RecoveryUpdate _recoveryUpdateForFailedTask({
    required ProjectDocument project,
    required ProjectTaskNode failedTask,
    required ProjectEvaluation evaluation,
    required DateTime now,
  }) {
    final recoveryFailure = _recoveryFailureFor(
      failedTask: failedTask,
      evaluation: evaluation,
    );
    if (recoveryFailure == null) {
      return _RecoveryUpdate(
        failedTask: failedTask,
        recoveryIncidents: project.recoveryIncidents,
      );
    }

    final existing = _matchingRecoveryIncident(
      project.recoveryIncidents,
      recoveryFailure,
      failedTask.recoveryIncidentId,
    );
    final isRecoveryAttempt = failedTask.recoveryIncidentId != null;
    final incidentId = existing?.id ?? 'recovery_${uuid.v7()}';
    final nextAttemptCount =
        (existing?.attemptCount ?? 0) + (isRecoveryAttempt ? 1 : 0);
    final status =
        nextAttemptCount >=
            (existing?.maxAttempts ??
                ProjectRecoveryIncident.defaultMaxAttempts)
        ? ProjectRecoveryIncidentStatus.exhausted
        : ProjectRecoveryIncidentStatus.active;
    final linkedFailedTask = failedTask.copyWith(
      recoveryIncidentId: incidentId,
    );
    final recoveryTask = status == ProjectRecoveryIncidentStatus.active
        ? _recoveryTaskForIncident(
            incidentId: incidentId,
            sourceTask: failedTask,
            failure: recoveryFailure,
            attemptNumber: nextAttemptCount + 1,
            now: now,
          )
        : null;
    final incident =
        (existing ??
                ProjectRecoveryIncident(
                  id: incidentId,
                  status: ProjectRecoveryIncidentStatus.active,
                  sourceTaskIds: const [],
                  sourceTaskTitles: const [],
                  failedGateId: recoveryFailure.gateResult.gateId,
                  command: recoveryFailure.command,
                  workingDirectory: recoveryFailure.workingDirectory,
                  failureSummary: recoveryFailure.summary,
                  attemptCount: 0,
                  maxAttempts: ProjectRecoveryIncident.defaultMaxAttempts,
                  recoveryTaskIds: const [],
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              status: status,
              sourceTaskIds: _appendUnique(
                existing?.sourceTaskIds ?? const [],
                failedTask.id,
              ),
              sourceTaskTitles: _appendUnique(
                existing?.sourceTaskTitles ?? const [],
                failedTask.title,
              ),
              failedGateId: recoveryFailure.gateResult.gateId,
              command: recoveryFailure.command,
              workingDirectory: recoveryFailure.workingDirectory,
              failureSummary: recoveryFailure.summary,
              attemptCount: nextAttemptCount,
              recoveryTaskIds: recoveryTask == null
                  ? existing?.recoveryTaskIds ?? const []
                  : _appendUnique(
                      existing?.recoveryTaskIds ?? const [],
                      recoveryTask.id,
                    ),
              updatedAt: now,
              resolvedAt: status == ProjectRecoveryIncidentStatus.exhausted
                  ? now
                  : null,
            );
    return _RecoveryUpdate(
      failedTask: linkedFailedTask,
      recoveryIncidents: _upsertRecoveryIncident(
        project.recoveryIncidents,
        incident,
      ),
      incident: incident,
      recoveryTask: recoveryTask,
      exhaustedIncident: status == ProjectRecoveryIncidentStatus.exhausted
          ? incident
          : null,
    );
  }

  _RecoveryFailure? _recoveryFailureFor({
    required ProjectTaskNode failedTask,
    required ProjectEvaluation evaluation,
  }) {
    final failedGate = evaluation.gateResults
        .where(
          (result) =>
              result.status == TaskGateStatus.failed &&
              result.details['required'] == true,
        )
        .where(
          (result) =>
              result.failureDisposition ==
                  TaskGateFailureDisposition.repairable ||
              failedTask.recoveryIncidentId != null,
        )
        .firstOrNull;
    if (failedGate == null) return null;
    final command = _gateFailureCommand(failedGate);
    final workingDirectory = jsonNullableString(
      failedGate.details['workingDirectory'] ??
          failedGate.details['working_directory'],
    );
    final summary = [
      failedGate.summary,
      _gateDiagnosticSummary(failedGate),
      if (evaluation.failureReason?.trim().isNotEmpty == true)
        evaluation.failureReason!.trim(),
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    return _RecoveryFailure(
      gateResult: failedGate,
      command: command,
      workingDirectory: workingDirectory,
      summary: _cap(summary.isEmpty ? 'Required gate failed.' : summary, 2000),
    );
  }

  String _gateDiagnosticSummary(TaskGateResult result) {
    final unresolved = result.details['unresolvedErrors'];
    if (unresolved is! List) return '';
    final lines = unresolved.whereType<Map>().take(10).map((raw) {
      final item = jsonMap(raw);
      final code = jsonString(item['code'], fallback: 'unknown_tool_error');
      final toolName = jsonString(item['toolName'], fallback: 'tool');
      final operation = jsonString(item['operationKey']);
      final message = jsonString(item['message']);
      return '- $code ($toolName${operation.isEmpty ? '' : ', $operation'}): $message';
    }).toList();
    return lines.isEmpty ? '' : 'Unresolved diagnostics:\n${lines.join('\n')}';
  }

  TaskFailure _taskFailure(ProjectEvaluation evaluation) {
    final gate = evaluation.gateResults
        .where(
          (result) =>
              result.status == TaskGateStatus.failed &&
              result.details['required'] == true,
        )
        .firstOrNull;
    final unresolved = gate?.details['unresolvedErrors'];
    final advisory = gate?.details['advisoryErrors'];
    final resolved = gate?.details['resolvedErrors'];
    final errorMaps = unresolved is List
        ? unresolved.whereType<Map>().map(jsonMap).toList()
        : const <Map<String, dynamic>>[];
    final errorCodes =
        errorMaps
            .map((item) => jsonString(item['code']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final callIds = errorMaps
        .map((item) => jsonString(item['callId']))
        .where((item) => item.isNotEmpty)
        .take(10)
        .toList();
    final operationKeys =
        errorMaps
            .map((item) => jsonString(item['operationKey']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final disposition =
        gate?.failureDisposition ?? TaskGateFailureDisposition.blocking;
    final summary = evaluation.failureReason?.trim().isNotEmpty == true
        ? evaluation.failureReason!.trim()
        : gate?.summary ?? 'Task execution failed.';
    final keyParts = [
      gate?.gateId ?? 'execution',
      ...errorCodes,
      ...operationKeys,
      if (errorCodes.isEmpty && operationKeys.isEmpty) _normalise(summary),
    ];
    return TaskFailure(
      gateId: gate?.gateId,
      disposition: disposition,
      failureKey: _cap(keyParts.join('|'), 500),
      summary: _cap(summary, 2000),
      errorCodes: errorCodes,
      toolCallIds: callIds,
      advisoryErrorCount: advisory is List ? advisory.length : 0,
      resolvedErrorCount: resolved is List ? resolved.length : 0,
      unresolvedErrorCount: unresolved is List ? unresolved.length : 0,
    );
  }

  String? _gateFailureCommand(TaskGateResult result) {
    final direct = jsonNullableString(result.details['command']);
    if (direct != null) return direct;
    final failedCommands = result.details['failedCommands'];
    if (failedCommands is List && failedCommands.isNotEmpty) {
      final first = failedCommands.first;
      if (first is Map) return jsonNullableString(first['command']);
    }
    return null;
  }

  ProjectRecoveryIncident? _matchingRecoveryIncident(
    List<ProjectRecoveryIncident> incidents,
    _RecoveryFailure failure,
    String? preferredIncidentId,
  ) {
    if (preferredIncidentId != null) {
      final preferred = incidents
          .where((incident) => incident.id == preferredIncidentId)
          .firstOrNull;
      if (preferred != null) return preferred;
    }
    final key = _recoveryIncidentKey(
      gateId: failure.gateResult.gateId,
      command: failure.command,
      workingDirectory: failure.workingDirectory,
      summary: failure.summary,
    );
    return incidents.where((incident) {
      return incident.status == ProjectRecoveryIncidentStatus.active &&
          _recoveryIncidentKey(
                gateId: incident.failedGateId,
                command: incident.command,
                workingDirectory: incident.workingDirectory,
                summary: incident.failureSummary,
              ) ==
              key;
    }).firstOrNull;
  }

  String _recoveryIncidentKey({
    required String gateId,
    required String? command,
    required String? workingDirectory,
    required String summary,
  }) {
    final commandPart = command?.trim().isNotEmpty == true
        ? command!.trim()
        : _cap(_normalise(summary), 160);
    return [
      _normalise(gateId),
      _normalise(commandPart),
      _normalise(workingDirectory ?? '.'),
    ].join('|');
  }

  List<TaskEvidenceExpectation> _replacementExpectedEvidence({
    required Iterable<TaskEvidenceExpectation> source,
    required Iterable<TaskEvidenceExpectation> additions,
    required Iterable<String> criterionIds,
    required String idPrefix,
  }) {
    final validCriteria = criterionIds.toSet();
    final merged = <String, TaskEvidenceExpectation>{};
    for (final expectation in [...source, ...additions]) {
      final linkedCriteria = expectation.criterionIds
          .where(validCriteria.contains)
          .toSet()
          .toList();
      if (linkedCriteria.isEmpty) continue;
      final normalized = TaskEvidenceExpectation(
        id: expectation.id,
        type: expectation.type,
        criterionIds: linkedCriteria,
        description: expectation.description,
        required: expectation.required,
        sourceRef: expectation.sourceRef,
        details: expectation.details,
      );
      final signature = _evidenceExpectationSignature(normalized);
      final existing = merged[signature];
      merged[signature] = existing == null
          ? normalized
          : TaskEvidenceExpectation(
              id: normalized.id,
              type: normalized.type,
              criterionIds: normalized.criterionIds,
              description: normalized.description,
              required: existing.required || normalized.required,
              sourceRef: normalized.sourceRef,
              details: normalized.details,
            );
    }
    return [
      for (final expectation in merged.values)
        TaskEvidenceExpectation(
          id: '${idPrefix}_${uuid.v7()}',
          type: expectation.type,
          criterionIds: expectation.criterionIds,
          description: expectation.description,
          required: expectation.required,
          sourceRef: expectation.sourceRef,
          details: expectation.details,
        ),
    ];
  }

  String _evidenceExpectationSignature(TaskEvidenceExpectation expectation) {
    final criteria = [...expectation.criterionIds]..sort();
    return [
      expectation.type.name,
      _normalise(expectation.sourceRef ?? ''),
      criteria.join(','),
    ].join('|');
  }

  ProjectTaskNode _recoveryTaskForIncident({
    required String incidentId,
    required ProjectTaskNode sourceTask,
    required _RecoveryFailure failure,
    required int attemptNumber,
    required DateTime now,
  }) {
    final command = failure.command?.trim();
    final gateTarget = command?.isNotEmpty == true
        ? '${failure.gateResult.gateId}: $command'
        : failure.gateResult.gateId;
    final objective = 'Restore required project health gate: $gateTarget';
    final gateType =
        command?.isNotEmpty == true ||
            failure.gateResult.gateId == 'command_passes'
        ? ProjectEvidenceType.command
        : failure.gateResult.gateId == 'human_approval'
        ? ProjectEvidenceType.userApproval
        : ProjectEvidenceType.gate;
    final gateSourceRef = command?.isNotEmpty == true
        ? command
        : failure.gateResult.gateId;
    final recoveryGateExpectation = TaskEvidenceExpectation(
      id: 'recovery_gate_expectation',
      type: gateType,
      criterionIds: sourceTask.criterionIds,
      description: 'The required recovery gate passes: $gateTarget.',
      required: true,
      sourceRef: gateSourceRef,
      details: failure.gateResult.details,
    );
    return ProjectTaskNode(
      id: 'project_recovery_${uuid.v7()}',
      title: 'Recover project health',
      objective: objective,
      criterionIds: sourceTask.criterionIds,
      doneCriteria: [
        'Diagnose why the required gate is failing.',
        'Make the smallest safe repair needed to restore the gate.',
        if (command?.isNotEmpty == true)
          'Run `$command` successfully before completing this task.'
        else
          'Rerun the failed required gate successfully before completing this task.',
      ],
      outOfScope: const [
        'Do not start unrelated feature work.',
        'Do not expand the original project scope.',
      ],
      context: [
        'Recovery incident: $incidentId',
        'Original task: ${sourceTask.title}',
        'Original objective: ${sourceTask.objective}',
        'Failed gate: ${failure.gateResult.gateId}',
        if (command?.isNotEmpty == true) 'Failed command: $command',
        if (failure.workingDirectory?.trim().isNotEmpty == true)
          'Working directory: ${failure.workingDirectory}',
        'Failure summary:\n${failure.summary}',
        'Recovery attempt: $attemptNumber',
      ],
      readPaths: sourceTask.readPaths,
      writePaths: sourceTask.writePaths,
      expectedEvidence: _replacementExpectedEvidence(
        source: sourceTask.expectedEvidence,
        additions: [recoveryGateExpectation],
        criterionIds: sourceTask.criterionIds,
        idPrefix: 'recovery_expectation',
      ),
      expectedArtifacts: const [],
      status: TaskStatus.queued,
      recoveryIncidentId: incidentId,
      fingerprint: projectTaskFingerprint(objective, [
        incidentId,
        'attempt_$attemptNumber',
      ]),
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<ProjectRecoveryIncident> _upsertRecoveryIncident(
    List<ProjectRecoveryIncident> incidents,
    ProjectRecoveryIncident incident,
  ) {
    var replaced = false;
    final next = <ProjectRecoveryIncident>[];
    for (final current in incidents) {
      if (current.id == incident.id) {
        next.add(incident);
        replaced = true;
      } else {
        next.add(current);
      }
    }
    if (!replaced) next.add(incident);
    return next;
  }

  List<ProjectRecoveryIncident> _resolveRecoveryIncidentForTask(
    List<ProjectRecoveryIncident> incidents,
    ProjectTaskNode completedTask,
    DateTime now,
  ) {
    final incidentId = completedTask.recoveryIncidentId;
    if (incidentId == null) return incidents;
    return [
      for (final incident in incidents)
        incident.id == incidentId &&
                incident.status == ProjectRecoveryIncidentStatus.active
            ? incident.copyWith(
                status: ProjectRecoveryIncidentStatus.resolved,
                updatedAt: now,
                resolvedAt: now,
              )
            : incident,
    ];
  }

  List<TaskGate> _requiredGatesForTask(
    ProjectDocument project,
    ProjectTaskNode task,
  ) {
    final expectedGates = <TaskGate>[
      for (final expectation in task.expectedEvidence)
        if (expectation.required &&
            expectation.type == ProjectEvidenceType.command &&
            expectation.sourceRef?.trim().isNotEmpty == true)
          TaskGate(
            id: 'command_passes',
            required: true,
            scope: 'task',
            params: {
              'command': expectation.sourceRef!.trim(),
              ...expectation.details,
            },
            description: expectation.description,
          )
        else if (expectation.required &&
            expectation.type == ProjectEvidenceType.gate &&
            expectation.sourceRef?.trim().isNotEmpty == true)
          TaskGate(
            id: expectation.sourceRef!.trim(),
            required: true,
            scope: 'task',
            params: expectation.details,
            description: expectation.description,
          )
        else if (expectation.required &&
            expectation.type == ProjectEvidenceType.userApproval)
          TaskGate(
            id: 'human_approval',
            required: true,
            scope: 'task',
            params: expectation.details,
            description: expectation.description,
          ),
    ];
    final incidentId = task.recoveryIncidentId;
    if (incidentId == null) return expectedGates;
    final incident = project.recoveryIncidents
        .where((item) => item.id == incidentId)
        .firstOrNull;
    if (incident == null) return expectedGates;
    return [
      ...expectedGates,
      TaskGate(
        id: incident.failedGateId,
        required: true,
        scope: 'task',
        params: {
          if (incident.command?.trim().isNotEmpty == true)
            'command': incident.command,
          if (incident.workingDirectory?.trim().isNotEmpty == true)
            'working_directory': incident.workingDirectory,
        },
        description: 'Recovery incident ${incident.id} must be resolved.',
      ),
    ];
  }

  int _projectFailureBudgetCount(
    List<ProjectTaskNode> failedTasks,
    List<ProjectRecoveryIncident> recoveryIncidents,
  ) {
    final nonRecoveryFailures = failedTasks
        .where(
          (task) =>
              task.status == TaskStatus.failed &&
              task.recoveryIncidentId == null,
        )
        .map(
          (task) =>
              task.failureKey ??
              '${task.fingerprint}|${_normalise(task.rejectionReason ?? '')}',
        )
        .toSet()
        .length;
    final exhaustedIncidents = recoveryIncidents
        .where(
          (incident) =>
              incident.status == ProjectRecoveryIncidentStatus.exhausted,
        )
        .length;
    return nonRecoveryFailures + exhaustedIncidents;
  }
}
