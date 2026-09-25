part of 'project_workflow_service.dart';

/// Owns project creation and initial-plan validation policy.
extension ProjectPlanningPhase on ProjectWorkflowService {
  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ChatClient? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final planning = await _planningCoordinator.initialise(
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
        ? const <Task>[]
        : _normaliseInitialBacklog(proposal.taskDocuments, initialCriterionIds);
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
      final committed = await _planRevisionService.prepareAndApplyPatch(
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

  List<Map<String, String>> _validateInitialPlan({
    required ProjectInitialPlanResult initialPlan,
    required WorkspaceDiscoveryProfile workspaceProfile,
  }) {
    final plan = initialPlan.patch.plan;
    final issues = <Map<String, String>>[];
    void add(String code, String message, {String? path}) {
      final issue = <String, String>{'code': code, 'message': message};
      if (path != null) issue['path'] = path;
      issues.add(issue);
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

  String _initialPlanningBlockerMessage(List<Map<String, String>> issues) {
    final details = issues
        .map((issue) {
          final path = issue['path'];
          return '${issue['code']}${path == null ? '' : ' ($path)'}: ${issue['message']}';
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
}
