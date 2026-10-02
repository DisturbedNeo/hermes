part of 'project_execution_state_machine.dart';

/// Owns project creation and initial-plan application at the project
/// application boundary.
class ProjectPlanningUseCase {
  ProjectPlanningUseCase(ProjectPlanningCapabilities context)
    : _context = context;

  final ProjectPlanningCapabilities _context;

  Future<ProjectAggregate> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelConversationPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final planning = await _context.planningHandler.initialise(
      workspace: workspace,
      userPrompt: userPrompt,
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      fallback: () => _context.fallbackInitialPlan(userPrompt),
      validate: _context.validateInitialPlan,
      blocksContextIssue: _context.blocksInitialPlanningForContextIssue,
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
    final filteredQuestions = _context.filterProjectQuestions(
      proposal.openQuestions,
      autonomy: questionAutonomy,
    );
    final initialCriteria = proposal.criteria;
    final initialCriterionIds = initialCriteria.map((item) => item.id).toList();
    final initialBacklog = planningBlocked
        ? const <ProjectTaskNode>[]
        : _context.normaliseInitialBacklog(proposal.tasks, initialCriterionIds);
    final initialMilestones = _context.initialMilestones(
      milestones: proposal.milestones,
      refinedGoal: initialPlan.patch.refinedGoal ?? userPrompt,
      criteria: initialCriteria,
      now: now,
    );
    final initialMemory = _context.initialMemory(
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
        ? _context.titleFromPrompt(userPrompt)
        : initialPlan.patch.title!.trim();
    final refinedGoal = (initialPlan.patch.refinedGoal ?? '').trim().isEmpty
        ? userPrompt
        : initialPlan.patch.refinedGoal!.trim();
    final constraints = initialPlan.patch.constraints?.isEmpty ?? true
        ? const ['Stay within the attached workspace.']
        : initialPlan.patch.constraints!;

    var project = ProjectAggregate(
      id: _context.newProjectId(userPrompt),
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
      maxIterations: _context.normaliseOptionalLimit(
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
              message: _context.initialPlanningBlockerMessage(planningIssues),
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
      final committed = await _context.planningHandler.prepareAndApplyPatch(
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
      project = _context.transitionProject(
        snapshot: project,
        to: ProjectStatus.blocked,
        trigger: ProjectLifecycleTrigger.initialization,
        reason: project.blocker?.message ?? 'Initial planning was blocked.',
        blocker: project.blocker,
        now: now,
      );
    }
    if (client == null || initialPlan.planningError != null) {
      project = _context.controlStateService.withOutcome(
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
    return _context.persistProject(
      workspace.rootPath,
      project,
      checkpoint: ProjectPersistenceCheckpoint.initialization,
    );
  }
}
