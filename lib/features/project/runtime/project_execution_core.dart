part of 'project_execution_state_machine.dart';

extension ProjectExecutionCore on ProjectExecutionStateMachine {
  Future<ProjectCommandResult> _runProjectCore({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String baseSystemPrompt,
    required int maxNewTasks,
    int? maxIterations,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
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
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required ProjectTaskNode projectTask,
    required String baseSystemPrompt,
    required bool requirePhaseApproval,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
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
          ? await _taskProjectPlanning.createProjectTask(
              workspace: workspace,
              userPrompt: _taskPrompt(workingProject, projectTask),
              chatSessionId: workingProject.chatSessionId,
              projectId: workingProject.id,
              planningContext: planningContext,
              canonicalTaskId: projectTask.id,
            )
          : await _taskPlanning.createTask(
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
      activeTask = await _taskExecution.runNextStep(
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
      activeTask = await _taskExecution.runNextStep(
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
  Future<ProjectAggregate> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelCompletionPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
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
    var project = ProjectAggregate(
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
        fallback: ProjectAggregate.defaultMaxIterations,
      ),
      maxFailedTasks: ProjectAggregate.defaultMaxFailedTasks,
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
            ProjectPlanValidationIssue(
              code: issue.code,
              path: '',
              message: issue.message,
            ),
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
  // Project helper operations
  ProjectRepositoryPort get repository => _repository;

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _commandService.execute(request, port: _executionPort);

  List<String> _appendUnique(List<String> current, String value) {
    if (value.trim().isEmpty || current.contains(value)) return current;
    return [...current, value];
  }

  TaskResult _taskResultFromTask(ProjectTaskNode projectTask, Task task) {
    final latestRun = task.runs.isEmpty ? null : task.runs.last;
    final artifacts = <TaskArtifact>[
      for (final run in task.runs)
        for (final artifact in run.artifacts)
          TaskArtifact(
            id: 'artifact_${uuid.v7()}',
            taskId: projectTask.id,
            runId: run.runId,
            path: artifact.path,
            description: artifact.description ?? '',
            kind: artifact.kind,
            createdAt: artifact.createdAt ?? DateTime.now(),
          ),
    ];
    return TaskResult(
      taskId: task.id,
      status: task.status,
      summary: latestRun?.summary ?? task.memorySummary,
      memoryUpdate: latestRun?.memoryUpdate ?? task.memorySummary,
      artifacts: artifacts,
      gateResults: latestRun?.gateResults ?? const [],
      evidenceClaims: [for (final run in task.runs) ...run.evidenceClaims],
      finalRunId: latestRun?.runId,
      toolCallCount: task.runs.fold<int>(
        0,
        (sum, run) => sum + run.toolCalls.length,
      ),
      userQuestion: task.pendingQuestion?.question,
      error: latestRun?.error,
      projectReplanRequested: task.runs.any(
        (run) =>
            run.status == TaskRunStatus.needsReplan ||
            (run.replanReason?.trim().isNotEmpty ?? false),
      ),
    );
  }

  String _projectEvidenceTypeWire(ProjectEvidenceType type) => switch (type) {
    ProjectEvidenceType.taskClaim => 'task_claim',
    ProjectEvidenceType.userApproval => 'user_approval',
    _ => type.name,
  };

  (ProjectBlockerType, String)? _taskBlocker(Task task) {
    if (task.pendingApproval != null) {
      return (
        ProjectBlockerType.taskEditApproval,
        task.pendingApproval!.reason,
      );
    }
    if (task.pendingQuestion != null) {
      return (ProjectBlockerType.taskBlocked, task.pendingQuestion!.question);
    }
    if (task.status == TaskStatus.blocked) {
      return (
        ProjectBlockerType.taskBlocked,
        'Task `${task.title}` is blocked.',
      );
    }
    return null;
  }

  ProjectAggregate _syncCurrentTaskFromTask(
    ProjectAggregate project,
    Task task,
    DateTime now,
  ) {
    final current = _activeProjectTask(project);
    if (current == null) return project;
    final nextStatus = switch (task.status) {
      TaskStatus.completed => TaskStatus.completed,
      TaskStatus.failed => TaskStatus.failed,
      TaskStatus.cancelled => TaskStatus.cancelled,
      _ => TaskStatus.running,
    };
    return project.copyWith(
      tasks: _upsertTask(
        project,
        current.copyWith(status: nextStatus, updatedAt: now),
      ),
      activeTaskId: task.isTerminal ? null : current.id,
      updatedAt: now,
    );
  }

  ProjectAggregate _waitingForUser(ProjectAggregate project, DateTime now) {
    final blocker =
        project.blocker ??
        (project.openQuestions.isEmpty
            ? null
            : ProjectBlocker(
                type: ProjectBlockerType.question,
                message: project.openQuestions.first.question,
                createdAt: now,
              ));
    final prepared = project.copyWith(blocker: blocker, updatedAt: now);
    return lifecycleService
        .transition(
          snapshot: prepared,
          to: ProjectStatus.waitingForUser,
          trigger: ProjectLifecycleTrigger.pause,
          reason: blocker?.message ?? 'Project is waiting for user input.',
          blocker: blocker,
          now: now,
        )
        .project;
  }

  _FilteredProjectQuestions _filterProjectQuestions(
    List<PendingProjectQuestion> questions, {
    required QuestionAutonomy autonomy,
  }) {
    final blocking = <PendingProjectQuestion>[];
    final assumptions = <String>[];
    for (final question in questions) {
      final decision = _questionPolicy.decide(
        question: AgentQuestion.fromText(question.question),
        autonomy: autonomy,
      );
      if (decision.shouldBlock) {
        blocking.add(question);
      } else {
        assumptions.add(decision.assumption);
      }
    }
    return _FilteredProjectQuestions(
      blocking: blocking,
      assumptions: assumptions,
    );
  }

  ProjectAggregate _blockProject(
    ProjectAggregate project,
    ProjectBlockerType type,
    String message,
    DateTime now, {
    String? taskId,
  }) {
    final blocker = ProjectBlocker(
      type: type,
      message: message,
      taskId: taskId,
      createdAt: now,
    );
    return lifecycleService
        .transition(
          snapshot: project,
          to: ProjectStatus.blocked,
          trigger: ProjectLifecycleTrigger.failure,
          reason: message,
          taskId: taskId,
          blocker: blocker,
          now: now,
        )
        .project;
  }

  List<String> _remainingCriteria(ProjectAggregate project) {
    return project.criteria
        .where(
          (criterion) =>
              criterion.required &&
              criterion.status != ProjectCriterionStatus.satisfied &&
              criterion.status != ProjectCriterionStatus.invalidated,
        )
        .map((criterion) => criterion.statement)
        .toList();
  }

  List<TaskArtifact> _mergeArtifacts(
    List<TaskArtifact> current,
    List<TaskArtifact> additions,
  ) {
    final byPath = <String, TaskArtifact>{
      for (final artifact in current) artifact.path: artifact,
    };
    for (final artifact in additions) {
      byPath[artifact.path] = artifact;
    }
    return byPath.values.toList();
  }

  ProjectAggregate _recordAssumptions(
    ProjectAggregate project,
    List<String> assumptions, {
    String? sourceId,
    DateTime? timestamp,
  }) {
    var updated = project;
    for (final assumption in assumptions) {
      if (assumption.trim().isEmpty) continue;
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.assumption,
            content: assumption,
            sourceType: ProjectMemorySourceType.planner,
            sourceId: sourceId,
            confidence: ProjectMemoryConfidence.inferred,
            timestamp: timestamp,
          )
          .project;
    }
    return updated;
  }

  ProjectAggregate _recordTaskMemory({
    required ProjectAggregate project,
    required ProjectTaskNode task,
    required ProjectEvaluation evaluation,
    required List<String> assumptions,
    required bool accepted,
    bool recordFailureRisk = true,
    required DateTime timestamp,
  }) {
    var updated = project;
    if (evaluation.summary.trim().isNotEmpty) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.summary,
            content: evaluation.summary,
            sourceType: ProjectMemorySourceType.task,
            sourceId: task.id,
            // Task summaries are model-reported descriptions. A completed
            // task can have deterministic evidence, but that evidence does
            // not prove every factual statement in the summary.
            confidence: accepted
                ? ProjectMemoryConfidence.inferred
                : ProjectMemoryConfidence.uncertain,
            timestamp: timestamp,
          )
          .project;
    }
    for (final fact in evaluation.newKnownFacts) {
      if (fact.trim().isEmpty ||
          _normalise(fact) == _normalise(evaluation.summary)) {
        continue;
      }
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.fact,
            content: fact,
            sourceType: ProjectMemorySourceType.task,
            sourceId: task.id,
            // Facts extracted from model output remain unverified even when
            // the surrounding task passed its completion gates.
            confidence: accepted
                ? ProjectMemoryConfidence.inferred
                : ProjectMemoryConfidence.uncertain,
            timestamp: timestamp,
          )
          .project;
    }
    if (!accepted &&
        recordFailureRisk &&
        evaluation.failureReason?.trim().isNotEmpty == true) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.risk,
            content:
                'Task ${task.id} failed: ${evaluation.failureReason!.trim()}',
            sourceType: ProjectMemorySourceType.task,
            sourceId: task.id,
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            timestamp: timestamp,
          )
          .project;
    }
    return _recordAssumptions(
      updated,
      assumptions,
      sourceId: task.id,
      timestamp: timestamp,
    );
  }

  ProjectAggregate _projectForModel(
    ProjectAggregate project, {
    ProjectTaskNode? task,
  }) {
    final selection = _memoryService.selectContext(
      project: project,
      task: task,
    );
    final selectedIds = selection.selectedMemoryEntryIds.toSet();
    return project.copyWith(
      memory: [
        for (final entry in project.memory)
          if (selectedIds.contains(entry.id)) entry,
      ],
    );
  }

  Set<String> _knownFingerprints(
    ProjectAggregate project, {
    String? excludingTaskId,
  }) {
    return {
      for (final task in project.tasks)
        if (task.id != excludingTaskId && task.recoveryIncidentId == null)
          task.fingerprint,
      for (final decision in project.decisions)
        if (decision.taskPrompt?.trim().isNotEmpty == true)
          projectTaskFingerprint(decision.taskPrompt!, const []),
    };
  }

  List<ProjectTaskNode> _normaliseBacklog(List<ProjectTaskNode> tasks) {
    final seen = <String>{};
    return [
      for (final task in tasks)
        if (task.objective.trim().isNotEmpty && seen.add(task.fingerprint))
          task.copyWith(
            status: task.status == TaskStatus.running
                ? TaskStatus.queued
                : task.status,
            updatedAt: DateTime.now(),
          ),
    ];
  }

  List<ProjectTaskNode> _normaliseInitialBacklog(
    List<ProjectTaskNode> tasks,
    List<String> criterionIds,
  ) {
    final knownCriterionIds = criterionIds.toSet();
    return [
      for (final task in _normaliseBacklog(tasks))
        if (task.criterionIds.isNotEmpty &&
            task.criterionIds.every(knownCriterionIds.contains))
          task.copyWith(
            expectedEvidence: [
              for (final expectation in task.expectedEvidence)
                TaskEvidenceExpectation(
                  id: expectation.id,
                  type: expectation.type,
                  criterionIds: expectation.criterionIds.isEmpty
                      ? task.criterionIds
                      : expectation.criterionIds
                            .where(task.criterionIds.contains)
                            .toSet()
                            .toList(),
                  description: expectation.description,
                  required: expectation.required,
                  sourceRef: expectation.sourceRef,
                  details: expectation.details,
                ),
            ],
          ),
    ];
  }

  ProjectAggregate _recordTransitionReplanTriggers({
    required ProjectAggregate project,
    required ProjectEvaluation evaluation,
    required Set<String> invalidEvidenceIdsBefore,
    required DateTime now,
  }) {
    var milestones = project.milestones;
    var milestoneCompleted = false;
    final satisfiedCriterionIds = {
      for (final criterion in project.criteria)
        if (criterion.status == ProjectCriterionStatus.satisfied) criterion.id,
    };
    milestones = [
      for (final milestone in milestones)
        if (milestone.status != ProjectMilestoneStatus.completed &&
            ((milestone.criterionIds.isNotEmpty &&
                    milestone.criterionIds.every(
                      satisfiedCriterionIds.contains,
                    )) ||
                (() {
                  final taskIds = project.tasks
                      .where((task) => task.milestoneId == milestone.id)
                      .map((task) => task.id)
                      .toSet();
                  return taskIds.isNotEmpty &&
                      taskIds.every(
                        (taskId) =>
                            project.taskById(taskId)?.status ==
                            TaskStatus.completed,
                      );
                })()))
          _completedMilestone(milestone, now, () => milestoneCompleted = true)
        else
          milestone,
    ];
    if (milestoneCompleted) {
      var activatedNext = false;
      milestones = [
        for (final milestone in milestones)
          if (!activatedNext &&
              milestone.status == ProjectMilestoneStatus.planned)
            (() {
              activatedNext = true;
              return ProjectMilestone(
                id: milestone.id,
                title: milestone.title,
                objective: milestone.objective,
                criterionIds: milestone.criterionIds,
                status: ProjectMilestoneStatus.active,
                exitConditions: milestone.exitConditions,
                order: milestone.order,
                createdAt: milestone.createdAt,
                updatedAt: now,
              );
            })()
          else
            milestone,
      ];
    }

    var triggers = _eligibleReplanTriggers(project.pendingReplanTriggers);
    final activeMilestone = milestones
        .where((item) => item.status == ProjectMilestoneStatus.active)
        .firstOrNull;
    final activeMilestoneHasPlannedWork =
        activeMilestone != null &&
        project.tasks.any(
          (task) =>
              task.milestoneId == activeMilestone.id &&
              task.status != TaskStatus.completed &&
              task.status != TaskStatus.failed &&
              task.status != TaskStatus.rejected &&
              task.status != TaskStatus.split &&
              task.status != TaskStatus.deferred &&
              task.status != TaskStatus.obsolete &&
              task.status != TaskStatus.cancelled,
        );
    if (milestoneCompleted &&
        activeMilestone != null &&
        !activeMilestoneHasPlannedWork) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.milestoneRoadmapChanged,
      );
    }
    if (!evaluation.taskAccepted) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.taskFailed,
      );
    }
    if (evaluation.projectReplanRequested) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.taskReplanRequested,
      );
    }
    final hasNewRejectedEvidence = project.evidence.any((item) {
      return (item.status == ProjectEvidenceStatus.rejected ||
              item.status == ProjectEvidenceStatus.stale) &&
          !invalidEvidenceIdsBefore.contains(item.id);
    });
    if (hasNewRejectedEvidence) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.evidenceRejected,
      );
    }
    final pendingReplanReason = project.isTerminal || triggers.isEmpty
        ? null
        : project.pendingReplanReason ?? _replanReasonForTriggers(triggers);
    return project.copyWith(
      milestones: milestones,
      pendingReplanTriggers: project.isTerminal ? const [] : triggers,
      pendingReplanReason: pendingReplanReason,
      updatedAt: now,
    );
  }

  ProjectMilestone _completedMilestone(
    ProjectMilestone milestone,
    DateTime now,
    void Function() onCompleted,
  ) {
    onCompleted();
    return ProjectMilestone(
      id: milestone.id,
      title: milestone.title,
      objective: milestone.objective,
      criterionIds: milestone.criterionIds,
      status: ProjectMilestoneStatus.completed,
      exitConditions: milestone.exitConditions,
      order: milestone.order,
      createdAt: milestone.createdAt,
      updatedAt: now,
      completedAt: now,
    );
  }

  List<ProjectPlanRevisionTrigger> _appendTrigger(
    List<ProjectPlanRevisionTrigger> current,
    ProjectPlanRevisionTrigger trigger,
  ) {
    return current.contains(trigger) ? current : [...current, trigger];
  }

  List<ProjectPlanRevisionTrigger> _eligibleReplanTriggers(
    Iterable<ProjectPlanRevisionTrigger> triggers,
  ) {
    return {
      for (final trigger in triggers)
        if (ProjectExecutionStateMachine._runtimeReplanTriggers.contains(
          trigger,
        ))
          trigger,
    }.toList();
  }

  ProjectDecisionRecord _decision(
    ProjectDecisionType type,
    String summary,
    String memoryUpdate, {
    ProjectTaskNode? task,
    String? error,
  }) {
    return ProjectDecisionRecord(
      id: 'decision_${uuid.v7()}',
      decision: type,
      summary: summary,
      memoryUpdate: memoryUpdate,
      taskId: task?.id,
      taskTitle: task?.title,
      taskPrompt: task?.objective,
      error: error,
      createdAt: DateTime.now(),
    );
  }

  String _taskPrompt(ProjectAggregate project, ProjectTaskNode task) {
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    final workspaceContext = const ProjectWorkspaceContextService()
        .selectContext(project: project, task: task);
    final buffer = StringBuffer()
      ..writeln('Project goal:')
      ..writeln(project.refinedGoal)
      ..writeln()
      ..writeln('Selected bounded Project task:')
      ..writeln(task.objective)
      ..writeln()
      ..writeln('Done criteria:')
      ..writeln(_bulletList(task.doneCriteria))
      ..writeln()
      ..writeln('Out of scope:')
      ..writeln(_bulletList(task.outOfScope))
      ..writeln()
      ..writeln('Relevant project success criteria:')
      ..writeln(_bulletList(project.criterionStatementsFor(task)))
      ..writeln()
      ..writeln('Known project facts:')
      ..writeln(_bulletList([...memoryContext.lines, ...task.context]));
    if (workspaceContext.orientation.trim().isNotEmpty ||
        workspaceContext.lines.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Workspace orientation:')
        ..writeln(
          workspaceContext.orientation.trim().isEmpty
              ? '- None specified.'
              : workspaceContext.orientation,
        )
        ..writeln()
        ..writeln('Relevant workspace context:')
        ..writeln(_bulletList(workspaceContext.lines));
    }
    return buffer.toString().trim();
  }

  String _buildTaskSystemPrompt(
    String baseSystemPrompt,
    ProjectAggregate project,
    Task? task,
  ) {
    final activeTaskLine = task == null
        ? ''
        : '\nActive task document: ${task.title} (${task.id})';
    final activeRecovery = project.recoveryIncidents
        .where(
          (incident) => incident.status == ProjectRecoveryIncidentStatus.active,
        )
        .firstOrNull;
    final recoveryLine = activeRecovery == null
        ? ''
        : '\nActive recovery incident: ${activeRecovery.id}. Required gate restoration is the only valid project work until this incident is resolved.';
    return '''
$baseSystemPrompt

You are executing one bounded task inside a persistent Project orchestrator.
Project id: ${project.id}
Project goal: ${project.refinedGoal}
Complete only the active bounded Project task. Do not expand into the full project. The application will select the next task after this one is evaluated.$activeTaskLine$recoveryLine
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Ask the user only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
'''
        .trim();
  }

  String _bulletList(List<String> items) {
    if (items.isEmpty) return '- None specified.';
    return items.map((item) => '- $item').join('\n');
  }

  bool _wasInterrupted(ProjectStatus status) {
    return status == ProjectStatus.initializing ||
        status == ProjectStatus.runningTask ||
        status == ProjectStatus.reviewingTask;
  }

  String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _newProjectId(String prompt) {
    final slug = _titleFromPrompt(prompt)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = slug.isEmpty ? 'project' : slug;
    return 'project_${prefix.length > 32 ? prefix.substring(0, 32) : prefix}_${uuid.v7().substring(0, 8)}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled project';
    return singleLine.length <= 60
        ? singleLine
        : '${singleLine.substring(0, 57)}...';
  }

  int _normaliseOptionalLimit(int? value, {int fallback = 0}) {
    final resolved = value ?? fallback;
    return resolved < 0 ? 0 : resolved;
  }

  // Project planning and recovery operations
  /// Owns the runtime graph used by the project use cases.
  List<ProjectPlanValidationIssue> _validateInitialPlan({
    required ProjectInitialPlanResult initialPlan,
    required WorkspaceDiscoveryProfile workspaceProfile,
  }) {
    final plan = initialPlan.patch.plan;
    final issues = <ProjectPlanValidationIssue>[];
    void add(String code, String message, {String? path}) {
      issues.add(
        ProjectPlanValidationIssue(
          code: code,
          message: message,
          path: path ?? '',
        ),
      );
    }

    final criteria = plan.criteria;
    final criterionIds = <String>{};
    for (final criterion in criteria) {
      if (criterion.id.trim().isEmpty || criterion.statement.trim().isEmpty) {
        add(
          'invalid_criterion',
          'Every success criterion needs a non-empty stable ID and statement.',
        );
      } else if (!criterionIds.add(criterion.id)) {
        add(
          'duplicate_criterion_id',
          'Criterion ID ${criterion.id} is declared more than once.',
        );
      }
      if (criterion.status != ProjectCriterionStatus.unsatisfied ||
          criterion.verifiedAt != null) {
        add(
          'unsupported_initial_criterion_progress',
          'Criterion ${criterion.id} claims evaluator-owned progress during initialization.',
        );
      }
    }
    if (criterionIds.isEmpty) {
      add(
        'missing_criteria',
        'The initial plan must define at least one success criterion.',
      );
    }

    final taskById = <String, ProjectTaskNode>{};
    for (final task in plan.tasks) {
      if (task.id.trim().isEmpty || taskById.containsKey(task.id)) {
        add(
          'invalid_task_id',
          'Every initial task needs a unique, non-empty stable ID.',
        );
      } else {
        taskById[task.id] = task;
      }
    }
    if (taskById.isEmpty && plan.openQuestions.isEmpty) {
      add(
        'missing_executable_tasks',
        'The initial plan must contain bounded executable work or a blocking question.',
      );
    }

    final milestoneIds = <String>{};
    for (final milestone in plan.milestones) {
      if (milestone.id.trim().isEmpty || !milestoneIds.add(milestone.id)) {
        add(
          'invalid_milestone_id',
          'Every milestone needs a unique, non-empty stable ID.',
        );
      }
      for (final criterionId in milestone.criterionIds) {
        if (!criterionIds.contains(criterionId)) {
          add(
            'unknown_milestone_criterion',
            'Milestone ${milestone.id} references unknown criterion $criterionId.',
          );
        }
      }
    }
    if (taskById.isNotEmpty && milestoneIds.isEmpty) {
      add(
        'missing_milestones',
        'The initial plan must place executable work in at least one milestone.',
      );
    }

    final workspacePaths = {
      for (final item in workspaceProfile.treePaths)
        _normaliseWorkspacePath(
          item.endsWith('/') ? item.substring(0, item.length - 1) : item,
        ),
    };
    for (final task in taskById.values) {
      if (task.objective.trim().isEmpty ||
          task.doneCriteria.isEmpty ||
          task.outOfScope.isEmpty) {
        add(
          'invalid_task_structure',
          'Task ${task.id} needs an objective, done criteria, and out-of-scope boundaries.',
        );
      }
      if (task.status != TaskStatus.queued &&
          task.status != TaskStatus.deferred) {
        add(
          'invalid_initial_task_status',
          'Task ${task.id} cannot claim execution progress during initialization.',
        );
      }
      if (task.criterionIds.isEmpty) {
        add(
          'task_without_criteria',
          'Task ${task.id} must reference at least one project criterion.',
        );
      }
      for (final criterionId in task.criterionIds) {
        if (!criterionIds.contains(criterionId)) {
          add(
            'unknown_task_criterion',
            'Task ${task.id} references unknown criterion $criterionId.',
          );
        }
      }
      if (task.milestoneId == null ||
          !milestoneIds.contains(task.milestoneId)) {
        add(
          'unknown_task_milestone',
          'Task ${task.id} must reference a declared milestone.',
        );
      }
      for (final dependencyId in task.dependsOnTaskIds) {
        if (!taskById.containsKey(dependencyId) || dependencyId == task.id) {
          add(
            'invalid_task_dependency',
            'Task ${task.id} has invalid dependency $dependencyId.',
          );
        }
      }
      if (task.expectedEvidence.isEmpty) {
        add(
          'missing_evidence_expectation',
          'Task ${task.id} must declare expected evidence.',
        );
      }
      for (final expectation in task.expectedEvidence) {
        if (expectation.id.trim().isEmpty ||
            expectation.description.trim().isEmpty) {
          add(
            'invalid_evidence_expectation',
            'Every evidence expectation on task ${task.id} needs an ID and description.',
          );
        }
        if (expectation.criterionIds.isEmpty) {
          add(
            'evidence_without_criteria',
            'Evidence ${expectation.id} on task ${task.id} has no criterion link.',
          );
        }
        for (final criterionId in expectation.criterionIds) {
          if (!criterionIds.contains(criterionId) ||
              !task.criterionIds.contains(criterionId)) {
            add(
              'invalid_evidence_criterion',
              'Evidence ${expectation.id} references criterion $criterionId outside task ${task.id}.',
            );
          }
        }
      }
      for (final readPath in task.readPaths) {
        final normalized = _normaliseWorkspacePath(readPath);
        if (!_isSafeRelativeWorkspacePath(normalized)) {
          add(
            'read_path_outside_workspace',
            'Task ${task.id} readPath is outside the workspace.',
            path: readPath,
          );
          continue;
        }
        final exists = workspacePaths.any(
          (candidate) => _pathCovers(candidate, normalized),
        );
        final producedByDependency = task.dependsOnTaskIds.any((dependencyId) {
          final dependency = taskById[dependencyId];
          if (dependency == null) return false;
          final outputs = <String>[
            ...dependency.writePaths,
            ...dependency.expectedArtifacts.map((item) => item.path),
          ].map(_normaliseWorkspacePath);
          return outputs.any((output) => _pathCovers(output, normalized));
        });
        if (!exists && !producedByDependency) {
          add(
            'ungrounded_read_path',
            'Task ${task.id} treats a missing path as existing, and no declared dependency produces it.',
            path: readPath,
          );
        }
      }
      for (final writePath in task.writePaths) {
        final normalized = _normaliseWorkspacePath(writePath);
        if (!_isSafeRelativeWorkspacePath(normalized)) {
          add(
            'write_path_outside_workspace',
            'Task ${task.id} writePath is outside the workspace.',
            path: writePath,
          );
        }
      }
      for (final artifact in task.expectedArtifacts) {
        final normalized = _normaliseWorkspacePath(artifact.path);
        if (artifact.path.trim().isEmpty ||
            !_isSafeRelativeWorkspacePath(normalized)) {
          add(
            'artifact_path_outside_workspace',
            'Task ${task.id} has an invalid expected artifact path.',
            path: artifact.path,
          );
        }
      }
      if (task.effort == TaskEffort.small &&
          task.expectedArtifacts.isNotEmpty &&
          task.writePaths.isEmpty) {
        add(
          'missing_write_paths',
          'Small artifact-producing tasks must declare write paths.',
        );
      }
    }

    for (final criterion in criteria) {
      if (criterion.status == ProjectCriterionStatus.satisfied ||
          criterion.verificationMode != ProjectVerificationMode.deterministic) {
        continue;
      }
      final hasConclusiveExpectation = plan.tasks.any(
        (task) => task.expectedEvidence.any(
          (expectation) =>
              expectation.required &&
              expectation.criterionIds.contains(criterion.id) &&
              (expectation.type == ProjectEvidenceType.gate ||
                  expectation.type == ProjectEvidenceType.command),
        ),
      );
      if (!hasConclusiveExpectation) {
        add(
          'impossible_deterministic_verification',
          'Deterministic criterion ${criterion.id} needs a required gate or command evidence expectation.',
        );
      }
    }

    final dependencyGraph = <String, List<String>>{
      for (final task in taskById.values) task.id: task.dependsOnTaskIds,
    };
    if (_hasDependencyCycle(dependencyGraph)) {
      add(
        'cyclic_dependencies',
        'The initial task dependency graph contains a cycle.',
      );
    }

    final memoryIds = <String>{};
    for (final entry in plan.memoryAdditions) {
      if (entry.id.trim().isEmpty || !memoryIds.add(entry.id)) {
        add(
          'invalid_memory_id',
          'Planner memory entries need unique, non-empty IDs.',
        );
      }
      if (entry.content.trim().isEmpty) {
        add('empty_memory', 'Planner memory entries cannot be empty.');
      }
    }
    return issues;
  }

  String _initialPlanningBlockerMessage(
    List<ProjectPlanValidationIssue> issues,
  ) {
    final details = issues
        .map((issue) {
          final path = issue.path;
          return '${issue.code}${path.isEmpty ? '' : ' ($path)'}: ${issue.message}';
        })
        .join(' ');
    return 'Initial planning was blocked because required context or plan structure was invalid. $details';
  }

  String _normaliseWorkspacePath(String value) => path
      .normalize(value.trim().replaceAll('\\', '/'))
      .replaceFirst(RegExp(r'^\./'), '');

  bool _isSafeRelativeWorkspacePath(String value) =>
      value.isNotEmpty &&
      !path.isAbsolute(value) &&
      value != '..' &&
      !value.startsWith('../');

  bool _pathCovers(String declaredPath, String candidatePath) {
    if (declaredPath.isEmpty || candidatePath.isEmpty) return false;
    return candidatePath == declaredPath ||
        candidatePath.startsWith('$declaredPath/');
  }

  bool _hasDependencyCycle(Map<String, List<String>> graph) {
    final states = <String, int>{};

    bool visit(String id) {
      final state = states[id] ?? 0;
      if (state == 1) return true;
      if (state == 2) return false;
      states[id] = 1;
      for (final dependency in graph[id] ?? const <String>[]) {
        if (graph.containsKey(dependency) && visit(dependency)) return true;
      }
      states[id] = 2;
      return false;
    }

    for (final id in graph.keys) {
      if (visit(id)) return true;
    }
    return false;
  }

  List<ProjectMilestone> _initialMilestones({
    required List<ProjectMilestone> milestones,
    required String refinedGoal,
    required List<ProjectCriterion>? criteria,
    required DateTime now,
  }) {
    final criterionIds = criteria?.map((item) => item.id).toList() ?? const [];
    final criterionStatements =
        criteria?.map((item) => item.statement).toList() ?? const [];
    final proposed = milestones.isEmpty
        ? [
            ProjectMilestone(
              id: 'milestone_001',
              title: 'Deliver the project outcome',
              objective: refinedGoal,
              criterionIds: criterionIds,
              status: ProjectMilestoneStatus.active,
              exitConditions: criterionStatements,
              order: 1,
              createdAt: now,
              updatedAt: now,
            ),
          ]
        : milestones;
    return [
      for (var index = 0; index < proposed.length; index++)
        ProjectMilestone(
          id: proposed[index].id,
          title: proposed[index].title,
          objective: proposed[index].objective,
          criterionIds: proposed[index].criterionIds,
          status: index == 0
              ? ProjectMilestoneStatus.active
              : ProjectMilestoneStatus.planned,
          exitConditions: proposed[index].exitConditions,
          order: proposed[index].order,
          createdAt: proposed[index].createdAt,
          updatedAt: now,
          completedAt: null,
        ),
    ];
  }

  List<ProjectMemoryEntry> _initialMemory({
    required List<ProjectMemoryEntry> memory,
    required List<String> policyAssumptions,
    required DateTime now,
  }) {
    final entries = <ProjectMemoryEntry>[];
    final usedIds = <String>{};
    final contents = <String>{};
    for (var index = 0; index < memory.length; index++) {
      final proposed = memory[index];
      final content = proposed.content.trim();
      if (content.isEmpty || !contents.add(_normalise(content))) continue;
      final baseId = proposed.id.trim().isEmpty
          ? 'memory_${(index + 1).toString().padLeft(3, '0')}'
          : proposed.id;
      var id = baseId;
      var suffix = 2;
      while (!usedIds.add(id)) {
        id = '${baseId}_$suffix';
        suffix++;
      }
      entries.add(
        ProjectMemoryEntry(
          id: id,
          kind: proposed.kind,
          content: content,
          sourceType: ProjectMemorySourceType.planner,
          sourceId: proposed.sourceId,
          confidence: ProjectMemoryConfidence.inferred,
          protected: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    var index = entries.length + 1;
    void add(String content, ProjectMemoryKind kind) {
      if (content.trim().isEmpty || !contents.add(_normalise(content))) {
        return;
      }
      var id = 'memory_${index.toString().padLeft(3, '0')}';
      while (!usedIds.add(id)) {
        index++;
        id = 'memory_${index.toString().padLeft(3, '0')}';
      }
      entries.add(
        ProjectMemoryEntry(
          id: id,
          kind: kind,
          content: content.trim(),
          sourceType: ProjectMemorySourceType.planner,
          confidence: ProjectMemoryConfidence.inferred,
          createdAt: now,
          updatedAt: now,
        ),
      );
      index++;
    }

    for (final content in policyAssumptions) {
      add(content, ProjectMemoryKind.assumption);
    }
    return entries;
  }

  ProjectInitialPlanResult _fallbackInitialPlan(String originalGoal) {
    final now = DateTime.now();
    return ProjectInitialPlanResult(
      patch: ProjectPlanPatch.initial(
        ProjectDesiredPlan(
          revision: 1,
          triggers: const [ProjectPlanRevisionTrigger.initialization],
          summary: 'Initial project roadmap.',
          rationale: 'Created from the safe project fallback.',
          criteria: [
            ProjectCriterion(
              id: 'criterion_001',
              statement: 'Complete the stated project goal.',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
        ),
        title: _titleFromPrompt(originalGoal),
        refinedGoal: originalGoal,
        constraints: const ['Stay within the attached workspace.'],
      ),
    );
  }

  /// Coordinates readiness refresh with the aggregate write boundary.
  Future<ProjectAggregate> _persistProject(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) => _persistenceCoordinator.persistProject(
    workspaceRoot,
    project,
    persistenceContext: persistenceContext,
    checkpoint: checkpoint,
  );

  /// Owns user-facing project commands and interrupted-run recovery.
  Future<ProjectCommandResult> _recoverProjectCore({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    ProjectTaskSnapshotSink? onTaskUpdated,
  }) async {
    final loaded = await _aggregateRepository.loadProject(
      workspace.rootPath,
      snapshot.id,
      chatSessionId: snapshot.chatSessionId,
      includeHistory: false,
    );
    final persistenceDiagnostics = loaded.diagnostics;
    if (persistenceDiagnostics.isReadOnly) {
      return ProjectCommandResult.fromSnapshot(
        project: snapshot,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }
    snapshot = loaded.project == null
        ? await _hydrateProjectTasks(workspace, snapshot)
        : snapshot.copyWith(
            tasks: loaded.canonicalTasks.map(ProjectTaskNode.fromTask).toList(),
          );
    final persistenceContext = ProjectPersistenceContext(
      loaded.canonicalTasks,
      health: persistenceDiagnostics,
    );
    if (snapshot.isTerminal) {
      return ProjectCommandResult.fromSnapshot(
        project: snapshot,
        activeTask: await _loadActiveTask(workspace, snapshot),
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    final activeTask = await _loadActiveTask(workspace, snapshot);
    if (!_wasInterrupted(snapshot.status)) {
      return ProjectCommandResult.fromSnapshot(
        project: snapshot,
        activeTask: activeTask,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    final now = DateTime.now();
    if (snapshot.activeTaskId == null) {
      final blocker = snapshot.openQuestions.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: snapshot.openQuestions.first.question,
              createdAt: now,
            );
      final recovered = _transitionProject(
        snapshot: snapshot.copyWith(blocker: blocker, updatedAt: now),
        to: blocker == null
            ? ProjectStatus.active
            : ProjectStatus.waitingForUser,
        trigger: ProjectLifecycleTrigger.recovery,
        reason: blocker?.message ?? 'Recovered project execution state.',
        blocker: blocker,
        now: now,
      );
      final persisted = await _persistProject(
        workspace.rootPath,
        recovered,
        persistenceContext: persistenceContext,
      );
      return ProjectCommandResult.fromSnapshot(
        project: persisted,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    if (activeTask == null) {
      final blocked = _blockProject(
        snapshot.copyWith(activeTaskId: null, updatedAt: now),
        ProjectBlockerType.error,
        'Recovered an interrupted project, but its active task was missing.',
        now,
      );
      final persisted = await _persistProject(
        workspace.rootPath,
        blocked,
        persistenceContext: persistenceContext,
      );
      onTaskUpdated?.call(null);
      return ProjectCommandResult.fromSnapshot(
        project: persisted,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    final recoveredTask = await _taskRecovery.recoverTask(
      workspace: workspace,
      snapshot: activeTask,
      persist: false,
    );
    persistenceContext.stageTask(recoveredTask);
    onTaskUpdated?.call(recoveredTask);
    var recovered = recoveryHandler.reconcile(
      project: snapshot,
      recoveredTask: recoveredTask,
      now: now,
    );
    recovered = await _persistProject(
      workspace.rootPath,
      recovered,
      persistenceContext: persistenceContext,
    );
    return ProjectCommandResult.fromSnapshot(
      project: recovered,
      activeTask: recoveredTask,
      persistenceDiagnostics: persistenceDiagnostics,
    );
  }

  Future<ProjectAggregate> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String incidentId,
  }) async {
    final incident = snapshot.recoveryIncidents
        .where(
          (item) =>
              item.id == incidentId &&
              item.status == ProjectRecoveryIncidentStatus.exhausted,
        )
        .firstOrNull;
    if (incident == null) return snapshot;
    final sourceTask = snapshot.tasks
        .where((task) => task.status == TaskStatus.failed)
        .toList()
        .reversed
        .where((task) => task.recoveryIncidentId == incidentId)
        .firstOrNull;
    if (sourceTask == null) return snapshot;

    final now = DateTime.now();
    final gateResult = TaskGateResult(
      gateId: incident.failedGateId,
      status: TaskGateStatus.failed,
      summary: incident.failureSummary,
      details: {
        'required': true,
        if (incident.command?.trim().isNotEmpty == true)
          'command': incident.command,
        if (incident.workingDirectory?.trim().isNotEmpty == true)
          'workingDirectory': incident.workingDirectory,
      },
      failureDisposition: TaskGateFailureDisposition.repairable,
      evaluatedAt: now,
    );
    final failure = ProjectRecoveryFailure(
      gateResult: gateResult,
      command: incident.command,
      workingDirectory: incident.workingDirectory,
      summary: incident.failureSummary,
    );
    final recoveryTask = _recoveryPolicy.recoveryTaskForIncident(
      incidentId: incident.id,
      sourceTask: sourceTask,
      failure: failure,
      attemptNumber: incident.attemptCount + 1,
      now: now,
    );
    final reactivated = incident.copyWith(
      status: ProjectRecoveryIncidentStatus.active,
      maxAttempts: incident.attemptCount + 1,
      recoveryTaskIds: _appendUnique(incident.recoveryTaskIds, recoveryTask.id),
      updatedAt: now,
      resolvedAt: null,
    );
    var updated = _transitionProject(
      snapshot: snapshot.copyWith(
        blocker: null,
        tasks: [recoveryTask, ...snapshot.tasks],
        recoveryIncidents: _recoveryPolicy.upsertRecoveryIncident(
          snapshot.recoveryIncidents,
          reactivated,
        ),
        decisions: [
          ...snapshot.decisions,
          _decision(
            ProjectDecisionType.retryRecovery,
            'Granted one additional recovery attempt for ${incident.id}.',
            incident.failureSummary,
            task: recoveryTask,
          ),
        ],
        updatedAt: now,
      ),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.recovery,
      reason: 'Recovery retry approved by the user.',
      now: now,
    );
    updated = _memoryService
        .record(
          project: updated,
          kind: ProjectMemoryKind.decision,
          content:
              'User granted one additional recovery attempt for ${incident.id}.',
          sourceType: ProjectMemorySourceType.user,
          sourceId: incident.id,
          confidence: ProjectMemoryConfidence.confirmed,
          protected: true,
          timestamp: now,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String answer,
  }) async {
    final question = snapshot.openQuestions.firstOrNull;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final remainingQuestions = snapshot.openQuestions
        .where((item) => item.id != question.id)
        .toList();
    var updated = _transitionProject(
      snapshot: snapshot.copyWith(
        openQuestions: remainingQuestions,
        blocker: null,
        pendingReplanTriggers: _appendTrigger(
          snapshot.pendingReplanTriggers,
          ProjectPlanRevisionTrigger.scopeChanged,
        ),
        pendingReplanReason:
            'The project scope changed and the backlog must be reconciled.',
        updatedAt: DateTime.now(),
      ),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.answerQuestion,
      reason: 'The user answered an open project question.',
      now: DateTime.now(),
    );
    updated = _memoryService
        .recordUserAnswer(project: updated, question: question, answer: trimmed)
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return snapshot;
    if (snapshot.openQuestions.isNotEmpty) {
      return answerOpenQuestion(
        workspace: workspace,
        snapshot: snapshot,
        answer: trimmed,
      );
    }
    var updated = snapshot.isTerminal
        ? snapshot.copyWith(
            blocker: snapshot.blocker?.type == ProjectBlockerType.question
                ? null
                : snapshot.blocker,
            updatedAt: DateTime.now(),
          )
        : _transitionProject(
            snapshot: snapshot.copyWith(
              blocker: snapshot.blocker?.type == ProjectBlockerType.question
                  ? null
                  : snapshot.blocker,
              updatedAt: DateTime.now(),
            ),
            to: ProjectStatus.active,
            trigger: ProjectLifecycleTrigger.userContext,
            reason: 'The user added project context.',
            now: DateTime.now(),
          );
    updated = _memoryService
        .record(
          project: updated,
          kind: ProjectMemoryKind.requirement,
          content: 'User added project context: $trimmed',
          sourceType: ProjectMemorySourceType.user,
          confidence: ProjectMemoryConfidence.confirmed,
          protected: true,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  /// Records an explicit user scope change and queues one plan revision.
  Future<ProjectAggregate> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String context,
  }) async {
    if (snapshot.isTerminal || snapshot.pendingPlanApproval != null) {
      return snapshot;
    }
    final now = DateTime.now();
    final trimmedReason = context.trim();
    var updated = _transitionProject(
      snapshot: snapshot.copyWith(
        blocker:
            snapshot.blocker?.type == ProjectBlockerType.planApproval ||
                snapshot.blocker?.type == ProjectBlockerType.stagnation
            ? null
            : snapshot.blocker,
        pendingReplanTriggers: _appendTrigger(
          snapshot.pendingReplanTriggers,
          ProjectPlanRevisionTrigger.scopeChanged,
        ),
        pendingReplanReason: trimmedReason.isEmpty
            ? 'The project scope changed and the backlog must be reconciled.'
            : 'User changed project scope: $trimmedReason',
        updatedAt: now,
        diagnostics: snapshot.diagnostics.copyWith(
          consecutiveNoProgressBatches: 0,
          recentNoProgressBatchIds: const [],
        ),
      ),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.userContext,
      reason: 'The user changed project scope.',
      now: now,
    );
    if (trimmedReason.isNotEmpty) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.requirement,
            content: 'User changed project scope: $trimmedReason',
            sourceType: ProjectMemorySourceType.user,
            sourceId: 'scope_change_${now.microsecondsSinceEpoch}',
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            timestamp: now,
          )
          .project;
    }
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> compactMemory({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required List<String> coveredEntryIds,
    required String summary,
  }) async {
    final compacted = _memoryService.compact(
      project: snapshot,
      coveredEntryIds: coveredEntryIds,
      summary: summary,
    );
    return _persistProject(workspace.rootPath, compacted.project);
  }

  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) async {
    final updated = _transitionProject(
      snapshot: snapshot,
      to: ProjectStatus.paused,
      trigger: ProjectLifecycleTrigger.pause,
      reason: 'Project paused by the user.',
      now: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) async {
    final type = snapshot.blocker?.type;
    if (type != ProjectBlockerType.taskEditApproval &&
        type != ProjectBlockerType.taskBlocked &&
        type != ProjectBlockerType.taskFailed) {
      return snapshot;
    }
    final updated = _transitionProject(
      snapshot: snapshot.copyWith(blocker: null, updatedAt: DateTime.now()),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.answerQuestion,
      reason: 'The task blocker was cleared by the user.',
      now: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) async {
    final result = _planningHandler.approvePending(
      project: snapshot,
      workspaceRoot: workspace.rootPath,
    );
    return _persistProject(
      workspace.rootPath,
      result.project.copyWith(
        diagnostics: result.project.diagnostics.copyWith(
          userApprovals: result.project.diagnostics.userApprovals + 1,
        ),
      ),
    );
  }

  Future<ProjectAggregate> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) async {
    final pending = snapshot.pendingPlanApproval;
    if (pending == null) return snapshot;
    final now = DateTime.now();
    final rejectionBase = snapshot.copyWith(
      pendingPlanApproval: null,
      blocker: null,
      updatedAt: now,
    );
    final schedule = _scheduler.schedule(rejectionBase);
    final hasReadyWork = schedule.selectedTask != null;
    final boundary = schedule.project.copyWith(
      blocker: hasReadyWork
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.planApproval,
              message:
                  'Plan revision ${pending.revision} was rejected and no ready work remains. Provide new direction before replanning.',
              createdAt: now,
            ),
      decisions: [
        ...snapshot.decisions,
        _decision(
          ProjectDecisionType.rejectPlanRevision,
          'Rejected plan revision ${pending.revision}: ${pending.summary}',
          pending.reason,
        ),
      ],
      updatedAt: now,
    );
    var updated = _transitionProject(
      snapshot: boundary,
      to: hasReadyWork ? ProjectStatus.active : ProjectStatus.paused,
      trigger: ProjectLifecycleTrigger.approval,
      reason: hasReadyWork
          ? 'Rejected plan approval; existing ready work remains.'
          : boundary.blocker?.message ?? 'Plan approval was rejected.',
      blocker: boundary.blocker,
      now: now,
    );
    updated = _memoryService
        .record(
          project: updated,
          kind: ProjectMemoryKind.decision,
          content: 'User rejected plan revision ${pending.revision}.',
          sourceType: ProjectMemorySourceType.user,
          sourceId: 'revision_${pending.revision}',
          confidence: ProjectMemoryConfidence.confirmed,
          protected: true,
          timestamp: now,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) async {
    final now = DateTime.now();
    final activeTask = _activeProjectTask(snapshot);
    final prepared = snapshot.copyWith(
      activeTaskId: null,
      tasks: [
        for (final task in snapshot.tasks)
          task.id == activeTask?.id
              ? task.copyWith(status: TaskStatus.cancelled, updatedAt: now)
              : task,
      ],
      openQuestions: const [],
      blocker: null,
      updatedAt: now,
    );
    final updated = lifecycleService
        .transition(
          snapshot: prepared,
          to: ProjectStatus.cancelled,
          trigger: ProjectLifecycleTrigger.cancel,
          reason: 'Project cancelled by the user.',
          now: now,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectAggregate> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) {
    return cancelProject(workspace: workspace, snapshot: snapshot);
  }
}
