import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/task/runtime/task_plan_builder.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';

/// State available to one task-planning invocation.
///
/// The registry has no [ToolService] and no workspace mutation route. It only
/// edits the in-memory builder and returns a task to the owning service after
/// a valid commit.
class TaskPlanningToolContext {
  TaskPlanningToolContext({
    required this.task,
    required this.workspaceRoot,
    required this.maxSteps,
    this.projectGoal = '',
    this.acceptance = const [],
    this.outOfScope = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.requireDeclaredWriteBoundary = false,
    this.preserveCompletedStepsOnly = false,
    this.viewService = const TaskViewService(),
    DateTime? now,
  }) : builder = TaskPlanBuilder(
         task: task,
         maxSteps: maxSteps,
         projectGoal: projectGoal,
         outOfScope: outOfScope,
         readPaths: readPaths,
         writePaths: writePaths,
         acceptance: acceptance,
         requireDeclaredWriteBoundary: requireDeclaredWriteBoundary,
         preserveCompletedStepsOnly: preserveCompletedStepsOnly,
         now: now,
       );

  final TaskAggregate task;
  final String workspaceRoot;
  final int maxSteps;
  final String projectGoal;
  final List<AcceptanceItem> acceptance;
  final List<String> outOfScope;
  final List<String> readPaths;
  final List<String> writePaths;
  final bool requireDeclaredWriteBoundary;
  final bool preserveCompletedStepsOnly;
  final TaskViewService viewService;
  final TaskPlanBuilder builder;

  TaskAggregate? committedTask;
  String? replanReason;
  bool closed = false;
}

class TaskPlanningToolRegistry extends PlanningToolRegistryBase {
  TaskPlanningToolRegistry({required this.context});

  final TaskPlanningToolContext context;

  @override
  String get terminalToolId => 'task_commit_plan';

  @override
  List<ToolDefinition> get toolDefinitions => const [
    _taskViewDefinition,
    _setBriefDefinition,
    _resetPlanDefinition,
    _addStepDefinition,
    _addAcceptanceDefinition,
    _previewDefinition,
    _commitDefinition,
    _requestReplanDefinition,
    _requestDecisionDefinition,
  ];

  @override
  bool get allowsWorkspaceMutation => false;

  @override
  Future<PlanningResponse> dispatch(
    String toolId,
    PlanningArguments arguments, {
    String? commandId,
  }) async {
    final result = switch (toolId) {
      'task_view' => _view(arguments),
      'task_set_brief' => _setBrief(arguments),
      'task_reset_plan' => _resetPlan(arguments, commandId),
      'task_add_step' => _addStep(arguments, commandId),
      'task_add_acceptance' => _addAcceptance(arguments, commandId),
      'task_preview_plan' => _preview(arguments),
      'task_commit_plan' => _commit(arguments),
      'task_request_replan' => _requestReplan(arguments),
      'task_request_user_decision' => _requestDecision(arguments, commandId),
      _ => throw _argument(
        'unknown_tool',
        'tool',
        'Unknown task planning tool $toolId.',
      ),
    };
    final response = <String, dynamic>{'ok': true, ...result};
    if (_mutationToolIds.contains(toolId)) {
      response['state'] = _draftState();
    }
    return PlanningResponse.fromWire(response);
  }

  static const _mutationToolIds = {
    'task_set_brief',
    'task_reset_plan',
    'task_add_step',
    'task_add_acceptance',
    'task_request_replan',
    'task_request_user_decision',
  };

  @override
  Map<String, dynamic> domainError(Object error) {
    if (error is TaskPlanBuilderException) {
      return _error(code: error.code, path: error.path, message: error.message);
    }
    if (error is TaskViewException) {
      return _error(code: error.code, path: error.path, message: error.message);
    }
    return super.domainError(error);
  }

  Map<String, dynamic> _view(PlanningArguments arguments) {
    _keys(arguments, const {'step_ref', 'max_items', 'section', 'cursor'});
    final stepRef = _optionalString(arguments['step_ref'], 'step_ref');
    final section = _optionalString(arguments['section'], 'section');
    final cursor = _optionalString(arguments['cursor'], 'cursor');
    final preview = context.builder.preview();
    final draftStepId = stepRef == null
        ? null
        : context.builder.stepIdFor(stepRef);
    final viewTask = draftStepId != null
        ? preview.task
        : context.preserveCompletedStepsOnly
        ? context.task
        : preview.task;
    final view = context.viewService.query(
      viewTask,
      stepRef: draftStepId ?? stepRef,
      maxItems: _optionalInt(arguments['max_items'], 'max_items'),
      maxSteps: context.maxSteps,
      projectGoal: context.projectGoal,
      outOfScope: context.outOfScope,
      readPaths: context.readPaths,
      writePaths: context.writePaths,
      section: section,
      cursor: cursor,
    );
    return {
      ...view,
      'planning': {
        'max_steps': context.maxSteps,
        'draft_step_count': preview.task.steps.length,
        'draft_next_step_ref': preview.task.currentStepId,
        'preserve_completed_steps_only': context.preserveCompletedStepsOnly,
        'draft_issues': [for (final issue in preview.issues) issue.toMap()],
      },
    };
  }

  Map<String, dynamic> _setBrief(PlanningArguments arguments) {
    _ensureOpen();
    _keys(arguments, const {'title', 'objective', 'constraints'});
    final title = _optionalString(arguments['title'], 'title');
    final objective = _optionalString(arguments['objective'], 'objective');
    final constraints = arguments.containsKey('constraints')
        ? _stringList(arguments['constraints'], 'constraints')
        : null;
    if (title == null && objective == null && constraints == null) {
      throw _argument(
        'missing_argument',
        'brief',
        'Provide at least one brief field to update.',
      );
    }
    context.builder.setBrief(
      title: title,
      objective: objective,
      constraints: constraints,
    );
    return {
      'title': context.builder.preview().task.title,
      'objective': context.builder.preview().task.objective,
      'acceptance': [
        for (final item in context.builder.preview().task.acceptance)
          _acceptanceWire(item),
      ],
    };
  }

  Map<String, dynamic> _resetPlan(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {});
    context.builder.resetDraft(commandId: commandId);
    return {
      'reset': true,
      'preserved_step_count': context.builder.steps.length,
    };
  }

  Map<String, dynamic> _addStep(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _rejectPersistentFields(arguments, 'step');
    _keys(arguments, const {
      'ref',
      'title',
      'objective',
      'instructions',
      'may_edit_files',
      'artifacts',
      'acceptance_refs',
    });
    final ref = _optionalString(arguments['ref'], 'ref') ?? '';
    final title = _optionalString(arguments['title'], 'title') ?? '';
    final objective = _requiredString(arguments['objective'], 'objective');
    final instructions = _stringList(arguments['instructions'], 'instructions');
    final artifacts = _artifacts(arguments['artifacts'], 'artifacts');
    final mayEditFiles =
        _optionalBool(arguments['may_edit_files'], 'may_edit_files') ?? false;
    final acceptanceRefs = _stringList(
      arguments['acceptance_refs'],
      'acceptance_refs',
    );
    final id = context.builder.addStep(
      TaskPlanStepSpec(
        ref: ref,
        title: title,
        objective: objective,
        instructions: instructions,
        mayEditFiles: mayEditFiles,
        artifacts: artifacts,
        acceptanceRefs: acceptanceRefs,
      ),
      commandId: commandId,
    );
    final step = context.builder.preview().task.stepById(id)!;
    return {
      'changed': true,
      'step': _stepDetail(step, ref.trim().isEmpty ? id : ref.trim()),
    };
  }

  Map<String, dynamic> _addAcceptance(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'ref', 'statement', 'criterion_refs', 'verifiers'});
    final item = _parseAcceptance(
      arguments.toWire(),
      'acceptance',
      allowEmptyCriteria: true,
    );
    context.builder.addAcceptance(item: item, commandId: commandId);
    return {'changed': true, 'acceptance': _acceptanceWire(item)};
  }

  Map<String, dynamic> _preview(PlanningArguments arguments) {
    _ensureOpen();
    _keys(arguments, const {});
    final preview = context.builder.preview();
    return {
      'plan': _planSummary(preview.task),
      'issues': [for (final issue in preview.issues) issue.toMap()],
    };
  }

  Map<String, dynamic> _commit(PlanningArguments arguments) {
    _ensureOpen();
    _keys(arguments, const {});
    final committed = context.builder.commit();
    final response = {
      'plan': _planSummary(committed.task),
      'control': _controlState(committed.task),
      'issues': [for (final issue in committed.issues) issue.toMap()],
    };
    if (!committed.valid) {
      final issue = committed.issues.first;
      return _error(
        code: issue.code,
        path: issue.path,
        message: issue.message,
        extra: response,
      );
    }
    context.committedTask = committed.task;
    context.closed = true;
    return response;
  }

  Map<String, dynamic> _requestReplan(PlanningArguments arguments) {
    _ensureOpen();
    _keys(arguments, const {'reason'});
    final reason = _requiredString(arguments['reason'], 'reason');
    context.builder.requestReplan(reason);
    context.replanReason = reason;
    return {'reason': reason};
  }

  Map<String, dynamic> _requestDecision(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {'question', 'step_ref'});
    final stepRef = _optionalString(arguments['step_ref'], 'step_ref');
    final id = context.builder.requestUserDecision(
      question: _requiredString(arguments['question'], 'question'),
      stepReference: stepRef,
      commandId: commandId,
    );
    return {
      'changed': true,
      'question': {'id': id, 'step_ref': stepRef},
    };
  }

  Map<String, dynamic> _draftState() {
    final preview = context.builder.preview();
    return {
      'plan': _planSummary(preview.task),
      'steps': [
        for (final step in preview.task.steps) _stepDetail(step, step.id),
      ],
      'acceptance': [
        for (final item in preview.task.acceptance) _acceptanceSummary(item),
      ],
      'issues': [for (final issue in preview.issues) issue.toMap()],
      'control': _controlState(preview.task),
    };
  }

  Map<String, dynamic> _stepDetail(TaskStep step, String ref) => {
    'id': step.id,
    'ref': ref,
    'title': step.title,
    'objective': step.objective,
    'status': step.status.wire,
    'may_edit_files': step.mayEditFiles,
    'instructions': step.instructions,
    'artifacts': [
      for (final artifact in step.artifacts)
        {
          'path': artifact.path,
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
    'acceptance_refs': step.acceptanceRefs,
  };

  Map<String, dynamic> _acceptanceSummary(AcceptanceItem item) => {
    'ref': item.ref,
    'statement': item.statement,
    'criterion_refs': item.criterionIds,
    'verifiers': [
      for (final verifier in item.verifiers)
        {
          'kind': verifier.kind.wire,
          'required': verifier.required,
          'status': 'pending',
          if (verifier.command != null) 'command': verifier.command,
          if (verifier.path != null) 'path': verifier.path,
          if (verifier.description != null) 'description': verifier.description,
        },
    ],
  };

  Map<String, dynamic> _controlState(TaskAggregate task) => {
    'outcome': task.pendingQuestion != null
        ? 'awaiting_user_input'
        : task.status.wire,
    'action': task.pendingQuestion == null ? null : 'answer_question',
    'pending_question': task.pendingQuestion == null
        ? null
        : {
            'id': task.pendingQuestion!.id,
            'step_ref': task.pendingQuestion!.stepId,
            'question': task.pendingQuestion!.question,
          },
  };

  Map<String, dynamic> _planSummary(TaskAggregate task) => {
    'task_id': task.id,
    'title': task.title,
    'objective': task.objective,
    'step_count': task.steps.length,
    'next_step_ref': task.currentStepId,
    'status': task.status.wire,
    'acceptance': [
      for (final item in task.acceptance) _acceptanceSummary(item),
    ],
  };

  void _ensureOpen() {
    if (context.closed) {
      throw _argument(
        'planning_closed',
        'tool',
        'The task plan was already committed.',
      );
    }
  }

  void _rejectPersistentFields(Object value, String fieldPath) {
    rejectPersistentFields(
      value,
      fieldPath,
      additional: const {
        'step_id',
        'stepId',
        'run_id',
        'runId',
        'current_step_id',
        'currentStepId',
      },
    );
  }

  List<TaskArtifact> _artifacts(Object? value, String fieldPath) {
    if (value == null) return const [];
    if (value is! List) {
      throw _argument(
        'invalid_argument',
        fieldPath,
        'Expected an array of artifact declarations.',
      );
    }
    return [
      for (var index = 0; index < value.length; index++)
        _artifact(value[index], '$fieldPath[$index]'),
    ];
  }

  TaskArtifact _artifact(Object? raw, String fieldPath) {
    if (raw is! Map) {
      throw _argument(
        'invalid_argument',
        fieldPath,
        'An artifact declaration must be an object.',
      );
    }
    final value = Map<String, dynamic>.from(raw);
    _rejectPersistentFields(value, fieldPath);
    _keys(value, const {'path', 'description', 'kind'}, fieldPath: fieldPath);
    return TaskArtifact(
      path: _requiredString(value['path'], '$fieldPath.path'),
      description: _optionalString(
        value['description'],
        '$fieldPath.description',
      ),
      kind: _optionalString(value['kind'], '$fieldPath.kind') ?? 'file',
    );
  }

  AcceptanceItem _parseAcceptance(
    Map<String, dynamic> value,
    String fieldPath, {
    required bool allowEmptyCriteria,
  }) {
    _keys(value, const {
      'ref',
      'statement',
      'criterion_refs',
      'verifiers',
    }, fieldPath: fieldPath);
    final criterionIds = _stringList(
      value['criterion_refs'],
      '$fieldPath.criterion_refs',
    );
    if (!allowEmptyCriteria && criterionIds.isEmpty) {
      throw _argument(
        'missing_argument',
        '$fieldPath.criterion_refs',
        'Project-linked acceptance needs at least one criterion reference.',
      );
    }
    final rawVerifiers = value['verifiers'];
    if (rawVerifiers is! List || rawVerifiers.isEmpty) {
      throw _argument(
        'missing_argument',
        '$fieldPath.verifiers',
        'At least one verifier is required.',
      );
    }
    final verifiers = <AcceptanceVerifier>[];
    for (var index = 0; index < rawVerifiers.length; index++) {
      final raw = rawVerifiers[index];
      if (raw is! Map) {
        throw _argument(
          'invalid_argument',
          '$fieldPath.verifiers[$index]',
          'A verifier must be an object.',
        );
      }
      final verifier = Map<String, dynamic>.from(raw);
      _keys(verifier, const {
        'kind',
        'required',
        'command',
        'working_directory',
        'path',
        'artifact_kind',
        'description',
      }, fieldPath: '$fieldPath.verifiers[$index]');
      final kindName = _requiredString(
        verifier['kind'],
        '$fieldPath.verifiers[$index].kind',
      );
      final kind = AcceptanceVerifierKind.values.firstWhere(
        (item) => item.name == kindName,
        orElse: () => throw _argument(
          'invalid_argument',
          '$fieldPath.verifiers[$index].kind',
          'Unsupported verifier kind $kindName.',
        ),
      );
      final parsed = AcceptanceVerifier(
        kind: kind,
        required:
            _optionalBool(
              verifier['required'],
              '$fieldPath.verifiers[$index].required',
            ) ??
            true,
        command: _optionalString(
          verifier['command'],
          '$fieldPath.verifiers[$index].command',
        ),
        workingDirectory:
            _optionalString(
              verifier['working_directory'],
              '$fieldPath.verifiers[$index].working_directory',
            ) ??
            '.',
        path: _optionalString(
          verifier['path'],
          '$fieldPath.verifiers[$index].path',
        ),
        artifactKind:
            _optionalString(
              verifier['artifact_kind'],
              '$fieldPath.verifiers[$index].artifact_kind',
            ) ??
            'file',
        description: _optionalString(
          verifier['description'],
          '$fieldPath.verifiers[$index].description',
        ),
      );
      if (!parsed.hasConfiguration) {
        throw _argument(
          'invalid_argument',
          '$fieldPath.verifiers[$index]',
          'Verifier configuration does not match its kind.',
        );
      }
      verifiers.add(parsed);
    }
    if (!verifiers.any((item) => item.required)) {
      throw _argument(
        'missing_required_verifier',
        '$fieldPath.verifiers',
        'At least one verifier must be required.',
      );
    }
    return AcceptanceItem(
      ref: _requiredString(value['ref'], '$fieldPath.ref'),
      statement: _requiredString(value['statement'], '$fieldPath.statement'),
      criterionIds: criterionIds,
      verifiers: verifiers,
    );
  }

  Map<String, dynamic> _acceptanceWire(AcceptanceItem item) => {
    'ref': item.ref,
    'statement': item.statement,
    'criterion_refs': item.criterionIds,
    'verifiers': [
      for (final verifier in item.verifiers)
        {
          'kind': verifier.kind.wire,
          'required': verifier.required,
          if (verifier.command != null) 'command': verifier.command,
          if (verifier.workingDirectory != '.')
            'working_directory': verifier.workingDirectory,
          if (verifier.path != null) 'path': verifier.path,
          if (verifier.artifactKind != 'file')
            'artifact_kind': verifier.artifactKind,
          if (verifier.description != null) 'description': verifier.description,
        },
    ],
  };

  void _keys(
    Object value,
    Set<String> allowed, {
    String fieldPath = 'arguments',
  }) {
    final keys = value is PlanningArguments
        ? value.keys
        : (value as Map<String, dynamic>).keys;
    for (final key in keys) {
      if (!allowed.contains(key)) {
        throw _argument(
          'invalid_argument',
          '$fieldPath.$key',
          'Unknown planning argument $key.',
        );
      }
    }
  }

  String _requiredString(Object? value, String fieldPath) {
    final text = _optionalString(value, fieldPath);
    if (text == null || text.isEmpty) {
      throw _argument(
        'missing_argument',
        fieldPath,
        'A non-empty string is required.',
      );
    }
    return text;
  }

  String? _optionalString(Object? value, String fieldPath) {
    if (value == null) return null;
    if (value is! String) {
      throw _argument('invalid_argument', fieldPath, 'Expected a string.');
    }
    return value.trim();
  }

  bool? _optionalBool(Object? value, String fieldPath) {
    if (value == null) return null;
    if (value is! bool) {
      throw _argument('invalid_argument', fieldPath, 'Expected a boolean.');
    }
    return value;
  }

  int? _optionalInt(Object? value, String fieldPath) {
    if (value == null) return null;
    if (value is! int) {
      throw _argument('invalid_argument', fieldPath, 'Expected an integer.');
    }
    return value;
  }

  List<String> _stringList(Object? value, String fieldPath) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw _argument(
        'invalid_argument',
        fieldPath,
        'Expected an array of strings.',
      );
    }
    return [
      for (final item in value.cast<String>()) item.trim(),
    ].where((item) => item.isNotEmpty).toList();
  }

  static Map<String, dynamic> _error({
    required String code,
    required String path,
    required String message,
    Map<String, dynamic>? extra,
  }) => {
    'ok': false,
    'code': code,
    'path': path,
    'message': message,
    ...?extra,
  };

  static _TaskPlanningArgumentException _argument(
    String code,
    String path,
    String message,
  ) => _TaskPlanningArgumentException(code, path, message);
}

class _TaskPlanningArgumentException extends PlanningToolArgumentException {
  const _TaskPlanningArgumentException(super.code, super.path, super.message);
}

const ToolDefinition _taskViewDefinition = ToolDefinition(
  id: 'task_view',
  name: 'View task plan',
  description:
      'Inspect a bounded task summary, its step statuses, acceptance, and boundaries.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'step_ref': {
        'type': 'string',
        'description': 'A step ref returned by task_add_step or task_view.',
      },
      'section': {
        'type': 'string',
        'enum': TaskViewService.viewSections,
        'description':
            'Optional collection to page. Use the next_cursor returned in navigation.pages.',
      },
      'cursor': {
        'type': 'string',
        'description':
            'Cursor returned in navigation.pages for the selected section.',
      },
      'max_items': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 48,
        'default': 12,
      },
    },
  }),
);

const ToolDefinition _setBriefDefinition = ToolDefinition(
  id: 'task_set_brief',
  name: 'Set task brief',
  description:
      'Refine the task title, objective, or constraints. Acceptance is managed separately.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'constraints': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
  }),
);

const ToolDefinition _addStepDefinition = ToolDefinition(
  id: 'task_add_step',
  name: 'Add task step',
  description:
      'Add one independently executable step. Hermes generates its persistent ID.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'ref': {'type': 'string'},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'instructions': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'may_edit_files': {
        'type': 'boolean',
        'default': false,
        'description':
            'Whether this step may edit source files. Defaults to read-only.',
      },
      'artifacts': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'path': {'type': 'string'},
            'description': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': ['file', 'directory'],
              'default': 'file',
              'description':
                  'Use directory for a directory output; file is the default.',
            },
          },
          'required': ['path'],
        },
      },
      'acceptance_refs': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Acceptance refs verified by this step.',
      },
    },
    'required': ['objective'],
  }),
);

const ToolDefinition _resetPlanDefinition = ToolDefinition(
  id: 'task_reset_plan',
  name: 'Reset task draft',
  description:
      'Discard the current uncommitted draft so it can be rebuilt with planning commands. Completed and skipped steps are preserved during replanning.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {},
  }),
);

const ToolDefinition _addAcceptanceDefinition = ToolDefinition(
  id: 'task_add_acceptance',
  name: 'Add task acceptance',
  description:
      'Add one explicit local acceptance item. Hermes creates all gate and evidence identifiers.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'ref': {'type': 'string'},
      'statement': {'type': 'string'},
      'criterion_refs': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Leave empty for task-local acceptance.',
      },
      'verifiers': {
        'type': 'array',
        'minItems': 1,
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['command', 'artifact', 'review', 'approval'],
            },
            'required': {'type': 'boolean', 'default': true},
            'command': {'type': 'string'},
            'working_directory': {'type': 'string', 'default': '.'},
            'path': {'type': 'string'},
            'artifact_kind': {'type': 'string', 'default': 'file'},
            'description': {'type': 'string'},
          },
          'required': ['kind'],
        },
      },
    },
    'required': ['ref', 'statement', 'verifiers'],
  }),
);

const ToolDefinition _previewDefinition = ToolDefinition(
  id: 'task_preview_plan',
  name: 'Preview task plan',
  description: 'Validate the current task draft without committing it.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {},
  }),
);

const ToolDefinition _commitDefinition = ToolDefinition(
  id: 'task_commit_plan',
  name: 'Commit task plan',
  description: 'Validate and finish the task plan draft.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {},
  }),
);

const ToolDefinition _requestReplanDefinition = ToolDefinition(
  id: 'task_request_replan',
  name: 'Request task replan',
  description: 'Record a concrete reason why unfinished work needs replanning.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'reason': {'type': 'string'},
    },
    'required': ['reason'],
  }),
);

const ToolDefinition _requestDecisionDefinition = ToolDefinition(
  id: 'task_request_user_decision',
  name: 'Request user decision',
  description: 'Ask one genuinely blocking user question.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'question': {'type': 'string'},
      'step_ref': {'type': 'string'},
    },
    'required': ['question'],
  }),
);
