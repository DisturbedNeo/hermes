// ignore_for_file: override_on_non_overriding_member, unused_element
part of 'project_runtime_engine.dart';

extension _ProjectExecutionOperations on _ProjectApplicationContext {
  /// Executes bounded project runs and owns the task execution protocol.
  @override
  Future<ProjectCommandResult> _runProjectCore({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    required int maxNewTasks,
    int? maxIterations,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    ProjectPlanApprovalPolicy planApprovalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) async {
    cancellationToken?.throwIfCancelled();
    final recovered = await _recoverProjectCore(
      workspace: workspace,
      snapshot: snapshot,
      onTaskUpdated: onTaskUpdated,
    );
    if (recovered.persistenceDiagnostics?.isReadOnly ?? false) {
      return recovered;
    }
    var project = recovered.project;
    var activeTask = recovered.activeTask;
    // A paused, empty shell is the persisted shape used while a project is
    // waiting for its first plan. Continuing that project is an explicit
    // resume command, so reduce it to an active planning boundary and request
    // one no-ready-task revision before ordinary scheduling begins.
    if (project.status == ProjectStatus.paused &&
        project.activeTaskId == null &&
        project.tasks.isEmpty &&
        project.criteria.isEmpty &&
        project.blocker == null &&
        project.openQuestions.isEmpty &&
        project.pendingPlanApproval == null) {
      project = _transitionProject(
        snapshot: project.copyWith(
          pendingReplanTriggers: _appendTrigger(
            project.pendingReplanTriggers,
            ProjectPlanRevisionTrigger.noReadyTask,
          ),
          pendingReplanReason: 'The project has no initial bounded plan.',
        ),
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.recovery,
        reason: 'Resuming the project to create its initial bounded plan.',
      );
    }
    final initialAggregate = await _aggregateRepository.loadProject(
      workspace.rootPath,
      project.id,
      chatSessionId: project.chatSessionId,
      includeHistory: false,
    );
    final persistenceContext = ProjectPersistenceContext(
      initialAggregate.canonicalTasks,
      health: recovered.persistenceDiagnostics,
    );
    if (maxIterations != null && project.maxIterations != maxIterations) {
      project = project.copyWith(
        maxIterations: _normaliseOptionalLimit(maxIterations),
        updatedAt: DateTime.now(),
      );
      project = await _persistProject(
        workspace.rootPath,
        project,
        persistenceContext: persistenceContext,
      );
    }
    if (project.isTerminal) {
      return ProjectCommandResult.fromSnapshot(
        project: project,
        activeTask: activeTask,
      );
    }
    final pendingProposal = project.pendingPlanApproval?.desiredPlan;
    if (pendingProposal != null) {
      final reconsidered = await _planningHandler.prepareAndApply(
        project: project,
        proposal: pendingProposal,
        workspaceRoot: workspace.rootPath,
        approvalPolicy: planApprovalPolicy,
      );
      if (reconsidered.changed || !reconsidered.validation.valid) {
        project = await _persistProject(
          workspace.rootPath,
          reconsidered.project,
          persistenceContext: persistenceContext,
        );
      }
    }
    if (project.pendingPlanApproval != null) {
      return ProjectCommandResult.fromSnapshot(
        project: project,
        activeTask: activeTask,
      );
    }
    final canAutomaticallyReplanValidationBlocker =
        project.blocker?.type == ProjectBlockerType.validation &&
        project.activeTaskId == null;
    if (canAutomaticallyReplanValidationBlocker) {
      project = _transitionProject(
        snapshot: project.copyWith(
          blocker: null,
          pendingReplanTriggers: _appendTrigger(
            project.pendingReplanTriggers,
            ProjectPlanRevisionTrigger.noReadyTask,
          ),
          updatedAt: DateTime.now(),
        ),
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.planRevision,
        reason: 'Retrying the blocked plan revision.',
      );
      project = await _persistProject(
        workspace.rootPath,
        project,
        persistenceContext: persistenceContext,
      );
    }
    final canResumeValidationBlocker =
        project.blocker?.type == ProjectBlockerType.validation &&
        _hasExecutableProjectTask(project);
    if (project.blocker?.type == ProjectBlockerType.budget ||
        project.blocker?.type == ProjectBlockerType.duplicateTask ||
        canResumeValidationBlocker) {
      project = _transitionProject(
        snapshot: project.copyWith(blocker: null, updatedAt: DateTime.now()),
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.recovery,
        reason: 'Resuming after the project blocker was resolved.',
      );
      project = await _persistProject(
        workspace.rootPath,
        project,
        persistenceContext: persistenceContext,
      );
    }

    if (project.activeTaskId != null && project.currentBatchTaskIds.isEmpty) {
      project = await _persistProject(
        workspace.rootPath,
        project.copyWith(
          currentBatchTaskIds: [project.activeTaskId!],
          currentBatchIndex: 0,
          currentBatchPlanRevision: _currentPlanRevision(project),
        ),
        persistenceContext: persistenceContext,
      );
    } else if (project.activeTaskId == null &&
        project.currentBatchPlanRevision != 0 &&
        project.currentBatchPlanRevision != _currentPlanRevision(project)) {
      project = await _persistProject(
        workspace.rootPath,
        _clearBatch(project),
        persistenceContext: persistenceContext,
      );
    }

    final allowedIterations = maxNewTasks <= 0 ? null : maxNewTasks;
    var runIterations = 0;
    var consecutiveInvalidCandidates = 0;

    while (!project.isTerminal) {
      cancellationToken?.throwIfCancelled();
      if (project.openQuestions.isNotEmpty) {
        final filtered = _filterProjectQuestions(
          project.openQuestions,
          autonomy: questionAutonomy,
        );
        if (filtered.assumptions.isNotEmpty) {
          final boundary = project.copyWith(
            openQuestions: filtered.blocking,
            blocker: filtered.blocking.isEmpty
                ? null
                : ProjectBlocker(
                    type: ProjectBlockerType.question,
                    message: filtered.blocking.first.question,
                    createdAt: DateTime.now(),
                  ),
            updatedAt: DateTime.now(),
          );
          project = _transitionProject(
            snapshot: boundary,
            to: filtered.blocking.isEmpty
                ? ProjectStatus.active
                : ProjectStatus.waitingForUser,
            trigger: ProjectLifecycleTrigger.userContext,
            reason: filtered.blocking.isEmpty
                ? 'Question policy resolved the pending assumptions.'
                : filtered.blocking.first.question,
            blocker: boundary.blocker,
            now: DateTime.now(),
          );
          project = _recordAssumptions(
            project,
            filtered.assumptions,
            sourceId: 'question_policy',
          );
          project = await _persistProject(
            workspace.rootPath,
            project,
            persistenceContext: persistenceContext,
          );
        }
      }
      if (project.openQuestions.isNotEmpty ||
          project.blocker?.type == ProjectBlockerType.question) {
        project = _waitingForUser(project, DateTime.now());
        project = await _persistProject(
          workspace.rootPath,
          project,
          persistenceContext: persistenceContext,
          checkpoint: ProjectPersistenceCheckpoint.userBoundary,
        );
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }
      if (project.status == ProjectStatus.blocked &&
          project.blocker?.type != ProjectBlockerType.budget) {
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }
      if (project.maxIterations > 0 &&
          project.iterationCount >= project.maxIterations) {
        project = _blockProject(
          project,
          ProjectBlockerType.budget,
          'Project reached the maximum iteration limit of ${project.maxIterations}.',
          DateTime.now(),
        );
        project = await _persistProject(
          workspace.rootPath,
          project,
          persistenceContext: persistenceContext,
        );
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }
      if (allowedIterations != null && runIterations >= allowedIterations) {
        project = _transitionProject(
          snapshot: project,
          to: ProjectStatus.paused,
          trigger: ProjectLifecycleTrigger.pause,
          reason: 'The bounded command run reached its iteration budget.',
          now: DateTime.now(),
        );
        project = await _persistProject(
          workspace.rootPath,
          project,
          persistenceContext: persistenceContext,
        );
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }

      var replanTriggers = _eligibleReplanTriggers(
        project.pendingReplanTriggers,
      );
      if (replanTriggers.length != project.pendingReplanTriggers.length ||
          (replanTriggers.isNotEmpty && project.pendingReplanReason == null)) {
        project = project.copyWith(
          pendingReplanTriggers: replanTriggers,
          pendingReplanReason: replanTriggers.isEmpty
              ? null
              : _replanReasonForTriggers(replanTriggers),
        );
      }

      if (_activeProjectTask(project) == null && replanTriggers.isEmpty) {
        if (project.currentBatchPlanRevision != 0 &&
            project.currentBatchPlanRevision != _currentPlanRevision(project)) {
          project = await _persistProject(
            workspace.rootPath,
            _clearBatch(project),
            persistenceContext: persistenceContext,
          );
        }
        if (project.currentBatchTaskIds.isNotEmpty &&
            project.currentBatchIndex >= project.currentBatchTaskIds.length) {
          // A frontier is a bounded execution window, not a plan boundary.
          // Continue selecting ready work from the current plan; only an
          // actual dependency, scope, evidence, failure, or workspace change
          // can request a plan transaction.
          project = await _persistProject(
            workspace.rootPath,
            _clearBatch(project),
            persistenceContext: persistenceContext,
          );
        }
        if (replanTriggers.isEmpty && !project.hasCurrentBatch) {
          project = await _startBatch(
            workspaceRoot: workspace.rootPath,
            project: project,
            maxNewTasks: maxNewTasks,
            persistenceContext: persistenceContext,
          );
        }
      }

      var candidate = _activeProjectTask(project) ?? _currentBatchTask(project);
      if (_activeProjectTask(project) == null &&
          candidate?.isTerminal == true) {
        project = await _persistProject(
          workspace.rootPath,
          _advanceBatchCursor(project, candidate!.id),
          persistenceContext: persistenceContext,
        );
        continue;
      }
      var decision = _decisionEngine.decide(
        ProjectDecisionInput(
          project: project,
          candidate: candidate,
          replanTriggers: replanTriggers,
          runIterations: runIterations,
          allowedIterations: allowedIterations,
        ),
      );
      if (decision.action == ProjectExecutionAction.evaluateCompletion) {
        project = await _applyCompletionEvaluation(
          client: client,
          project: project,
          baseSystemPrompt: baseSystemPrompt,
          reviewReason: _nonTerminalTasks(project).isEmpty
              ? ProjectCompletionReviewReason.noRemainingTasks
              : null,
          onModelOutput: onModelOutput,
          questionAutonomy: questionAutonomy,
          cancellationToken: cancellationToken,
        );
        if (project.isTerminal ||
            project.status == ProjectStatus.waitingForUser ||
            project.openQuestions.isNotEmpty) {
          project = await _persistProject(
            workspace.rootPath,
            project,
            persistenceContext: persistenceContext,
          );
          return ProjectCommandResult.fromSnapshot(
            project: project,
            activeTask: activeTask,
          );
        }
        replanTriggers = _appendTrigger(
          replanTriggers,
          ProjectPlanRevisionTrigger.noReadyTask,
        );
        project = project.copyWith(
          pendingReplanTriggers: replanTriggers,
          pendingReplanReason:
              project.pendingReplanReason ??
              _replanReasonForTriggers(replanTriggers),
        );
        decision = _decisionEngine.decide(
          ProjectDecisionInput(
            project: project,
            candidate: candidate,
            replanTriggers: replanTriggers,
            runIterations: runIterations,
            allowedIterations: allowedIterations,
          ),
        );
      }

      if (decision.action == ProjectExecutionAction.revisePlan) {
        project = await _revisePlan(
          client: client,
          workspace: workspace,
          project: project,
          triggers: replanTriggers,
          baseSystemPrompt: baseSystemPrompt,
          approvalPolicy: planApprovalPolicy,
          questionAutonomy: questionAutonomy,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        project = await _persistProject(
          workspace.rootPath,
          project,
          persistenceContext: persistenceContext,
          checkpoint: ProjectPersistenceCheckpoint.planRevision,
        );
        if (project.pendingPlanApproval != null ||
            project.status == ProjectStatus.blocked ||
            project.status == ProjectStatus.waitingForUser) {
          return ProjectCommandResult.fromSnapshot(
            project: project,
            activeTask: activeTask,
          );
        }
        continue;
      }

      if (decision.action == ProjectExecutionAction.block ||
          candidate == null) {
        project = _blockProject(
          project.copyWith(
            diagnostics: project.diagnostics.copyWith(
              noReadyTaskBlocks: project.diagnostics.noReadyTaskBlocks + 1,
            ),
          ),
          ProjectBlockerType.validation,
          'The validated plan left no ready bounded task. Revise the scope, constraints, or dependencies before resuming.',
          DateTime.now(),
        );
        project = await _persistProject(
          workspace.rootPath,
          project,
          persistenceContext: persistenceContext,
        );
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }

      final activeProjectTask = _activeProjectTask(project);
      final resumingActiveTask =
          activeProjectTask?.id == candidate.id &&
          activeTask != null &&
          activeTask.id == activeProjectTask?.id;
      final validation = resumingActiveTask
          ? const _ProjectTaskValidation(true, [])
          : _validateProjectTask(candidate, project);
      if (!validation.valid) {
        final projectBeforeRecovery = project;
        project = await _handleInvalidProjectTask(
          client: client,
          workspace: workspace,
          project: project,
          task: candidate,
          violations: validation.violations,
          baseSystemPrompt: baseSystemPrompt,
          approvalPolicy: planApprovalPolicy,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        if (project.status == ProjectStatus.blocked) {
          project = await _persistProject(
            workspace.rootPath,
            project,
            persistenceContext: persistenceContext,
          );
          return ProjectCommandResult.fromSnapshot(
            project: project,
            activeTask: activeTask,
          );
        }
        if (project.pendingPlanApproval != null) {
          project = await _persistProject(
            workspace.rootPath,
            project,
            persistenceContext: persistenceContext,
          );
          return ProjectCommandResult.fromSnapshot(
            project: project,
            activeTask: activeTask,
          );
        }
        final recoveryMadeProgress = _invalidTaskRecoveryMadeProgress(
          before: projectBeforeRecovery,
          after: project,
        );
        if (recoveryMadeProgress || project.taskById(candidate.id) == null) {
          consecutiveInvalidCandidates = 0;
          // Selection recovery can replace the candidate with a fresh task.
          // Rebuild the batch from the repaired project so that replacement
          // work is eligible without changing the normal sequential path.
          project = _clearBatch(project);
        } else {
          consecutiveInvalidCandidates++;
        }
        if (consecutiveInvalidCandidates >= 3) {
          project = _blockProject(
            project,
            ProjectBlockerType.validation,
            'Project task selection produced $consecutiveInvalidCandidates invalid candidates in a row.',
            DateTime.now(),
          );
          project = await _persistProject(
            workspace.rootPath,
            project,
            persistenceContext: persistenceContext,
          );
          return ProjectCommandResult.fromSnapshot(
            project: project,
            activeTask: activeTask,
          );
        }
        project = await _persistProject(
          workspace.rootPath,
          project,
          persistenceContext: persistenceContext,
        );
        continue;
      }
      consecutiveInvalidCandidates = 0;

      final execution = await _executeProjectTask(
        client: client,
        workspace: workspace,
        project: project,
        projectTask: candidate,
        baseSystemPrompt: baseSystemPrompt,
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        onTaskUpdated: onTaskUpdated,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
        persistenceContext: persistenceContext,
      );
      project = execution.project;
      activeTask = execution.activeTask;
      if (execution.result == null) {
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }

      final now = DateTime.now();
      project = lifecycleService
          .transition(
            snapshot: project,
            to: ProjectStatus.reviewingTask,
            trigger: ProjectLifecycleTrigger.taskReview,
            taskId: candidate.id,
            now: now,
          )
          .project;
      project = await _persistProject(
        workspace.rootPath,
        project,
        persistenceContext: persistenceContext,
        checkpoint: ProjectPersistenceCheckpoint.taskReview,
      );

      final evaluatedProjectTask = _activeProjectTask(project) ?? candidate;
      final criterionStatusesBefore = {
        for (final criterion in project.criteria)
          criterion.id: criterion.status,
      };
      final acceptedEvidenceIdsBefore = {
        for (final item in project.evidence)
          if (item.status == ProjectEvidenceStatus.accepted) item.id,
      };
      final evidenceIdsBefore = project.evidence.map((item) => item.id).toSet();
      final activeMilestoneIdBefore = project.milestones
          .where((item) => item.status == ProjectMilestoneStatus.active)
          .map((item) => item.id)
          .firstOrNull;
      final invalidEvidenceIds = {
        for (final item in project.evidence)
          if (item.status == ProjectEvidenceStatus.rejected ||
              item.status == ProjectEvidenceStatus.stale)
            item.id,
      };
      final evaluation = _evaluateTaskResult(
        evaluatedProjectTask,
        execution.result!,
        project,
      );
      project = _updateProjectState(
        project,
        evaluation,
        now,
        questionAutonomy: questionAutonomy,
      );
      project = _applyTaskEvidence(
        project: project,
        task: evaluatedProjectTask,
        result: execution.result!,
        evaluatedAt: now,
      );
      project = _recordTransitionReplanTriggers(
        project: project,
        evaluation: evaluation,
        invalidEvidenceIdsBefore: invalidEvidenceIds,
        now: now,
      );
      final endedMilestoneId =
          activeMilestoneIdBefore != null &&
              project.milestones.any(
                (item) =>
                    item.id == activeMilestoneIdBefore &&
                    _isTerminalMilestoneStatus(item.status),
              )
          ? activeMilestoneIdBefore
          : null;
      final batchEnded = _isBatchEnd(project, evaluatedProjectTask.id);
      final reviewReason = _completionReviewReason(
        project: project,
        newEvidenceIds: project.evidence
            .where((item) => !evidenceIdsBefore.contains(item.id))
            .map((item) => item.id)
            .toSet(),
        endedMilestoneId: endedMilestoneId,
        batchEnded: batchEnded,
      );
      project = await _applyCompletionEvaluation(
        client: client,
        project: project,
        baseSystemPrompt: baseSystemPrompt,
        reviewReason: reviewReason,
        reviewMilestoneId: endedMilestoneId,
        onModelOutput: onModelOutput,
        questionAutonomy: questionAutonomy,
        cancellationToken: cancellationToken,
      );
      project = _progressMonitor.recordTaskResult(
        project: project,
        task: evaluatedProjectTask,
        taskAccepted: evaluation.taskAccepted,
        excludeFromStagnation: evaluation.projectReplanRequested,
        criterionStatusesBefore: criterionStatusesBefore,
        acceptedEvidenceIdsBefore: acceptedEvidenceIdsBefore,
        evaluatedAt: now,
      );
      project = project.copyWith(
        iterationCount: project.iterationCount + 1,
        updatedAt: DateTime.now(),
      );
      project = _advanceBatchCursor(project, evaluatedProjectTask.id);
      final pendingTriggers = _eligibleReplanTriggers(
        project.pendingReplanTriggers,
      );
      if (pendingTriggers.isNotEmpty && project.pendingReplanReason == null) {
        project = project.copyWith(
          pendingReplanReason: _replanReasonForTriggers(pendingTriggers),
        );
      }
      project = await _persistProject(
        workspace.rootPath,
        project,
        persistenceContext: persistenceContext,
      );
      runIterations++;
      if (project.status == ProjectStatus.completed ||
          project.status == ProjectStatus.failed ||
          project.status == ProjectStatus.waitingForUser ||
          project.status == ProjectStatus.blocked) {
        return ProjectCommandResult.fromSnapshot(
          project: project,
          activeTask: activeTask,
        );
      }
    }

    return ProjectCommandResult.fromSnapshot(
      project: project,
      activeTask: activeTask,
    );
  }

  Future<_ProjectTaskExecution> _executeProjectTask({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required ProjectTaskNode projectTask,
    required String baseSystemPrompt,
    required bool requirePhaseApproval,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    ProjectPersistenceContext? persistenceContext,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final effectiveCriterionIds = projectTask.criterionIds
        .where((id) => project.criteria.any((criterion) => criterion.id == id))
        .toSet();
    if (effectiveCriterionIds.isEmpty) {
      final blocked = _blockProject(
        project,
        ProjectBlockerType.validation,
        'Task ${projectTask.id} has no valid project criteria; no task document was created.',
        now,
        taskId: projectTask.id,
      );
      return _ProjectTaskExecution(
        project: await _persistProject(
          workspace.rootPath,
          blocked,
          persistenceContext: persistenceContext,
        ),
      );
    }
    final runningProjectTask = projectTask.copyWith(
      status: TaskStatus.running,
      updatedAt: now,
    );
    var workingProject = project.copyWith(
      activeTaskId: projectTask.id,
      tasks: _upsertTask(project, runningProjectTask),
      blocker: null,
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.createTask,
          'Selected next bounded project task: ${projectTask.title}',
          '',
          task: projectTask,
        ),
      ],
      updatedAt: now,
    );
    workingProject = lifecycleService
        .transition(
          snapshot: workingProject,
          to: ProjectStatus.runningTask,
          trigger: ProjectLifecycleTrigger.startTask,
          taskId: projectTask.id,
          now: now,
        )
        .project;
    final loadedTask = await _loadActiveTask(workspace, workingProject);
    // A queued Task record is the project definition, not yet an executable
    // plan. Only reuse a record once it contains executable steps.
    final existingTask = loadedTask?.steps.isNotEmpty == true
        ? loadedTask
        : null;
    workingProject = await _persistProject(
      workspace.rootPath,
      workingProject,
      persistenceContext: persistenceContext,
      checkpoint: ProjectPersistenceCheckpoint.taskExecutionStarted,
    );

    final planningContext = _planningContext(workingProject, projectTask);
    late Task activeTask;
    if (existingTask != null) {
      activeTask = existingTask;
    } else {
      activeTask = projectTask.effort == TaskEffort.small
          ? await _taskController.createProjectTask(
              workspace: workspace,
              userPrompt: _taskPrompt(workingProject, projectTask),
              chatSessionId: workingProject.chatSessionId,
              projectId: workingProject.id,
              planningContext: planningContext,
              canonicalTaskId: projectTask.id,
            )
          : await _taskController.createTask(
              client: client,
              workspace: workspace,
              userPrompt: _taskPrompt(workingProject, projectTask),
              selectedMode: ExecutionMode.task,
              baseSystemPrompt: _buildTaskSystemPrompt(
                baseSystemPrompt,
                workingProject,
                null,
              ),
              chatSessionId: workingProject.chatSessionId,
              projectId: workingProject.id,
              planningContext: planningContext,
              canonicalTaskId: projectTask.id,
              onModelOutput: onModelOutput,
              cancellationToken: cancellationToken,
            );
    }
    persistenceContext?.stageTask(activeTask);
    final executionRequest = TaskExecutionRequest.fromPlanningContext(
      planningContext,
    );
    workingProject = workingProject.copyWith(
      activeTaskId: projectTask.id,
      tasks: _upsertTask(
        workingProject,
        runningProjectTask.copyWith(updatedAt: DateTime.now()),
      ),
      updatedAt: DateTime.now(),
    );
    if (activeTask.planningError?.trim().isNotEmpty == true) {
      workingProject = _controlStateService.withOutcome(
        workingProject,
        outcome: ProjectControlOutcome.degradedPlanning,
        message: activeTask.planningError!,
        action: 'retry_planning',
        reasonCode: 'task_planning_failed',
        taskId: activeTask.id,
        now: DateTime.now(),
      );
    }
    workingProject = await _persistProject(
      workspace.rootPath,
      workingProject,
      persistenceContext: persistenceContext,
      checkpoint: ProjectPersistenceCheckpoint.taskExecution,
    );
    onTaskUpdated?.call(activeTask);

    while (activeTask.nextRunnableStep != null && !activeTask.isTerminal) {
      cancellationToken?.throwIfCancelled();
      activeTask = await _taskController.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: activeTask,
        baseSystemPrompt: _buildTaskSystemPrompt(
          baseSystemPrompt,
          workingProject,
          activeTask,
        ),
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
        executionRequest: executionRequest,
        persist: false,
      );
      onTaskUpdated?.call(activeTask);
      persistenceContext?.stageTask(activeTask);
      workingProject = _syncCurrentTaskFromTask(
        workingProject,
        activeTask,
        DateTime.now(),
      );
      final latestRun = activeTask.runs.isEmpty ? null : activeTask.runs.last;
      final interrupted =
          latestRun?.status == TaskRunStatus.failed ||
          latestRun?.status == TaskRunStatus.cancelled;
      var checkpoint = workingProject;
      if (activeTask.status == TaskStatus.paused && interrupted) {
        checkpoint = _transitionProject(
          snapshot: checkpoint.copyWith(blocker: null),
          to: ProjectStatus.paused,
          trigger: ProjectLifecycleTrigger.pause,
          reason: 'The task run was interrupted and can be resumed.',
          now: DateTime.now(),
        );
      } else if (cancellationToken?.isCancelled == true) {
        checkpoint = _transitionProject(
          snapshot: checkpoint,
          to: ProjectStatus.paused,
          trigger: ProjectLifecycleTrigger.pause,
          reason: 'The project run was cancelled before completion.',
          now: DateTime.now(),
        );
      } else {
        final blocker = _taskBlocker(activeTask);
        if (blocker != null) {
          final blockerRecord = ProjectBlocker(
            type: blocker.$1,
            message: blocker.$2,
            taskId: activeTask.id,
            createdAt: DateTime.now(),
          );
          checkpoint = lifecycleService
              .transition(
                snapshot: checkpoint.copyWith(blocker: blockerRecord),
                to: ProjectStatus.waitingForUser,
                trigger: ProjectLifecycleTrigger.pause,
                reason: blocker.$2,
                taskId: activeTask.id,
                blocker: blockerRecord,
                now: DateTime.now(),
              )
              .project;
        }
      }

      final persisted = await _persistProject(
        workspace.rootPath,
        checkpoint,
        persistenceContext: persistenceContext,
        checkpoint: ProjectPersistenceCheckpoint.taskExecution,
      );
      if (checkpoint.status == ProjectStatus.paused ||
          checkpoint.status == ProjectStatus.waitingForUser) {
        return _ProjectTaskExecution(
          project: persisted,
          activeTask: activeTask,
        );
      }
      workingProject = persisted;
    }

    if (!activeTask.isTerminal && activeTask.nextRunnableStep == null) {
      activeTask = await _taskController.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: activeTask,
        baseSystemPrompt: _buildTaskSystemPrompt(
          baseSystemPrompt,
          workingProject,
          activeTask,
        ),
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
        executionRequest: executionRequest,
        persist: false,
      );
      onTaskUpdated?.call(activeTask);
      persistenceContext?.stageTask(activeTask);
    }

    persistenceContext?.stageTask(activeTask);

    final result = _taskResultFromTask(
      _activeProjectTask(workingProject) ?? projectTask,
      activeTask,
    );
    final syncedProject = _syncCurrentTaskFromTask(
      workingProject,
      activeTask,
      DateTime.now(),
    );
    return _ProjectTaskExecution(
      project: syncedProject,
      activeTask: activeTask,
      result: result,
    );
  }

  /// Owns project creation and initial-plan validation policy.
  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelProvider? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final planning = await _planningHandler.initialise(
      workspace: workspace,
      userPrompt: userPrompt,
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      fallback: () => _fallbackInitialPlan(userPrompt),
      validate: _validateInitialPlan,
      blocksContextIssue: _blocksInitialPlanningForContextIssue,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final initialPlan = planning.initialPlan;
    var proposal = initialPlan.patch.plan;
    var planningIssues = planning.validationIssues;
    var modelCallCount = planning.modelCallCount;
    final repairAttempts = planning.repairAttempts;
    var planningMetrics = planning.planningMetrics;
    cancellationToken?.throwIfCancelled();

    final planningBlocked = planningIssues.isNotEmpty;
    final filteredQuestions = _filterProjectQuestions(
      proposal.openQuestions,
      autonomy: questionAutonomy,
    );
    final initialCriteria = proposal.criteria;
    final initialCriterionIds = initialCriteria.map((item) => item.id).toList();
    final initialBacklog = planningBlocked
        ? const <ProjectTaskNode>[]
        : _normaliseInitialBacklog(proposal.tasks, initialCriterionIds);
    final initialMilestones = _initialMilestones(
      milestones: proposal.milestones,
      refinedGoal: initialPlan.patch.refinedGoal ?? userPrompt,
      criteria: initialCriteria,
      now: now,
    );
    final initialMemory = _initialMemory(
      memory: proposal.memoryAdditions,
      policyAssumptions: filteredQuestions.assumptions,
      now: now,
    );
    proposal = proposal.copyWith(
      milestones: initialMilestones,
      tasks: initialBacklog,
      memoryAdditions: initialMemory,
      openQuestions: filteredQuestions.blocking,
    );

    if (planningMetrics.planningCalls == 0 && modelCallCount > 0) {
      planningMetrics = planningMetrics.copyWith(planningCalls: modelCallCount);
    }
    planningMetrics = planningMetrics.copyWith(
      planningStartedAt: now,
      fullPlanRepairCount: planningMetrics.fullPlanRepairCount + repairAttempts,
      validationBlockerCount:
          planningMetrics.validationBlockerCount + (planningBlocked ? 1 : 0),
      timeToFirstExecutableMs:
          !planningBlocked &&
              filteredQuestions.blocking.isEmpty &&
              initialBacklog.any((task) => task.status == TaskStatus.queued)
          ? DateTime.now().difference(now).inMilliseconds
          : null,
    );
    if (planningMetrics.planningCalls > modelCallCount) {
      modelCallCount = planningMetrics.planningCalls;
    }

    final title = (initialPlan.patch.title ?? '').trim().isEmpty
        ? _titleFromPrompt(userPrompt)
        : initialPlan.patch.title!.trim();
    final refinedGoal = (initialPlan.patch.refinedGoal ?? '').trim().isEmpty
        ? userPrompt
        : initialPlan.patch.refinedGoal!.trim();
    final constraints = initialPlan.patch.constraints?.isEmpty ?? true
        ? const ['Stay within the attached workspace.']
        : initialPlan.patch.constraints!;

    // This is a shell only. The initial plan patch below is applied once to
    // this real project ID; no planning_* project or second reconciliation is
    // created.
    var project = ProjectDocument(
      id: _newProjectId(userPrompt),
      title: title,
      originalGoal: userPrompt,
      refinedGoal: refinedGoal,
      constraints: constraints,
      criteria: const [],
      tasks: const [],
      artifacts: const [],
      memory: const [],
      milestones: const [],
      planHistory: const [],
      openQuestions: const [],
      status: ProjectStatus.initializing,
      iterationCount: 0,
      maxIterations: _normaliseOptionalLimit(
        maxIterations,
        fallback: ProjectDocument.defaultMaxIterations,
      ),
      maxFailedTasks: ProjectDocument.defaultMaxFailedTasks,
      activeTaskId: null,
      chatSessionId: chatSessionId,
      completionSummary: '',
      blocker: planningBlocked
          ? ProjectBlocker(
              type: ProjectBlockerType.validation,
              message: _initialPlanningBlockerMessage(planningIssues),
              createdAt: now,
            )
          : null,
      decisions: const [],
      diagnostics: ProjectDiagnostics(
        projectModelCalls: modelCallCount,
        userQuestions: filteredQuestions.blocking.length,
        planningMetrics: planningMetrics,
      ),
      createdAt: now,
      updatedAt: now,
    );

    if (!planningBlocked) {
      final committed = await _planningHandler.prepareAndApplyPatch(
        project: project,
        patch: ProjectPlanPatch.initial(
          proposal,
          title: title,
          refinedGoal: refinedGoal,
          constraints: constraints,
        ),
        workspaceRoot: workspace.rootPath,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );
      project = committed.project;
      planningIssues = [
        for (final issue in committed.validation.issues)
          if (issue.severity == ProjectPlanValidationSeverity.error)
            {'code': issue.code, 'message': issue.message},
      ];
    } else {
      project = _transitionProject(
        snapshot: project,
        to: ProjectStatus.blocked,
        trigger: ProjectLifecycleTrigger.initialization,
        reason: project.blocker?.message ?? 'Initial planning was blocked.',
        blocker: project.blocker,
        now: now,
      );
    }
    if (client == null || initialPlan.planningError != null) {
      project = _controlStateService.withOutcome(
        project,
        outcome: ProjectControlOutcome.degradedPlanning,
        message:
            initialPlan.planningError ??
            'Project was created from a safe fallback because no planning model was available.',
        action: 'retry_planning',
        reasonCode: client == null ? 'model_unavailable' : 'planning_failed',
        now: now,
      );
    }
    return _persistProject(
      workspace.rootPath,
      project,
      checkpoint: ProjectPersistenceCheckpoint.initialization,
    );
  }

  bool _blocksInitialPlanningForContextIssue(
    WorkspaceRequiredContextIssue issue,
  ) => issue.code == 'required_context_unreadable';
}
