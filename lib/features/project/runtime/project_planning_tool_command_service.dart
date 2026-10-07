part of 'project_planning_tools.dart';

class ProjectPlanningToolCommandService {
  ProjectPlanningToolCommandService({
    required this.context,
    this.profile = ProjectPlanningToolProfile.maintenance,
    this.includeProjectDetails = false,
  }) {
    _workspaceCommands = ProjectWorkspacePlanningCommandService(context);
    _planCommands = ProjectPlanEditingCommandService(context);
  }

  final ProjectPlanningContext context;
  final ProjectPlanningToolProfile profile;
  final bool includeProjectDetails;
  late final ProjectWorkspacePlanningCommandService _workspaceCommands;
  late final ProjectPlanEditingCommandService _planCommands;

  String get terminalToolId => 'plan_commit';

  String get closedCode => 'draft_closed';

  String get closedMessage => 'This planning draft has already been committed.';

  List<ToolDefinition> get toolDefinitions => [
    if (includeProjectDetails && _allows('plan_set_project_details'))
      _projectDetailsDefinition,
    if (context.workspaceReader != null && _allows('planning_read_file'))
      _planningReadFileDefinition,
    if (_allows('project_view')) _projectViewDefinition,
    if (_allows('plan_add_criteria')) _addCriteriaDefinition,
    if (_allows('plan_add_milestones')) _addMilestonesDefinition,
    if (_visible('plan_add_task')) _addTaskDefinition,
    if (_visible('plan_add_tasks')) _addTasksDefinition,
    if (_allows('plan_update_task')) _updateTaskDefinition,
    if (_allows('plan_set_dependency')) _setDependencyDefinition,
    if (_allows('plan_set_disposition')) _setDispositionDefinition,
    if (_allows('plan_split_task')) _splitTaskDefinition,
    if (_allows('plan_retry_task')) _retryTaskDefinition,
    if (_visible('plan_add_check')) _addCheckDefinition,
    if (_allows('plan_add_note')) _addNoteDefinition,
    if (_allows('plan_set_workspace_orientation'))
      _setWorkspaceOrientationDefinition,
    if (_allows('plan_add_workspace_nodes')) _addWorkspaceNodesDefinition,
    if (_allows('plan_update_workspace_node')) _updateWorkspaceNodeDefinition,
    if (_allows('plan_add_workspace_edges')) _addWorkspaceEdgesDefinition,
    if (_allows('plan_update_workspace_edge')) _updateWorkspaceEdgeDefinition,
    if (_allows('plan_remove_workspace_item')) _removeWorkspaceItemDefinition,
    if (_allows('plan_request_user_decision')) _requestDecisionDefinition,
    if (_visible('plan_preview')) _previewDefinition,
    if (_allows('plan_commit')) _commitDefinition,
  ];

  /// The planning registry has no route to workspace mutation.
  bool get allowsWorkspaceMutation => false;

  Future<PlanningResponse> dispatch(
    String toolId,
    PlanningArguments arguments, {
    String? commandId,
  }) async {
    if (!_allows(toolId) ||
        (toolId == 'plan_set_project_details' && !includeProjectDetails) ||
        (toolId == 'planning_read_file' && context.workspaceReader == null)) {
      throw _argument(
        'tool_unavailable',
        'tool',
        'Project planning tool $toolId is not available in the '
            '${profile.name} planning profile.',
      );
    }
    final result = switch (toolId) {
      'plan_set_project_details' => _setProjectDetails(arguments),
      'planning_read_file' => await _planningReadFile(arguments),
      'project_view' => _view(arguments),
      'plan_add_criteria' => _planCommands.addCriteria(arguments, commandId),
      'plan_add_milestones' => _planCommands.addMilestones(
        arguments,
        commandId,
      ),
      'plan_add_task' => _planCommands.addTask(arguments, commandId),
      'plan_add_tasks' => _planCommands.addTasks(arguments, commandId),
      'plan_update_task' => _planCommands.updateTask(arguments, commandId),
      'plan_set_dependency' => _planCommands.setDependency(
        arguments,
        commandId,
      ),
      'plan_set_disposition' => _planCommands.setDisposition(
        arguments,
        commandId,
      ),
      'plan_split_task' => _planCommands.splitTask(arguments, commandId),
      'plan_retry_task' => _planCommands.retryTask(arguments, commandId),
      'plan_add_check' => _planCommands.addCheck(arguments, commandId),
      'plan_add_note' => _planCommands.addNote(arguments, commandId),
      'plan_set_workspace_orientation' =>
        _workspaceCommands.setWorkspaceOrientation(arguments, commandId),
      'plan_add_workspace_nodes' => _workspaceCommands.addWorkspaceNodes(
        arguments,
        commandId,
      ),
      'plan_update_workspace_node' => _workspaceCommands.updateWorkspaceNode(
        arguments,
        commandId,
      ),
      'plan_add_workspace_edges' => _workspaceCommands.addWorkspaceEdges(
        arguments,
        commandId,
      ),
      'plan_update_workspace_edge' => _workspaceCommands.updateWorkspaceEdge(
        arguments,
        commandId,
      ),
      'plan_remove_workspace_item' => _workspaceCommands.removeWorkspaceItem(
        arguments,
        commandId,
      ),
      'plan_request_user_decision' => _planCommands.requestDecision(
        arguments,
        commandId,
      ),
      'plan_preview' => _preview(arguments),
      'plan_commit' => await _commit(arguments),
      _ => throw _argument(
        'unknown_tool',
        'tool',
        'Unknown project planning tool $toolId.',
      ),
    };
    final response = <String, dynamic>{'ok': true, ...result};
    if (_mutationToolIds.contains(toolId)) {
      response['state'] = _draftState();
    }
    return PlanningResponse.fromWire(response);
  }

  static const _mutationToolIds = {
    'plan_set_project_details',
    'plan_add_criteria',
    'plan_add_milestones',
    'plan_add_task',
    'plan_add_tasks',
    'plan_update_task',
    'plan_set_dependency',
    'plan_set_disposition',
    'plan_split_task',
    'plan_retry_task',
    'plan_add_check',
    'plan_add_note',
    'plan_set_workspace_orientation',
    'plan_add_workspace_nodes',
    'plan_update_workspace_node',
    'plan_add_workspace_edges',
    'plan_update_workspace_edge',
    'plan_remove_workspace_item',
    'plan_request_user_decision',
  };

  bool _allows(String toolId) {
    if (includeProjectDetails && toolId == 'plan_set_project_details') {
      return true;
    }
    return switch (profile) {
      ProjectPlanningToolProfile.bootstrap => const {
        'project_view',
        'planning_read_file',
        'plan_add_criteria',
        'plan_add_milestones',
        'plan_add_task',
        'plan_add_tasks',
        'plan_add_check',
        'plan_add_note',
        'plan_request_user_decision',
        'plan_preview',
        'plan_commit',
      }.contains(toolId),
      ProjectPlanningToolProfile.maintenance => const {
        'project_view',
        'planning_read_file',
        'plan_add_criteria',
        'plan_add_milestones',
        'plan_add_task',
        'plan_add_tasks',
        'plan_update_task',
        'plan_set_dependency',
        'plan_set_disposition',
        'plan_split_task',
        'plan_retry_task',
        'plan_add_check',
        'plan_add_note',
        'plan_set_workspace_orientation',
        'plan_add_workspace_nodes',
        'plan_update_workspace_node',
        'plan_add_workspace_edges',
        'plan_update_workspace_edge',
        'plan_remove_workspace_item',
        'plan_request_user_decision',
        'plan_preview',
        'plan_commit',
      }.contains(toolId),
      ProjectPlanningToolProfile.split => const {
        'project_view',
        'plan_split_task',
        'plan_preview',
        'plan_commit',
      }.contains(toolId),
    };
  }

  bool _visible(String toolId) {
    if (profile == ProjectPlanningToolProfile.bootstrap &&
        const {
          'plan_add_tasks',
          'plan_add_check',
          'plan_preview',
        }.contains(toolId)) {
      return false;
    }
    return _allows(toolId);
  }

  bool _validationRepairable(List<ProjectPlanValidationIssue> issues) {
    // Bootstrap can repair only omissions that its visible additive tools can
    // still supply. Existing task ownership, evidence, dependency, and
    // structural errors require mutation operations outside that profile.
    const bootstrapRepairable = {
      'missing_criteria',
      'missing_active_milestone',
      'missing_executable_tasks',
      'new_task_minimum_not_met',
    };
    if (profile == ProjectPlanningToolProfile.bootstrap) {
      return issues.every((issue) => bootstrapRepairable.contains(issue.code));
    }
    if (profile == ProjectPlanningToolProfile.split) {
      return false;
    }
    const nonRepairableByProfile = {
      ProjectPlanningToolProfile.maintenance: {'path_outside_workspace'},
    };
    final nonRepairable = nonRepairableByProfile[profile]!;
    return issues.every((issue) => !nonRepairable.contains(issue.code));
  }

  List<String> _suggestedActions(List<ProjectPlanValidationIssue> issues) {
    if (!_validationRepairable(issues)) return const [];
    final actions = <String>{};
    for (final issue in issues) {
      final action = switch (issue.code) {
        'missing_criteria' => 'plan_add_criteria',
        'missing_executable_tasks' ||
        'new_task_minimum_not_met' => 'plan_add_task',
        'missing_active_milestone' => 'plan_add_milestones',
        'impossible_deterministic_verification' ||
        'missing_command_passes_gate' =>
          profile == ProjectPlanningToolProfile.bootstrap
              ? 'plan_add_task'
              : 'plan_add_check',
        _ => null,
      };
      if (action != null && _visible(action)) actions.add(action);
    }
    return actions.toList()..sort();
  }

  Map<String, dynamic> domainError(Object error) {
    if (error is ProjectPlanBuilderException) {
      return _error(
        code: error.code,
        path: _wirePath(error.path),
        message: error.message,
        extra: error.details.isEmpty ? const {} : {'details': error.details},
      );
    }
    if (error is ProjectViewException) {
      return _error(code: error.code, path: error.path, message: error.message);
    }
    return _error(
      code: 'planning_tool_failed',
      path: 'tool',
      message: 'The planning command could not be applied: $error',
    );
  }

  Map<String, dynamic> _view(PlanningArguments arguments) {
    _keys(arguments, const {
      'task_ref',
      'criterion_ref',
      'memory_query',
      'workspace_query',
      'max_items',
    });
    final preview = context.builder.preview(
      workspaceRoot: context.workspaceRoot,
    );
    final taskRef = _optionalString(arguments['task_ref'], 'task_ref');
    final criterionRef = _optionalString(
      arguments['criterion_ref'],
      'criterion_ref',
    );
    final memoryQuery = _optionalString(
      arguments['memory_query'],
      'memory_query',
    );
    final workspaceQuery = _optionalString(
      arguments['workspace_query'],
      'workspace_query',
    );
    final view = context.viewService.query(
      _projectForDetail(preview),
      taskRef: _draftTaskReference(
        taskRef,
        preview.proposal.tasks.map((item) => item.id),
      ),
      criterionRef: _draftCriterionReference(
        criterionRef,
        preview.proposal.criteria.map((item) => item.id),
      ),
      memoryQuery: memoryQuery,
      workspaceQuery: workspaceQuery,
      maxItems: _optionalInt(arguments['max_items'], 'max_items'),
    );
    return {...view, 'draft': _draftSummary(preview)};
  }

  Future<Map<String, dynamic>> _planningReadFile(
    PlanningArguments arguments,
  ) async {
    _keys(arguments, const {'path', 'start_line', 'end_line'});
    final startLine = _optionalInt(arguments['start_line'], 'start_line') ?? 1;
    final endLine = _optionalInt(arguments['end_line'], 'end_line');
    return context.workspaceReader!.read(
      requestedPath: _requiredString(arguments['path'], 'path'),
      startLine: startLine,
      endLine: endLine,
    );
  }

  ProjectAggregate _projectForDetail(ProjectPlanBuilderPreview preview) {
    final proposedTaskIds = {
      for (final task in preview.proposal.tasks) task.id,
    };
    final tasks = [
      for (final task in context.project.tasks)
        if (!proposedTaskIds.contains(task.id))
          context.builder.splitTaskIds.contains(task.id)
              ? task.copyWith(
                  status: TaskStatus.split,
                  rejectionReason: 'Split in the current planning draft.',
                )
              : task,
      ...preview.proposal.tasks,
    ];
    return context.project.copyWith(
      title: context.draftTitle,
      refinedGoal: context.draftRefinedGoal,
      constraints: context.draftConstraints,
      criteria: preview.proposal.criteria,
      milestones: preview.proposal.milestones,
      tasks: tasks,
      memory: [...context.project.memory, ...preview.proposal.memoryAdditions],
      workspaceGraph: preview.proposal.workspaceGraph,
      openQuestions: preview.proposal.openQuestions,
    );
  }

  String? _draftTaskReference(String? reference, Iterable<String> ids) {
    if (reference == null || reference.isEmpty) return reference;
    try {
      final id = context.builder.taskIdFor(reference);
      if (ids.contains(id)) return id;
    } on ProjectPlanBuilderException {
      // Preserve the original reference for the view's error contract.
    }
    return reference;
  }

  Map<String, dynamic> _setProjectDetails(PlanningArguments arguments) {
    _ensureOpen();
    _keys(arguments, const {'title', 'refined_goal', 'constraints'});
    final title = _requiredString(arguments['title'], 'title');
    final refinedGoal = _requiredString(
      arguments['refined_goal'],
      'refined_goal',
    );
    final constraints = arguments.containsKey('constraints')
        ? _stringList(arguments['constraints'], 'constraints')
        : null;
    context.setProjectDetails(
      title: title,
      refinedGoal: refinedGoal,
      constraints: constraints,
    );
    return {
      'title': context.draftTitle,
      'refined_goal': context.draftRefinedGoal,
      'constraints': context.draftConstraints,
    };
  }

  String? _draftCriterionReference(String? reference, Iterable<String> ids) {
    if (reference == null || reference.isEmpty) return reference;
    try {
      final id = context.builder.criterionIdFor(reference);
      if (ids.contains(id)) return id;
    } on ProjectPlanBuilderException {
      // Preserve the original reference for the view's error contract.
    }
    return reference;
  }

  Map<String, dynamic> _preview(PlanningArguments arguments) {
    _ensureOpen();
    _keys(arguments, const {'summary', 'rationale'});
    final summary = _optionalString(arguments['summary'], 'summary');
    final rationale = _optionalString(arguments['rationale'], 'rationale');
    _validateOptionalText(summary, 'summary');
    _validateOptionalText(rationale, 'rationale');
    if (summary != null) context.builder.setSummary(summary);
    if (rationale != null) context.builder.setRationale(rationale);
    return {
      'preview': _draftSummary(
        context.builder.preview(workspaceRoot: context.workspaceRoot),
      ),
    };
  }

  Future<Map<String, dynamic>> _commit(PlanningArguments arguments) async {
    _ensureOpen();
    _keys(arguments, const {'summary', 'rationale'});
    final summary = _optionalString(arguments['summary'], 'summary');
    final rationale = _optionalString(arguments['rationale'], 'rationale');
    _validateOptionalText(summary, 'summary');
    _validateOptionalText(rationale, 'rationale');
    if (summary != null) context.builder.setSummary(summary);
    if (rationale != null) context.builder.setRationale(rationale);
    final preview = context.builder.preview(
      workspaceRoot: context.workspaceRoot,
    );
    final validation = preview.validation;
    final response = <String, dynamic>{
      'revision': preview.proposal.revision,
      'changed': true,
      'awaiting_approval': false,
      'control': context.viewService.controlState(context.project),
      'validation': [for (final issue in validation.issues) issue.toMap()],
      'diff': _draftDiff(preview.proposal),
    };
    if (!validation.valid) {
      final issue =
          validation.errors.firstOrNull ?? validation.issues.firstOrNull;
      if (issue != null) {
        return _error(
          code: issue.code,
          path: issue.path,
          message: issue.message,
          extra: {
            ...response,
            'details': {
              'repairable': _validationRepairable(validation.errors),
              'blockers': [for (final item in validation.errors) item.toMap()],
              'suggested_actions': _suggestedActions(validation.errors),
            },
          },
        );
      }
      return _error(
        code: 'invalid_plan',
        path: 'plan',
        message: 'The plan did not pass validation.',
        extra: {
          ...response,
          'details': {
            'repairable': false,
            'blockers': const [],
            'suggested_actions': const [],
          },
        },
      );
    }
    if (context.deferRevision) {
      // Initial planning only produces a validated draft. Applying the
      // revision service here would create a synthetic first commit and make
      // project creation reconcile the same plan a second time.
      context.committedProposal = preview.proposal;
      context.committedPatch = ProjectPlanPatch.initial(
        preview.proposal,
        title: context.draftTitle,
        refinedGoal: context.draftRefinedGoal,
        constraints: context.draftConstraints,
      );
      context.committedProject = context.project.copyWith(
        title: context.draftTitle,
        refinedGoal: context.draftRefinedGoal,
        constraints: context.draftConstraints,
        workspaceGraph: preview.proposal.workspaceGraph,
      );
    } else {
      final committed = await context.builder.commit(
        workspaceRoot: context.workspaceRoot,
        approvalPolicy: context.approvalPolicy,
      );
      context.committedProposal = committed.proposal;
      context.committedPatch = committed.patch;
      context.committedProject = committed.project.copyWith(
        title: context.draftTitle,
        refinedGoal: context.draftRefinedGoal,
        constraints: context.draftConstraints,
        workspaceGraph: committed.project.workspaceGraph,
      );
      response['changed'] = committed.result.changed;
      response['awaiting_approval'] = committed.result.awaitingApproval;
      response['control'] = context.viewService.controlState(committed.project);
    }
    if (context.deferRevision) {
      response['control'] = context.viewService.controlState(
        context.committedProject!,
      );
    }
    context.closed = true;
    return response;
  }

  Map<String, dynamic> _draftState() {
    final preview = context.builder.preview(
      workspaceRoot: context.workspaceRoot,
    );
    final diff = _draftDiff(preview.proposal);
    final changedCriterionIds = {
      for (final id in (diff['added_criteria'] as List).cast<String>()) id,
    };
    final changedMilestoneIds = {
      for (final id in (diff['added_milestones'] as List).cast<String>()) id,
    };
    final changedTaskIds = {
      for (final id in (diff['added_tasks'] as List).cast<String>()) id,
      for (final id in (diff['updated_tasks'] as List).cast<String>()) id,
      for (final id in (diff['deferred_tasks'] as List).cast<String>()) id,
      for (final id in (diff['obsolete_tasks'] as List).cast<String>()) id,
      for (final id in (diff['split_tasks'] as List).cast<String>()) id,
    };
    return {
      'revision': preview.proposal.revision,
      'valid': preview.validation.valid,
      'validation': [
        for (final issue in preview.validation.issues) issue.toMap(),
      ],
      'diff': diff,
      'changed_resources': {
        'criteria': [
          for (final criterion in preview.proposal.criteria)
            if (changedCriterionIds.contains(criterion.id))
              _criterionState(criterion),
        ],
        'milestones': [
          for (final milestone in preview.proposal.milestones)
            if (changedMilestoneIds.contains(milestone.id))
              _milestoneState(milestone),
        ],
        'tasks': [
          for (final task in preview.proposal.tasks)
            if (changedTaskIds.contains(task.id)) _taskState(task),
        ],
      },
      'control': context.viewService.controlState(_projectForDetail(preview)),
    };
  }

  Map<String, dynamic> _criterionState(ProjectCriterion criterion) => {
    'id': criterion.id,
    'statement': criterion.statement,
    'required': criterion.required,
    'verification_mode': criterion.verificationMode.name,
  };

  Map<String, dynamic> _milestoneState(ProjectMilestone milestone) => {
    'id': milestone.id,
    'title': milestone.title,
    'objective': milestone.objective,
    'criterion_refs': milestone.criterionIds,
    'exit_conditions': milestone.exitConditions,
    'order': milestone.order,
    'status': milestone.status.name,
  };

  Map<String, dynamic> _taskState(ProjectTaskNode task) => {
    'id': task.id,
    'title': task.title,
    'objective': task.objective,
    'status': task.status.wire,
    'criterion_refs': task.criterionIds,
    'dependency_refs': task.dependsOnTaskIds,
    'milestone_ref': task.milestoneId,
    'priority': task.priority.name,
    'risk': task.risk.name,
    'risk_reduction': task.riskReduction.name,
    'effort': task.effort.name,
    'selection_rationale': task.selectionRationale,
    'constraints': task.constraints,
    'read_paths': task.readPaths,
    'write_paths': task.writePaths,
    'done_criteria': task.doneCriteria,
    'out_of_scope': task.outOfScope,
    'context': task.context,
    'expected_artifacts': [
      for (final artifact in task.expectedArtifacts)
        {
          'path': artifact.path,
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
    'checks': [
      for (final gate in task.gates)
        {
          'kind': gate.id,
          'required': gate.required,
          'scope': gate.scope,
          'command': gate.params['command'],
          'working_directory':
              gate.params['working_directory'] ??
              gate.params['workingDirectory'],
          'description': gate.description,
        },
    ],
    'evidence_intents': [
      for (final expectation in task.expectedEvidence)
        {
          'kind': expectation.type.name,
          'criterion_refs': expectation.criterionIds,
          'description': expectation.description,
          'required': expectation.required,
          'source_ref': expectation.sourceRef,
        },
    ],
  };

  static ProjectTaskSpec _taskSpec(
    Map<String, dynamic> value,
    String path, {
    bool requireObjective = false,
  }) {
    _rejectPersistentFields(value, path);
    _keys(value, const {
      'ref',
      'title',
      'objective',
      'criterion_refs',
      'dependency_refs',
      'milestone_ref',
      'priority',
      'risk',
      'risk_reduction',
      'effort',
      'selection_rationale',
      'constraints',
      'read_paths',
      'write_paths',
      'done_criteria',
      'out_of_scope',
      'context',
      'expected_artifacts',
    });
    final ref = _optionalString(value['ref'], '$path.ref') ?? '';
    final title = _optionalString(value['title'], '$path.title') ?? '';
    final objective =
        _optionalString(value['objective'], '$path.objective') ?? '';
    final criterionRefs = _stringList(
      value['criterion_refs'],
      '$path.criterion_refs',
    );
    final doneCriteria = _stringList(
      value['done_criteria'],
      '$path.done_criteria',
    );
    final outOfScope = _stringList(value['out_of_scope'], '$path.out_of_scope');
    final missingFields = <String>[];
    if (requireObjective
        ? objective.isEmpty
        : title.isEmpty && objective.isEmpty) {
      missingFields.add(requireObjective ? 'objective' : 'objective_or_title');
    }
    if (criterionRefs.where((item) => item.isNotEmpty).isEmpty) {
      missingFields.add('criterion_refs');
    }
    if (doneCriteria.where((item) => item.isNotEmpty).isEmpty) {
      missingFields.add('done_criteria');
    }
    if (outOfScope.where((item) => item.isNotEmpty).isEmpty) {
      missingFields.add('out_of_scope');
    }
    if (missingFields.isNotEmpty) {
      throw _argument(
        'invalid_task_spec',
        path,
        'Submit the complete task object in one call. Arguments from previous '
            'calls are not merged.',
        details: {
          'missing_fields': missingFields,
          'instruction':
              'Resubmit the complete task object; do not send only the missing fields.',
        },
      );
    }
    return ProjectTaskSpec(
      ref: ref,
      title: title,
      objective: objective,
      criterionRefs: criterionRefs,
      dependencyRefs: _stringList(
        value['dependency_refs'],
        '$path.dependency_refs',
      ),
      milestoneRef: _optionalString(
        value['milestone_ref'],
        '$path.milestone_ref',
      ),
      priority:
          _enumValue(
            TaskPriority.values,
            value['priority'],
            '$path.priority',
          ) ??
          TaskPriority.normal,
      risk:
          _enumValue(TaskRisk.values, value['risk'], '$path.risk') ??
          TaskRisk.unknown,
      riskReduction:
          _enumValue(
            ProjectRiskReduction.values,
            value['risk_reduction'],
            '$path.risk_reduction',
          ) ??
          ProjectRiskReduction.none,
      effort:
          _enumValue(TaskEffort.values, value['effort'], '$path.effort') ??
          TaskEffort.small,
      selectionRationale:
          _optionalString(
            value['selection_rationale'],
            '$path.selection_rationale',
          ) ??
          '',
      constraints: _stringList(value['constraints'], '$path.constraints'),
      readPaths: _stringList(value['read_paths'], '$path.read_paths'),
      writePaths: _stringList(value['write_paths'], '$path.write_paths'),
      doneCriteria: doneCriteria,
      outOfScope: outOfScope,
      context: _stringList(value['context'], '$path.context'),
      expectedArtifacts: _artifacts(
        value['expected_artifacts'],
        '$path.expected_artifacts',
      ),
    );
  }

  static List<ProjectTaskCheckSpec> _checkSpecs(Object? value, String path) {
    if (value == null) return const [];
    final maps = _maps(value, path);
    return [
      for (var index = 0; index < maps.length; index++)
        () {
          final item = maps[index];
          _rejectPersistentFields(item, '$path[$index]');
          _keys(item, const {
            'command',
            'working_directory',
            'criterion_refs',
            'required',
            'description',
          });
          return ProjectTaskCheckSpec(
            command: _requiredString(item['command'], '$path[$index].command'),
            workingDirectory:
                _optionalString(
                  item['working_directory'],
                  '$path[$index].working_directory',
                ) ??
                '.',
            criterionRefs: _stringList(
              item['criterion_refs'],
              '$path[$index].criterion_refs',
            ),
            required:
                _optionalBool(item['required'], '$path[$index].required') ??
                true,
            description: _optionalString(
              item['description'],
              '$path[$index].description',
            ),
          );
        }(),
    ];
  }

  static void _rejectPersistentFields(Map<String, dynamic> value, String path) {
    const fields = {
      'id',
      'status',
      'created_at',
      'createdAt',
      'updated_at',
      'updatedAt',
      'runs',
      'failure',
      'gates',
      'expected_evidence',
      'expectedEvidence',
      'completed_at',
      'completedAt',
      'task_id',
      'taskId',
      'revision',
      'fingerprint',
      'revisionIntroduced',
      'revisionUpdated',
      'evidence',
      'steps',
      'currentStepId',
    };
    for (final field in fields) {
      if (value.containsKey(field)) {
        throw _argument(
          'invalid_argument',
          '$path.$field',
          'Creation tools generate persistent fields; the field is not accepted.',
        );
      }
    }
  }

  static List<TaskArtifact> _artifacts(Object? value, String path) {
    if (value == null) return const [];
    final maps = _maps(value, path);
    final artifacts = <TaskArtifact>[];
    for (var index = 0; index < maps.length; index++) {
      final item = maps[index];
      _rejectPersistentFields(item, '$path[$index]');
      _keys(item, const {'path', 'description', 'kind'});
      artifacts.add(
        TaskArtifact(
          path: _requiredString(item['path'], '$path[$index].path'),
          description: _optionalString(
            item['description'],
            '$path[$index].description',
          ),
          kind: _optionalString(item['kind'], '$path[$index].kind') ?? 'file',
        ),
      );
    }
    return artifacts;
  }

  static List<TaskArtifact>? _optionalArtifacts(Object? value, String path) {
    if (value == null) return null;
    return _artifacts(value, path);
  }

  Map<String, dynamic> _draftSummary(ProjectPlanBuilderPreview preview) => {
    'base_revision': context.baseRevision,
    'summary': context.builder.summary,
    'rationale': context.builder.rationale,
    'valid': preview.validation.valid,
    'validation': [
      for (final issue in preview.validation.issues) issue.toMap(),
    ],
    'diff': _draftDiff(preview.proposal),
  };

  Map<String, dynamic> _draftDiff(ProjectDesiredPlan proposal) {
    final existingCriteria = {
      for (final item in context.project.criteria) item.id,
    };
    final existingMilestones = {
      for (final item in context.project.milestones) item.id,
    };
    final existingTasks = {for (final item in context.project.tasks) item.id};
    return {
      'project_details_changed': context.projectDetailsChanged,
      'added_criteria': [
        for (final item in proposal.criteria)
          if (!existingCriteria.contains(item.id)) item.id,
      ],
      'added_milestones': [
        for (final item in proposal.milestones)
          if (!existingMilestones.contains(item.id)) item.id,
      ],
      'added_tasks': [
        for (final item in proposal.tasks)
          if (!existingTasks.contains(item.id)) item.id,
      ],
      'updated_tasks': [
        for (final item in proposal.tasks)
          if (existingTasks.contains(item.id) &&
              _taskChanged(context.project.taskById(item.id)!, item))
            item.id,
      ],
      'deferred_tasks': proposal.deferredTaskIds,
      'obsolete_tasks': proposal.obsoleteTaskIds,
      'split_tasks': context.builder.splitTaskIds,
      'added_notes': [for (final item in proposal.memoryAdditions) item.id],
      'workspace': {
        'orientation': proposal.workspaceGraph.orientation,
        'node_count': proposal.workspaceGraph.nodes.length,
        'edge_count': proposal.workspaceGraph.edges.length,
      },
      'pending_questions': [for (final item in proposal.openQuestions) item.id],
    };
  }

  void _ensureOpen() {
    if (context.closed) {
      throw _argument(
        'draft_closed',
        'tool',
        'This planning draft has already been committed.',
      );
    }
  }

  static bool _taskChanged(ProjectTaskNode existing, ProjectTaskNode desired) =>
      _taskSignature(existing) != _taskSignature(desired);

  static String _taskSignature(ProjectTaskNode task) => jsonEncode({
    'title': task.title,
    'objective': task.objective,
    'constraints': task.constraints,
    'criterion_refs': task.criterionIds,
    'milestone_ref': task.milestoneId,
    'dependency_refs': task.dependsOnTaskIds,
    'priority': task.priority.name,
    'risk': task.risk.name,
    'risk_reduction': task.riskReduction.name,
    'effort': task.effort.name,
    'selection_rationale': task.selectionRationale,
    'read_paths': task.readPaths,
    'write_paths': task.writePaths,
    'done_criteria': task.doneCriteria,
    'out_of_scope': task.outOfScope,
    'context': task.context,
    'status': task.status.name,
    'gates': [
      for (final gate in task.gates)
        {
          'id': gate.id,
          'required': gate.required,
          'scope': gate.scope,
          'params': gate.params,
          'description': gate.description,
        },
    ],
    'expected_evidence': [
      for (final expectation in task.expectedEvidence)
        {
          'type': expectation.type.name,
          'criterion_refs': expectation.criterionIds,
          'description': expectation.description,
          'required': expectation.required,
          'source_ref': expectation.sourceRef,
          'details': expectation.details,
        },
    ],
    'expected_artifacts': [
      for (final artifact in task.expectedArtifacts)
        {
          'path': artifact.path,
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
  });

  static void _keys(Object value, Set<String> allowed) {
    final keys = value is PlanningArguments
        ? value.keys
        : (value as Map<String, dynamic>).keys;
    for (final key in keys) {
      if (!allowed.contains(key)) {
        throw _argument(
          'invalid_argument',
          key,
          'Argument $key is not accepted by this planning tool.',
        );
      }
    }
  }

  static List<Map<String, dynamic>> _maps(
    Object? value,
    String path, {
    bool required = false,
  }) {
    if (value == null) {
      if (required) {
        throw _argument(
          'missing_argument',
          path,
          'A non-empty list is required.',
        );
      }
      return const [];
    }
    if (value is! List || value.isEmpty && required) {
      throw _argument('invalid_argument', path, 'Expected a non-empty list.');
    }
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! Map) {
        throw _argument(
          'invalid_argument',
          '$path[$index]',
          'Expected an object.',
        );
      }
      final map = <String, dynamic>{};
      for (final entry in item.entries) {
        if (entry.key is! String) {
          throw _argument(
            'invalid_argument',
            '$path[$index]',
            'Object field names must be strings.',
          );
        }
        map[entry.key as String] = entry.value;
      }
      result.add(map);
    }
    return result;
  }

  static String _requiredString(Object? value, String path) {
    if (value is! String || value.trim().isEmpty) {
      throw _argument(
        'invalid_argument',
        path,
        'A non-empty string is required.',
      );
    }
    return value.trim();
  }

  static String? _optionalString(Object? value, String path) {
    if (value == null) return null;
    if (value is! String) {
      throw _argument('invalid_argument', path, 'Expected a string.');
    }
    return value.trim();
  }

  static List<String> _stringList(Object? value, String path) {
    if (value == null) return const [];
    if (value is! List) {
      throw _argument('invalid_argument', path, 'Expected a list of strings.');
    }
    final result = <String>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! String) {
        throw _argument(
          'invalid_argument',
          '$path[$index]',
          'Expected a string.',
        );
      }
      result.add(item.trim());
    }
    return result;
  }

  static List<String>? _optionalStringList(Object? value, String path) {
    if (value == null) return null;
    return _stringList(value, path);
  }

  static void _validateOptionalText(String? value, String path) {
    if (value != null && value.trim().isEmpty) {
      throw _argument('invalid_argument', path, 'Expected a non-empty string.');
    }
  }

  static bool? _optionalBool(Object? value, String path) {
    if (value == null) return null;
    if (value is! bool) {
      throw _argument('invalid_argument', path, 'Expected a boolean.');
    }
    return value;
  }

  static int? _optionalInt(Object? value, String path) {
    if (value == null) return null;
    if (value is! int) {
      throw _argument('invalid_argument', path, 'Expected an integer.');
    }
    return value;
  }

  static T? _enumValue<T extends Enum>(
    List<T> values,
    Object? value,
    String path,
  ) {
    if (value == null) return null;
    if (value is! String) {
      throw _argument('invalid_argument', path, 'Expected an enum string.');
    }
    final normalised = value.trim().toLowerCase().replaceAll('-', '_');
    for (final candidate in values) {
      if (candidate.name == normalised ||
          candidate.name.toLowerCase() == normalised ||
          candidate.name.toLowerCase() == normalised.replaceAll('_', '')) {
        return candidate;
      }
    }
    throw _argument(
      'invalid_argument',
      path,
      'Unsupported value $value. Expected one of ${values.map((item) => item.name).join(', ')}.',
    );
  }

  static String? _partCommandId(String? commandId, int index) =>
      commandId == null ? null : '$commandId:$index';

  static _PlanningArgumentException _argument(
    String code,
    String path,
    String message, {
    Map<String, dynamic> details = const {},
  }) => _PlanningArgumentException(code, path, message, details: details);

  static String _wirePath(String path) => path
      .replaceAll('criterionRefs', 'criterion_refs')
      .replaceAll('dependencyRefs', 'dependency_refs')
      .replaceAll('milestoneRef', 'milestone_ref')
      .replaceAll('doneCriteria', 'done_criteria')
      .replaceAll('outOfScope', 'out_of_scope')
      .replaceAll('readPaths', 'read_paths')
      .replaceAll('writePaths', 'write_paths')
      .replaceAll('expectedArtifacts', 'expected_artifacts');

  static Map<String, dynamic> _error({
    required String code,
    required String path,
    required String message,
    Map<String, dynamic> extra = const {},
  }) => {'ok': false, 'code': code, 'path': path, 'message': message, ...extra};
}
