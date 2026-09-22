import 'dart:convert';

import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/project_system/project_plan_builder.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';
import 'package:hermes/core/services/project_system/project_planning_workspace_reader.dart';
import 'package:hermes/core/services/project_system/project_view_service.dart';

/// The state and policy available to a single project-planning invocation.
///
/// Planning commands can only edit the in-memory [ProjectPlanBuilder] draft.
/// Initial planning may additionally receive a separately budgeted,
/// read-only workspace context reader.
class ProjectPlanningContext {
  ProjectPlanningContext({
    required this.project,
    required this.workspaceRoot,
    DateTime? now,
    Iterable<ProjectPlanRevisionTrigger> triggers = const [],
    String summary = 'Apply the incremental plan update.',
    String rationale = 'Keep the project plan bounded and actionable.',
    bool requiresApproval = false,
    String approvalReason = '',
    this.approvalPolicy = ProjectPlanApprovalPolicy.highRiskOnly,
    ProjectPlanRevisionService revisionService =
        const ProjectPlanRevisionService(),
    this.viewService = const ProjectViewService(),
    this.workspaceReader,
  }) : builder = ProjectPlanBuilder(
         project: project,
         now: now,
         triggers: triggers,
         summary: summary,
         rationale: rationale,
         requiresApproval: requiresApproval,
         approvalReason: approvalReason,
         revisionService: revisionService,
       ),
       baseRevision = project.nextRevision - 1,
       _draftTitle = project.title,
       _draftRefinedGoal = project.refinedGoal,
       _draftConstraints = [...project.constraints];

  final ProjectState project;
  final String workspaceRoot;
  final int baseRevision;
  final ProjectPlanApprovalPolicy approvalPolicy;
  final ProjectPlanBuilder builder;
  final ProjectViewService viewService;
  final ProjectPlanningWorkspaceReader? workspaceReader;

  String _draftTitle;
  String _draftRefinedGoal;
  List<String> _draftConstraints;
  ProjectDesiredPlan? committedProposal;
  ProjectState? committedProject;

  bool closed = false;

  String get draftTitle => _draftTitle;
  String get draftRefinedGoal => _draftRefinedGoal;
  List<String> get draftConstraints => List.unmodifiable(_draftConstraints);

  bool get projectDetailsChanged =>
      _draftTitle != project.title ||
      _draftRefinedGoal != project.refinedGoal ||
      !_sameStrings(_draftConstraints, project.constraints);

  void setProjectDetails({
    required String title,
    required String refinedGoal,
    List<String>? constraints,
  }) {
    _draftTitle = title;
    _draftRefinedGoal = refinedGoal;
    builder.setValidationRefinedGoal(refinedGoal);
    if (constraints != null) _draftConstraints = [...constraints];
  }

  static bool _sameStrings(Iterable<String> first, Iterable<String> second) {
    final left = first.toList();
    final right = second.toList();
    return left.length == right.length &&
        left.asMap().entries.every((entry) => entry.value == right[entry.key]);
  }
}

/// Model-facing project planning tools.
///
/// The registry is deliberately separate from [ToolService]. It returns
/// [ToolDefinition] values for a planner call and never exposes mutating
/// workspace tools or full domain objects in those schemas.
class ProjectPlanningToolRegistry extends PlanningToolRegistryBase {
  ProjectPlanningToolRegistry({
    required this.context,
    this.includeProjectDetails = false,
  });

  final ProjectPlanningContext context;
  final bool includeProjectDetails;

  @override
  String get terminalToolId => 'plan_commit';

  @override
  String get closedCode => 'draft_closed';

  @override
  String get closedMessage => 'This planning draft has already been committed.';

  @override
  List<ToolDefinition> get toolDefinitions => [
    if (includeProjectDetails) _projectDetailsDefinition,
    if (context.workspaceReader != null) _planningReadFileDefinition,
    _projectViewDefinition,
    _addCriteriaDefinition,
    _addMilestonesDefinition,
    _addTasksDefinition,
    _updateTaskDefinition,
    _setDependencyDefinition,
    _setDispositionDefinition,
    _splitTaskDefinition,
    _retryTaskDefinition,
    _addCheckDefinition,
    _addNoteDefinition,
    _requestDecisionDefinition,
    _previewDefinition,
    _commitDefinition,
  ];

  /// The planning registry has no route to workspace mutation.
  @override
  bool get allowsWorkspaceMutation => false;

  @override
  Future<Map<String, dynamic>> dispatch(
    String toolId,
    Map<String, dynamic> arguments, {
    String? commandId,
  }) async {
    return switch (toolId) {
        'plan_set_project_details' when includeProjectDetails =>
          _setProjectDetails(arguments),
        'planning_read_file' when context.workspaceReader != null =>
          await _planningReadFile(arguments),
        'project_view' => _view(arguments),
        'plan_add_criteria' => _addCriteria(arguments, commandId),
        'plan_add_milestones' => _addMilestones(arguments, commandId),
        'plan_add_tasks' => _addTasks(arguments, commandId),
        'plan_update_task' => _updateTask(arguments, commandId),
        'plan_set_dependency' => _setDependency(arguments, commandId),
        'plan_set_disposition' => _setDisposition(arguments, commandId),
        'plan_split_task' => _splitTask(arguments, commandId),
        'plan_retry_task' => _retryTask(arguments, commandId),
        'plan_add_check' => _addCheck(arguments, commandId),
        'plan_add_note' => _addNote(arguments, commandId),
        'plan_request_user_decision' => _requestDecision(arguments, commandId),
        'plan_preview' => _preview(arguments),
        'plan_commit' => await _commit(arguments),
        _ => throw _argument(
          'unknown_tool',
          'tool',
          'Unknown project planning tool $toolId.',
        ),
      };
  }

  @override
  Map<String, dynamic> domainError(Object error) {
    if (error is ProjectPlanBuilderException) {
      return _error(code: error.code, path: error.path, message: error.message);
    }
    if (error is ProjectViewException) {
      return _error(code: error.code, path: error.path, message: error.message);
    }
    return super.domainError(error);
  }

  Map<String, dynamic> _view(Map<String, dynamic> arguments) {
    _keys(arguments, const {
      'task_ref',
      'criterion_ref',
      'memory_query',
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
      maxItems: _optionalInt(arguments['max_items'], 'max_items'),
    );
    return {...view, 'draft': _draftSummary(preview)};
  }

  Future<Map<String, dynamic>> _planningReadFile(
    Map<String, dynamic> arguments,
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

  ProjectState _projectForDetail(ProjectPlanBuilderPreview preview) {
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

  Map<String, dynamic> _setProjectDetails(Map<String, dynamic> arguments) {
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

  Map<String, dynamic> _addCriteria(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'criteria'});
    final values = _maps(arguments['criteria'], 'criteria', required: true);
    final added = <Map<String, dynamic>>[];
    context.builder.transaction(() {
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        _rejectPersistentFields(value, 'criteria[$index]');
        _keys(value, const {
          'ref',
          'statement',
          'required',
          'verification_mode',
        });
        final statement = _requiredString(
          value['statement'],
          'criteria[$index].statement',
        );
        final ref = _optionalString(value['ref'], 'criteria[$index].ref') ?? '';
        final required =
            _optionalBool(value['required'], 'criteria[$index].required') ??
            true;
        final verificationMode =
            _enumValue(
              ProjectVerificationMode.values,
              value['verification_mode'],
              'criteria[$index].verification_mode',
            ) ??
            ProjectVerificationMode.mixed;
        final id = context.builder.addCriterion(
          statement: statement,
          ref: ref,
          required: required,
          verificationMode: verificationMode,
          commandId: _partCommandId(commandId, index),
        );
        added.add({'id': id, 'ref': ref.isEmpty ? id : ref});
      }
    });
    return {'criteria': added};
  }

  Map<String, dynamic> _addMilestones(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'milestones'});
    final values = _maps(arguments['milestones'], 'milestones', required: true);
    final added = <Map<String, dynamic>>[];
    context.builder.transaction(() {
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        _rejectPersistentFields(value, 'milestones[$index]');
        _keys(value, const {
          'ref',
          'title',
          'objective',
          'criterion_refs',
          'exit_conditions',
          'order',
        });
        final title = _requiredString(
          value['title'],
          'milestones[$index].title',
        );
        final objective = _requiredString(
          value['objective'],
          'milestones[$index].objective',
        );
        final ref =
            _optionalString(value['ref'], 'milestones[$index].ref') ?? '';
        final id = context.builder.addMilestone(
          title: title,
          objective: objective,
          criterionRefs: _stringList(
            value['criterion_refs'],
            'milestones[$index].criterion_refs',
          ),
          exitConditions: _stringList(
            value['exit_conditions'],
            'milestones[$index].exit_conditions',
          ),
          ref: ref,
          order: _optionalInt(value['order'], 'milestones[$index].order'),
          commandId: _partCommandId(commandId, index),
        );
        added.add({'id': id, 'ref': ref.isEmpty ? id : ref});
      }
    });
    return {'milestones': added};
  }

  Map<String, dynamic> _addTasks(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'tasks'});
    final values = _maps(arguments['tasks'], 'tasks', required: true);
    final specs = [
      for (var index = 0; index < values.length; index++)
        _taskSpec(values[index], 'tasks[$index]'),
    ];
    final ids = context.builder.addTasks(specs, commandId: commandId);
    return {
      'tasks': [
        for (var index = 0; index < ids.length; index++)
          {
            'id': ids[index],
            'ref': specs[index].ref.trim().isEmpty
                ? ids[index]
                : specs[index].ref.trim(),
          },
      ],
    };
  }

  Map<String, dynamic> _updateTask(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {
      'task',
      'title',
      'objective',
      'criterion_refs',
      'dependency_refs',
      'milestone_ref',
      'clear_milestone',
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
    final task = _requiredString(arguments['task'], 'task');
    final updated = context.builder.updateTask(
      task,
      title: _optionalString(arguments['title'], 'title'),
      objective: _optionalString(arguments['objective'], 'objective'),
      criterionRefs: _optionalStringList(
        arguments['criterion_refs'],
        'criterion_refs',
      ),
      dependencyRefs: _optionalStringList(
        arguments['dependency_refs'],
        'dependency_refs',
      ),
      milestoneRef: _optionalString(
        arguments['milestone_ref'],
        'milestone_ref',
      ),
      clearMilestone:
          _optionalBool(arguments['clear_milestone'], 'clear_milestone') ??
          false,
      priority: _enumValue(
        TaskPriority.values,
        arguments['priority'],
        'priority',
      ),
      risk: _enumValue(TaskRisk.values, arguments['risk'], 'risk'),
      riskReduction: _enumValue(
        ProjectRiskReduction.values,
        arguments['risk_reduction'],
        'risk_reduction',
      ),
      effort: _enumValue(TaskEffort.values, arguments['effort'], 'effort'),
      selectionRationale: _optionalString(
        arguments['selection_rationale'],
        'selection_rationale',
      ),
      constraints: _optionalStringList(arguments['constraints'], 'constraints'),
      readPaths: _optionalStringList(arguments['read_paths'], 'read_paths'),
      writePaths: _optionalStringList(arguments['write_paths'], 'write_paths'),
      doneCriteria: _optionalStringList(
        arguments['done_criteria'],
        'done_criteria',
      ),
      outOfScope: _optionalStringList(
        arguments['out_of_scope'],
        'out_of_scope',
      ),
      context: _optionalStringList(arguments['context'], 'context'),
      expectedArtifacts: _optionalArtifacts(
        arguments['expected_artifacts'],
        'expected_artifacts',
      ),
      commandId: commandId,
    );
    return {
      'task': {'id': updated.id, 'ref': task},
    };
  }

  Map<String, dynamic> _setDependency(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'task', 'dependency', 'enabled'});
    final task = _requiredString(arguments['task'], 'task');
    final dependency = _requiredString(arguments['dependency'], 'dependency');
    final enabled = _optionalBool(arguments['enabled'], 'enabled') ?? true;
    context.builder.setDependency(
      taskReference: task,
      dependencyReference: dependency,
      enabled: enabled,
      commandId: commandId,
    );
    return {'task': task, 'dependency': dependency, 'enabled': enabled};
  }

  Map<String, dynamic> _setDisposition(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'task', 'disposition'});
    final task = _requiredString(arguments['task'], 'task');
    final disposition =
        _enumValue(
          ProjectPlanTaskDisposition.values,
          arguments['disposition'],
          'disposition',
        ) ??
        (throw _argument(
          'missing_argument',
          'disposition',
          'A task disposition is required.',
        ));
    context.builder.setDisposition(
      taskReference: task,
      disposition: disposition,
      commandId: commandId,
    );
    return {'task': task, 'disposition': disposition.name};
  }

  Map<String, dynamic> _splitTask(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'task', 'children'});
    final task = _requiredString(arguments['task'], 'task');
    final values = _maps(arguments['children'], 'children', required: true);
    final children = [
      for (var index = 0; index < values.length; index++)
        _taskSpec(values[index], 'children[$index]'),
    ];
    final ids = context.builder.splitTask(
      taskReference: task,
      children: children,
      commandId: commandId,
    );
    return {
      'source_task': task,
      'children': [
        for (var index = 0; index < ids.length; index++)
          {
            'id': ids[index],
            'ref': children[index].ref.trim().isEmpty
                ? ids[index]
                : children[index].ref.trim(),
          },
      ],
    };
  }

  Map<String, dynamic> _retryTask(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'task', 'ref', 'title', 'objective'});
    final task = _requiredString(arguments['task'], 'task');
    final ref = _optionalString(arguments['ref'], 'ref') ?? '';
    final id = context.builder.retryTask(
      taskReference: task,
      ref: ref,
      title: _optionalString(arguments['title'], 'title'),
      objective: _optionalString(arguments['objective'], 'objective'),
      commandId: commandId,
    );
    return {
      'source_task': task,
      'task': {'id': id, 'ref': ref.isEmpty ? id : ref},
    };
  }

  Map<String, dynamic> _addCheck(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {
      'task',
      'kind',
      'command',
      'working_directory',
      'criterion_refs',
      'required',
      'description',
    });
    final kind = _requiredString(arguments['kind'], 'kind');
    if (kind != 'command') {
      throw _argument(
        'invalid_check',
        'kind',
        'Only command checks are supported by the project planning tools.',
      );
    }
    final task = _requiredString(arguments['task'], 'task');
    final command = _requiredString(arguments['command'], 'command');
    final id = context.builder.addCommandCheck(
      taskReference: task,
      command: command,
      workingDirectory:
          _optionalString(
            arguments['working_directory'],
            'working_directory',
          ) ??
          '.',
      criterionRefs: _optionalStringList(
        arguments['criterion_refs'],
        'criterion_refs',
      ),
      required: _optionalBool(arguments['required'], 'required') ?? true,
      description: _optionalString(arguments['description'], 'description'),
      commandId: commandId,
    );
    return {
      'task': task,
      'check': {'id': 'command_passes', 'expectation_id': id},
    };
  }

  Map<String, dynamic> _addNote(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'kind', 'content', 'source_id'});
    final kind =
        _enumValue(ProjectMemoryKind.values, arguments['kind'], 'kind') ??
        (throw _argument(
          'missing_argument',
          'kind',
          'A note kind is required.',
        ));
    final id = context.builder.addNote(
      kind: kind,
      content: _requiredString(arguments['content'], 'content'),
      sourceId: _optionalString(arguments['source_id'], 'source_id'),
      commandId: commandId,
    );
    return {
      'note': {'id': id, 'kind': kind.name},
    };
  }

  Map<String, dynamic> _requestDecision(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'question'});
    final id = context.builder.requestUserDecision(
      question: _requiredString(arguments['question'], 'question'),
      commandId: commandId,
    );
    return {
      'question': {'id': id},
    };
  }

  Map<String, dynamic> _preview(Map<String, dynamic> arguments) {
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

  Future<Map<String, dynamic>> _commit(Map<String, dynamic> arguments) async {
    _ensureOpen();
    _keys(arguments, const {'summary', 'rationale'});
    final summary = _optionalString(arguments['summary'], 'summary');
    final rationale = _optionalString(arguments['rationale'], 'rationale');
    _validateOptionalText(summary, 'summary');
    _validateOptionalText(rationale, 'rationale');
    if (summary != null) context.builder.setSummary(summary);
    if (rationale != null) context.builder.setRationale(rationale);
    final committed = await context.builder.commit(
      workspaceRoot: context.workspaceRoot,
      approvalPolicy: context.approvalPolicy,
    );
    final validation = committed.validation;
    final response = <String, dynamic>{
      'revision': committed.proposal.revision,
      'changed': committed.result.changed,
      'awaiting_approval': committed.result.awaitingApproval,
      'validation': [for (final issue in validation.issues) issue.toMap()],
      'diff': _draftDiff(committed.proposal),
    };
    if (!validation.valid) {
      final issue =
          validation.errors.firstOrNull ?? validation.issues.firstOrNull;
      if (issue != null) {
        return _error(
          code: issue.code,
          path: issue.path,
          message: issue.message,
          extra: response,
        );
      }
      return _error(
        code: 'invalid_plan',
        path: 'plan',
        message: 'The plan did not pass validation.',
        extra: response,
      );
    }
    context.committedProposal = committed.proposal;
    context.committedProject = committed.project.copyWith(
      title: context.draftTitle,
      refinedGoal: context.draftRefinedGoal,
      constraints: context.draftConstraints,
    );
    context.closed = true;
    return response;
  }

  ProjectPlanTaskSpec _taskSpec(Map<String, dynamic> value, String path) {
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
    return ProjectPlanTaskSpec(
      ref: _optionalString(value['ref'], '$path.ref') ?? '',
      title: _optionalString(value['title'], '$path.title') ?? '',
      objective: _optionalString(value['objective'], '$path.objective') ?? '',
      criterionRefs: _stringList(
        value['criterion_refs'],
        '$path.criterion_refs',
      ),
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
      doneCriteria: _stringList(value['done_criteria'], '$path.done_criteria'),
      outOfScope: _stringList(value['out_of_scope'], '$path.out_of_scope'),
      context: _stringList(value['context'], '$path.context'),
      expectedArtifacts: _artifacts(
        value['expected_artifacts'],
        '$path.expected_artifacts',
      ),
    );
  }

  void _rejectPersistentFields(Map<String, dynamic> value, String path) {
    rejectPersistentFields(
      value,
      path,
      additional: const {
        'task_id',
        'taskId',
        'revision',
        'fingerprint',
        'revisionIntroduced',
        'revisionUpdated',
        'evidence',
        'steps',
        'currentStepId',
      },
      message: 'Creation tools generate persistent fields; the field is not accepted.',
    );
  }

  List<TaskArtifact> _artifacts(Object? value, String path) {
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

  List<TaskArtifact>? _optionalArtifacts(Object? value, String path) {
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

  static bool _taskChanged(Task existing, Task desired) =>
      _taskSignature(existing) != _taskSignature(desired);

  static String _taskSignature(Task task) => jsonEncode({
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

  static void _keys(Map<String, dynamic> value, Set<String> allowed) {
    for (final key in value.keys) {
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
    String message,
  ) => _PlanningArgumentException(code, path, message);

  static Map<String, dynamic> _error({
    required String code,
    required String path,
    required String message,
    Map<String, dynamic> extra = const {},
  }) => {'ok': false, 'code': code, 'path': path, 'message': message, ...extra};
}

class _PlanningArgumentException extends PlanningToolArgumentException {
  const _PlanningArgumentException(super.code, super.path, super.message);
}

Map<String, dynamic> _schema({
  required Map<String, dynamic> properties,
  List<String> required = const [],
}) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};

Map<String, dynamic> _stringArraySchema() => {
  'type': 'array',
  'items': {'type': 'string'},
};

Map<String, dynamic> _enumSchema(Iterable<String> values) => {
  'type': 'string',
  'enum': values.toList(),
};

final _taskSpecSchema = _schema(
  properties: {
    'ref': {'type': 'string', 'description': 'Optional temporary reference.'},
    'title': {'type': 'string'},
    'objective': {'type': 'string'},
    'criterion_refs': _stringArraySchema(),
    'dependency_refs': _stringArraySchema(),
    'milestone_ref': {'type': 'string'},
    'priority': _enumSchema(TaskPriority.values.map((item) => item.name)),
    'risk': _enumSchema(TaskRisk.values.map((item) => item.name)),
    'risk_reduction': _enumSchema(
      ProjectRiskReduction.values.map((item) => item.name),
    ),
    'effort': _enumSchema(TaskEffort.values.map((item) => item.name)),
    'selection_rationale': {'type': 'string'},
    'constraints': _stringArraySchema(),
    'read_paths': _stringArraySchema(),
    'write_paths': _stringArraySchema(),
    'done_criteria': _stringArraySchema(),
    'out_of_scope': _stringArraySchema(),
    'context': _stringArraySchema(),
    'expected_artifacts': {
      'type': 'array',
      'items': _schema(
        properties: {
          'path': {'type': 'string'},
          'description': {'type': 'string'},
          'kind': {'type': 'string'},
        },
        required: const ['path'],
      ),
    },
  },
);

final _projectDetailsDefinition = ToolDefinition(
  id: 'plan_set_project_details',
  name: 'Set project details',
  description:
      'Set the initial project title, refined goal, and workspace constraints.',
  schema: _schema(
    properties: {
      'title': {'type': 'string'},
      'refined_goal': {'type': 'string'},
      'constraints': _stringArraySchema(),
    },
    required: const ['title', 'refined_goal'],
  ),
);

final _projectViewDefinition = ToolDefinition(
  id: 'project_view',
  name: 'Project view',
  description:
      'Read a bounded project summary, readiness, failures, or one requested detail.',
  schema: _schema(
    properties: {
      'task_ref': {'type': 'string'},
      'criterion_ref': {'type': 'string'},
      'memory_query': {'type': 'string'},
      'max_items': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    },
  ),
);

final _planningReadFileDefinition = ToolDefinition(
  id: 'planning_read_file',
  name: 'Read planning context file',
  description:
      'Read a bounded line window from one existing file in the discovered workspace. Repeat with next_start_line when has_more is true. This is read-only and cannot access files outside the discovery tree.',
  schema: _schema(
    properties: {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative file path from readableFiles.',
      },
      'start_line': {
        'type': 'integer',
        'minimum': 1,
        'description': 'First 1-based line to return. Defaults to 1.',
      },
      'end_line': {
        'type': 'integer',
        'minimum': 1,
        'maximum': ProjectPlanningWorkspaceReader.defaultMaxWindowLines,
        'description':
            'Optional inclusive line number. Each response is capped at a bounded window.',
      },
    },
    required: const ['path'],
  ),
);

final _addCriteriaDefinition = ToolDefinition(
  id: 'plan_add_criteria',
  name: 'Add project criteria',
  description:
      'Add criteria with generated IDs and optional temporary references.',
  schema: _schema(
    properties: {
      'criteria': {
        'type': 'array',
        'minItems': 1,
        'items': _schema(
          properties: {
            'ref': {'type': 'string'},
            'statement': {'type': 'string'},
            'required': {'type': 'boolean'},
            'verification_mode': _enumSchema(
              ProjectVerificationMode.values.map((item) => item.name),
            ),
          },
          required: const ['statement'],
        ),
      },
    },
    required: const ['criteria'],
  ),
);

final _addMilestonesDefinition = ToolDefinition(
  id: 'plan_add_milestones',
  name: 'Add project milestones',
  description: 'Add optional milestones linked to criterion references.',
  schema: _schema(
    properties: {
      'milestones': {
        'type': 'array',
        'minItems': 1,
        'items': _schema(
          properties: {
            'ref': {'type': 'string'},
            'title': {'type': 'string'},
            'objective': {'type': 'string'},
            'criterion_refs': _stringArraySchema(),
            'exit_conditions': _stringArraySchema(),
            'order': {'type': 'integer'},
          },
          required: const ['title', 'objective'],
        ),
      },
    },
    required: const ['milestones'],
  ),
);

final _addTasksDefinition = ToolDefinition(
  id: 'plan_add_tasks',
  name: 'Add project tasks',
  description:
      'Create a small batch of bounded tasks. IDs, statuses, timestamps, gates, and evidence IDs are generated by Hermes.',
  schema: _schema(
    properties: {
      'tasks': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 20,
        'items': _taskSpecSchema,
      },
    },
    required: const ['tasks'],
  ),
);

final _updateTaskDefinition = ToolDefinition(
  id: 'plan_update_task',
  name: 'Update project task',
  description:
      'Patch one existing mutable task by reference; never creates a task.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'criterion_refs': _stringArraySchema(),
      'dependency_refs': _stringArraySchema(),
      'milestone_ref': {'type': 'string'},
      'clear_milestone': {'type': 'boolean'},
      'priority': _enumSchema(TaskPriority.values.map((item) => item.name)),
      'risk': _enumSchema(TaskRisk.values.map((item) => item.name)),
      'risk_reduction': _enumSchema(
        ProjectRiskReduction.values.map((item) => item.name),
      ),
      'effort': _enumSchema(TaskEffort.values.map((item) => item.name)),
      'selection_rationale': {'type': 'string'},
      'constraints': _stringArraySchema(),
      'read_paths': _stringArraySchema(),
      'write_paths': _stringArraySchema(),
      'done_criteria': _stringArraySchema(),
      'out_of_scope': _stringArraySchema(),
      'context': _stringArraySchema(),
      'expected_artifacts': _taskSpecSchema['properties'] is Map
          ? (_taskSpecSchema['properties'] as Map)['expected_artifacts']
          : _stringArraySchema(),
    },
    required: const ['task'],
  ),
);

final _setDependencyDefinition = ToolDefinition(
  id: 'plan_set_dependency',
  name: 'Set task dependency',
  description: 'Add or remove one dependency and reject cycles immediately.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'dependency': {'type': 'string'},
      'enabled': {'type': 'boolean'},
    },
    required: const ['task', 'dependency'],
  ),
);

final _setDispositionDefinition = ToolDefinition(
  id: 'plan_set_disposition',
  name: 'Set task disposition',
  description: 'Defer or obsolete one mutable task by reference.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'disposition': _enumSchema(
        ProjectPlanTaskDisposition.values.map((item) => item.name),
      ),
    },
    required: const ['task', 'disposition'],
  ),
);

final _splitTaskDefinition = ToolDefinition(
  id: 'plan_split_task',
  name: 'Split project task',
  description:
      'Replace one mutable oversized task with newly generated child tasks.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'children': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 5,
        'items': _taskSpecSchema,
      },
    },
    required: const ['task', 'children'],
  ),
);

final _retryTaskDefinition = ToolDefinition(
  id: 'plan_retry_task',
  name: 'Retry failed project task',
  description:
      'Create a fresh retry task while preserving the failed task history.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'ref': {'type': 'string'},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
    },
    required: const ['task'],
  ),
);

final _addCheckDefinition = ToolDefinition(
  id: 'plan_add_check',
  name: 'Add project check',
  description:
      'Add a command verification intent with generated gate and evidence IDs.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'kind': {
        'type': 'string',
        'enum': const ['command'],
      },
      'command': {'type': 'string'},
      'working_directory': {'type': 'string'},
      'criterion_refs': _stringArraySchema(),
      'required': {'type': 'boolean'},
      'description': {'type': 'string'},
    },
    required: const ['task', 'kind', 'command'],
  ),
);

final _addNoteDefinition = ToolDefinition(
  id: 'plan_add_note',
  name: 'Add planning note',
  description:
      'Record a planner fact, assumption, risk, or decision with a generated ID.',
  schema: _schema(
    properties: {
      'kind': _enumSchema(ProjectMemoryKind.values.map((item) => item.name)),
      'content': {'type': 'string'},
      'source_id': {'type': 'string'},
    },
    required: const ['kind', 'content'],
  ),
);

final _requestDecisionDefinition = ToolDefinition(
  id: 'plan_request_user_decision',
  name: 'Request user decision',
  description:
      'Ask one blocking question for a genuinely unsafe-to-assume decision.',
  schema: _schema(
    properties: {
      'question': {'type': 'string'},
    },
    required: const ['question'],
  ),
);

final _previewDefinition = ToolDefinition(
  id: 'plan_preview',
  name: 'Preview project plan',
  description:
      'Validate the draft and return a compact diff without committing it.',
  schema: _schema(
    properties: {
      'summary': {'type': 'string'},
      'rationale': {'type': 'string'},
    },
  ),
);

final _commitDefinition = ToolDefinition(
  id: 'plan_commit',
  name: 'Commit project plan',
  description:
      'Validate and apply the draft through the existing project revision service.',
  schema: _schema(
    properties: {
      'summary': {'type': 'string'},
      'rationale': {'type': 'string'},
    },
  ),
);
