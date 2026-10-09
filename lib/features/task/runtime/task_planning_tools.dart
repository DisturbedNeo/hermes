import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/task/runtime/task_plan_builder.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';

/// State available to one task-planning invocation.
///
/// The registry has no [ToolService] and no workspace mutation route. It only
/// validates each mutation against the complete task and persists it through
/// the owning service before returning a response.
class TaskPlanningToolContext {
  TaskPlanningToolContext({
    required this.task,
    required this.workspaceRoot,
    required this.maxSteps,
    this.projectGoal = '',
    this.acceptance = const [],
    List<AcceptanceItem>? inheritedAcceptance,
    this.outOfScope = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.requireDeclaredWriteBoundary = false,
    this.preserveCompletedStepsOnly = false,
    this.taskNumber = 1,
    this.criterionAgentNumbers = const {},
    this.taskIdsByAgentNumber = const {},
    this.milestoneIdsByAgentNumber = const {},
    this.persistTask,
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
       ),
       currentTask = task,
       inheritedAcceptance = inheritedAcceptance ?? acceptance;

  final TaskAggregate task;
  final String workspaceRoot;
  final int maxSteps;
  final String projectGoal;
  final List<AcceptanceItem> acceptance;
  final List<AcceptanceItem> inheritedAcceptance;
  final List<String> outOfScope;
  final List<String> readPaths;
  final List<String> writePaths;
  final bool requireDeclaredWriteBoundary;
  final bool preserveCompletedStepsOnly;
  final int taskNumber;
  final Map<String, int> criterionAgentNumbers;
  final Map<int, String> taskIdsByAgentNumber;
  final Map<int, String> milestoneIdsByAgentNumber;
  final Future<TaskAggregate> Function(TaskAggregate task)? persistTask;
  TaskPlanBuilder builder;
  TaskAggregate currentTask;

  TaskAggregate? committedTask;
  String? replanReason;
  bool closed = false;

  Future<TaskAggregate> persist(TaskAggregate task) async {
    final persisted = persistTask == null ? task : await persistTask!(task);
    currentTask = persisted;
    builder = TaskPlanBuilder(
      task: persisted,
      maxSteps: maxSteps,
      projectGoal: projectGoal,
      outOfScope: outOfScope,
      readPaths: readPaths,
      writePaths: writePaths,
      requireDeclaredWriteBoundary: requireDeclaredWriteBoundary,
    );
    return persisted;
  }
}

class TaskPlanningToolRegistry extends PlanningToolRegistryBase {
  TaskPlanningToolRegistry({required this.context});

  final TaskPlanningToolContext context;

  @override
  String get terminalToolId => 'plan_finalize';

  @override
  List<ToolDefinition> get toolDefinitions => const [
    _taskAddDefinition,
    _taskUpdateDefinition,
    _taskRemoveDefinition,
    _finalizeDefinition,
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
      'task_add' => await _addTask(arguments),
      'task_update' => await _updateTask(arguments),
      'task_remove' => await _removeTask(arguments),
      'plan_finalize' => await _finalize(arguments),
      _ => throw _argument(
        'unknown_tool',
        'tool',
        'Unknown task planning tool $toolId.',
      ),
    };
    final response = <String, dynamic>{'ok': true, ...result};
    return PlanningResponse.fromWire(response);
  }

  @override
  Map<String, dynamic> domainError(Object error) {
    if (error is TaskPlanBuilderException) {
      return _error(code: error.code, path: error.path, message: error.message);
    }
    if (error is InvalidTaskTransitionException) {
      return _error(
        code: 'invalid_transition',
        path: 'task.status',
        message: error.reason,
      );
    }
    return super.domainError(error);
  }

  Future<Map<String, dynamic>> _addTask(PlanningArguments arguments) async {
    _ensureOpen();
    _keys(arguments, _taskMutationKeys);
    final candidate = _taskCandidate(
      arguments,
      requireComplete: true,
      replaceSteps: true,
      replaceAcceptance: true,
    );
    final committed = _validateCandidate(candidate);
    final persisted = await context.persist(committed);
    return _mutationResponse('added', persisted);
  }

  Future<Map<String, dynamic>> _updateTask(PlanningArguments arguments) async {
    _ensureOpen();
    _keys(arguments, {..._taskMutationKeys, 'task_id'});
    _requireTaskId(arguments['task_id']);
    final candidate = _taskCandidate(arguments);
    final committed = _validateCandidate(candidate);
    final persisted = await context.persist(committed);
    return _mutationResponse('updated', persisted);
  }

  Future<Map<String, dynamic>> _removeTask(PlanningArguments arguments) async {
    _ensureOpen();
    _keys(arguments, const {'task_id'});
    _requireTaskId(arguments['task_id']);
    final transition = const TaskLifecycleService().transition(
      snapshot: context.currentTask,
      to: TaskStatus.obsolete,
      trigger: TaskLifecycleTrigger.planManagement,
      reason: 'Removed by the planning agent.',
    );
    final persisted = await context.persist(transition.task);
    return _mutationResponse('removed', persisted);
  }

  Future<Map<String, dynamic>> _finalize(PlanningArguments arguments) async {
    _ensureOpen();
    _keys(arguments, const {});
    final validation = context.builder.commit();
    if (!validation.valid) {
      final issue = validation.issues.first;
      throw TaskPlanBuilderException(
        code: issue.code,
        path: issue.path,
        message: issue.message,
      );
    }
    final transitioned = context.currentTask.status == TaskStatus.obsolete
        ? context.currentTask
        : const TaskLifecycleService()
              .transition(
                snapshot: context.currentTask,
                to: TaskStatus.planned,
                trigger: TaskLifecycleTrigger.planning,
                reason: 'Task planning finalized.',
              )
              .task;
    final persisted = await context.persist(transitioned);
    context.committedTask = persisted;
    context.closed = true;
    return {
      'finalized': true,
      'task': _taskWire(persisted),
      'persistence_revision': persisted.persistenceRevision,
    };
  }

  TaskAggregate _taskCandidate(
    PlanningArguments arguments, {
    bool requireComplete = false,
    bool replaceSteps = false,
    bool replaceAcceptance = false,
  }) {
    final current = context.currentTask;
    final now = DateTime.now();
    final title = _optionalString(arguments['title'], 'title');
    final objective = _optionalString(arguments['objective'], 'objective');
    final acceptanceSupplied = arguments.containsKey('acceptance');
    final acceptance = acceptanceSupplied
        ? _parseMutationAcceptance(arguments['acceptance'], 'acceptance')
        : replaceAcceptance
        ? const <AcceptanceItem>[]
        : current.acceptance;
    final parsedSteps = arguments.containsKey('steps') || replaceSteps
        ? _parseMutationSteps(arguments['steps'], 'steps')
        : null;
    final steps = parsedSteps == null
        ? current.steps
        : [
            if (context.preserveCompletedStepsOnly)
              ...current.steps.where(_isPreservedStep),
            ...parsedSteps,
          ];
    if (requireComplete && objective == null) {
      throw _argument(
        'missing_argument',
        'objective',
        'A task_add call requires an objective.',
      );
    }
    if (requireComplete &&
        acceptance.isEmpty &&
        context.inheritedAcceptance.isEmpty) {
      throw _argument(
        'missing_argument',
        'acceptance',
        'A task_add call requires acceptance unless inherited acceptance is present.',
      );
    }
    if (requireComplete && steps.isEmpty) {
      throw _argument(
        'missing_argument',
        'steps',
        'A task_add call requires at least one executable step.',
      );
    }
    final mergedAcceptance = acceptanceSupplied
        ? _mergeInheritedAcceptance(acceptance)
        : replaceAcceptance
        ? [...context.inheritedAcceptance]
        : [
            ...context.inheritedAcceptance,
            ...current.acceptance.where(
              (item) => !context.inheritedAcceptance.any(
                (inherited) => inherited.ref == item.ref,
              ),
            ),
          ];
    return current.copyWith(
      title: title ?? current.title,
      objective: objective ?? current.objective,
      constraints: arguments.containsKey('constraints')
          ? _stringList(arguments['constraints'], 'constraints')
          : current.constraints,
      steps: steps,
      acceptance: mergedAcceptance,
      milestoneId: arguments.containsKey('milestone_id')
          ? _resolveAgentReference(
              _optionalInt(arguments['milestone_id'], 'milestone_id'),
              context.milestoneIdsByAgentNumber,
              'milestone_id',
              'milestone',
            )
          : current.milestoneId,
      dependsOnTaskIds: arguments.containsKey('dependency_task_ids')
          ? [
              for (final id in _intList(
                arguments['dependency_task_ids'],
                'dependency_task_ids',
              ))
                _resolveAgentReference(
                  id,
                  context.taskIdsByAgentNumber,
                  'dependency_task_ids',
                  'task',
                )!,
            ]
          : current.dependsOnTaskIds,
      priority:
          _enumValue(TaskPriority.values, arguments['priority'], 'priority') ??
          current.priority,
      risk:
          _enumValue(TaskRisk.values, arguments['risk'], 'risk') ??
          current.risk,
      riskReduction:
          _enumValue(
            ProjectRiskReduction.values,
            arguments['risk_reduction'],
            'risk_reduction',
          ) ??
          current.riskReduction,
      effort:
          _enumValue(TaskEffort.values, arguments['effort'], 'effort') ??
          current.effort,
      selectionRationale:
          _optionalString(
            arguments['selection_rationale'],
            'selection_rationale',
          ) ??
          current.selectionRationale,
      readPaths: arguments.containsKey('read_paths')
          ? _stringList(arguments['read_paths'], 'read_paths')
          : current.readPaths,
      writePaths: arguments.containsKey('write_paths')
          ? _stringList(arguments['write_paths'], 'write_paths')
          : current.writePaths,
      outOfScope: arguments.containsKey('out_of_scope')
          ? _stringList(arguments['out_of_scope'], 'out_of_scope')
          : current.outOfScope,
      context: arguments.containsKey('context')
          ? _stringList(arguments['context'], 'context')
          : current.context,
      status: TaskStatus.paused,
      currentStepId: steps.isEmpty ? null : steps.first.id,
      pendingQuestion: null,
      updatedAt: now,
    );
  }

  TaskAggregate _validateCandidate(TaskAggregate candidate) {
    final committed = TaskPlanBuilder(
      task: candidate,
      maxSteps: context.maxSteps,
      projectGoal: context.projectGoal,
      outOfScope: context.outOfScope,
      readPaths: context.readPaths,
      writePaths: context.writePaths,
      requireDeclaredWriteBoundary: context.requireDeclaredWriteBoundary,
    ).commit();
    if (!committed.valid) {
      final issue = committed.issues.first;
      throw TaskPlanBuilderException(
        code: issue.code,
        path: issue.path,
        message: issue.message,
      );
    }
    return committed.task;
  }

  List<AcceptanceItem> _mergeInheritedAcceptance(
    List<AcceptanceItem> supplied,
  ) {
    final inheritedRefs = {
      for (final item in context.inheritedAcceptance) item.ref,
    };
    for (final item in supplied) {
      if (inheritedRefs.contains(item.ref)) {
        throw _argument(
          'duplicate_acceptance_ref',
          'acceptance',
          'Inherited acceptance ref ${item.ref} must not be re-added.',
        );
      }
    }
    final local = supplied.where((item) => !inheritedRefs.contains(item.ref));
    return [...context.inheritedAcceptance, ...local];
  }

  List<TaskStep> _parseMutationSteps(Object? value, String path) {
    if (value is! List || value.isEmpty) {
      throw _argument(
        'missing_argument',
        path,
        'At least one executable step is required.',
      );
    }
    return [
      for (var index = 0; index < value.length; index++)
        _parseMutationStep(value[index], '$path[$index]'),
    ];
  }

  TaskStep _parseMutationStep(Object? raw, String path) {
    if (raw is! Map) {
      throw _argument('invalid_argument', path, 'A step must be an object.');
    }
    final value = Map<String, dynamic>.from(raw);
    _rejectPersistentFields(value, path);
    _keys(value, const {
      'ref',
      'title',
      'objective',
      'instructions',
      'may_edit_files',
      'artifacts',
      'acceptance_refs',
    }, fieldPath: path);
    final objective = _requiredString(value['objective'], '$path.objective');
    final title = _optionalString(value['title'], '$path.title') ?? objective;
    final artifacts = _artifacts(value['artifacts'], '$path.artifacts');
    return TaskStep(
      id: 'step_${uuid.v7()}',
      title: title,
      objective: objective,
      instructions: _stringList(value['instructions'], '$path.instructions'),
      mayEditFiles:
          _optionalBool(value['may_edit_files'], '$path.may_edit_files') ??
          false,
      artifacts: artifacts,
      acceptanceRefs: _stringList(
        value['acceptance_refs'],
        '$path.acceptance_refs',
      ),
      status: TaskStepStatus.pending,
    );
  }

  List<AcceptanceItem> _parseMutationAcceptance(Object? value, String path) {
    if (value is! List) return const [];
    return [
      for (var index = 0; index < value.length; index++)
        _parseMutationAcceptanceItem(value[index], '$path[$index]'),
    ];
  }

  AcceptanceItem _parseMutationAcceptanceItem(Object? raw, String path) {
    if (raw is! Map) {
      throw _argument(
        'invalid_argument',
        path,
        'Acceptance must be an object.',
      );
    }
    final value = Map<String, dynamic>.from(raw);
    _keys(value, const {
      'ref',
      'statement',
      'criterion_ids',
      'verifiers',
    }, fieldPath: path);
    final verifierMaps = value['verifiers'];
    if (verifierMaps is! List || verifierMaps.isEmpty) {
      throw _argument(
        'missing_argument',
        '$path.verifiers',
        'At least one verifier is required.',
      );
    }
    final verifiers = [
      for (var index = 0; index < verifierMaps.length; index++)
        _parseMutationVerifier(verifierMaps[index], '$path.verifiers[$index]'),
    ];
    return AcceptanceItem(
      ref: _requiredString(value['ref'], '$path.ref'),
      statement: _requiredString(value['statement'], '$path.statement'),
      criterionIds: [
        for (final id in _intList(
          value['criterion_ids'],
          '$path.criterion_ids',
        ))
          _resolveCriterionReference(id, '$path.criterion_ids'),
      ],
      verifiers: verifiers,
    );
  }

  AcceptanceVerifier _parseMutationVerifier(Object? raw, String path) {
    if (raw is! Map) {
      throw _argument(
        'invalid_argument',
        path,
        'A verifier must be an object.',
      );
    }
    final value = Map<String, dynamic>.from(raw);
    _keys(value, const {
      'kind',
      'required',
      'command',
      'working_directory',
      'path',
      'artifact_kind',
      'description',
    }, fieldPath: path);
    final kindName = _requiredString(value['kind'], '$path.kind');
    final kind = AcceptanceVerifierKind.values.firstWhere(
      (item) => item.name == kindName,
      orElse: () => throw _argument(
        'invalid_argument',
        '$path.kind',
        'Unsupported verifier kind $kindName.',
      ),
    );
    return AcceptanceVerifier(
      kind: kind,
      required: _optionalBool(value['required'], '$path.required') ?? true,
      command: _optionalString(value['command'], '$path.command'),
      workingDirectory:
          _optionalString(
            value['working_directory'],
            '$path.working_directory',
          ) ??
          '.',
      path: _optionalString(value['path'], '$path.path'),
      artifactKind:
          _optionalString(value['artifact_kind'], '$path.artifact_kind') ??
          'file',
      description: _optionalString(value['description'], '$path.description'),
    );
  }

  Map<String, dynamic> _mutationResponse(String action, TaskAggregate task) => {
    action: true,
    'task': _taskWire(task),
    'persistence_revision': task.persistenceRevision,
    'next_action': 'plan_finalize',
  };

  Map<String, dynamic> _taskWire(TaskAggregate task) => {
    'task_id': context.taskNumber,
    'title': task.title,
    'objective': task.objective,
    'constraints': task.constraints,
    'out_of_scope': task.outOfScope,
    'read_paths': task.readPaths,
    'write_paths': task.writePaths,
    'context': task.context,
    'dependency_task_ids': [
      for (final id in task.dependsOnTaskIds)
        ?context.taskIdsByAgentNumber.entries
            .where((entry) => entry.value == id)
            .map((entry) => entry.key)
            .firstOrNull,
    ],
    'milestone_id': task.milestoneId == null
        ? null
        : context.milestoneIdsByAgentNumber.entries
              .where((entry) => entry.value == task.milestoneId)
              .map((entry) => entry.key)
              .firstOrNull,
    'priority': task.priority.name,
    'risk': task.risk.name,
    'risk_reduction': task.riskReduction.name,
    'effort': task.effort.name,
    'selection_rationale': task.selectionRationale,
    'status': task.status.wire,
    'steps': [
      for (var index = 0; index < task.steps.length; index++)
        {
          'ref': 'step_${index + 1}',
          'title': task.steps[index].title,
          'objective': task.steps[index].objective,
          'instructions': task.steps[index].instructions,
          'may_edit_files': task.steps[index].mayEditFiles,
          'acceptance_refs': task.steps[index].acceptanceRefs,
          'artifacts': [
            for (final artifact in task.steps[index].artifacts)
              {
                'path': artifact.path,
                'description': artifact.description,
                'kind': artifact.kind,
              },
          ],
        },
    ],
    'inherited_acceptance': [
      for (final item in context.inheritedAcceptance)
        _acceptanceWireNumeric(item),
    ],
    'local_acceptance': [
      for (final item in task.acceptance)
        if (!context.inheritedAcceptance.any(
          (inherited) => inherited.ref == item.ref,
        ))
          _acceptanceWireNumeric(item),
    ],
    'effective_acceptance': [
      for (final item in task.acceptance) _acceptanceWireNumeric(item),
    ],
  };

  Map<String, dynamic> _acceptanceWireNumeric(AcceptanceItem item) => {
    'ref': item.ref,
    'statement': item.statement,
    'criterion_ids': [
      for (final id in item.criterionIds)
        if (_criterionAgentNumber(id) != null) _criterionAgentNumber(id)!,
    ],
    'verifiers': [
      for (final verifier in item.verifiers)
        {
          'kind': verifier.kind.name,
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

  int? _criterionAgentNumber(String id) =>
      context.criterionAgentNumbers[id] ?? int.tryParse(id);

  String _resolveCriterionReference(int number, String path) {
    if (context.criterionAgentNumbers.isEmpty) return number.toString();
    final id = context.criterionAgentNumbers.entries
        .where((entry) => entry.value == number)
        .map((entry) => entry.key)
        .firstOrNull;
    if (id == null) {
      throw _argument(
        'unknown_reference',
        path,
        'Unknown criterion reference $number.',
      );
    }
    return id;
  }

  String? _resolveAgentReference(
    int? number,
    Map<int, String> references,
    String path,
    String kind,
  ) {
    if (number == null) return null;
    if (references.isEmpty) return number.toString();
    final resolved = references[number];
    if (resolved == null) {
      throw _argument(
        'unknown_reference',
        path,
        'Unknown $kind reference $number.',
      );
    }
    return resolved;
  }

  bool _isPreservedStep(TaskStep step) =>
      step.status == TaskStepStatus.completed ||
      step.status == TaskStepStatus.skipped;

  void _requireTaskId(Object? value) {
    final id = _optionalInt(value, 'task_id');
    if (id == null || id != context.taskNumber) {
      throw _argument(
        'unknown_reference',
        'task_id',
        'Task $value is not the current task.',
      );
    }
  }

  static const _taskMutationKeys = {
    'title',
    'objective',
    'constraints',
    'acceptance',
    'steps',
    'out_of_scope',
    'read_paths',
    'write_paths',
    'context',
    'dependency_task_ids',
    'milestone_id',
    'priority',
    'risk',
    'risk_reduction',
    'effort',
    'selection_rationale',
  };

  List<int> _intList(Object? value, String fieldPath) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! int)) {
      throw _argument(
        'invalid_argument',
        fieldPath,
        'Expected an array of integers.',
      );
    }
    return [for (final item in value.cast<int>()) item];
  }

  T? _enumValue<T extends Enum>(
    Iterable<T> values,
    Object? value,
    String fieldPath,
  ) {
    if (value == null) return null;
    if (value is! String) {
      throw _argument(
        'invalid_argument',
        fieldPath,
        'Expected a string enum value.',
      );
    }
    for (final item in values) {
      if (item.name == value) return item;
    }
    throw _argument('invalid_argument', fieldPath, 'Unsupported value $value.');
  }

  void _ensureOpen() {
    if (context.closed) {
      throw _argument(
        'planning_closed',
        'tool',
        'The task plan was already finalized.',
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

const ToolDefinition _taskAddDefinition = ToolDefinition(
  id: 'task_add',
  name: 'Add task',
  description:
      'Create or replace the complete current task in one validated operation.',
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
      'out_of_scope': {
        'type': 'array',
        'minItems': 1,
        'items': {'type': 'string'},
      },
      'read_paths': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'write_paths': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'context': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'dependency_task_ids': {
        'type': 'array',
        'items': {'type': 'integer', 'minimum': 1},
      },
      'milestone_id': {'type': 'integer', 'minimum': 1},
      'priority': {
        'type': 'string',
        'enum': ['critical', 'high', 'normal', 'low'],
      },
      'risk': {
        'type': 'string',
        'enum': ['high', 'medium', 'low', 'unknown'],
      },
      'risk_reduction': {
        'type': 'string',
        'enum': ['high', 'medium', 'low', 'none'],
      },
      'effort': {
        'type': 'string',
        'enum': ['small', 'medium', 'large'],
      },
      'selection_rationale': {'type': 'string'},
      'acceptance': _taskAcceptanceSchema,
      'steps': _taskStepsSchema,
    },
    'required': ['objective', 'acceptance', 'out_of_scope', 'steps'],
  }),
);

const ToolDefinition _taskUpdateDefinition = ToolDefinition(
  id: 'task_update',
  name: 'Update task',
  description:
      'Partially update the current task. Omitted fields remain unchanged.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'task_id': {'type': 'integer', 'minimum': 1},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'constraints': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'out_of_scope': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'read_paths': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'write_paths': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'context': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'dependency_task_ids': {
        'type': 'array',
        'items': {'type': 'integer', 'minimum': 1},
      },
      'milestone_id': {'type': 'integer', 'minimum': 1},
      'priority': {
        'type': 'string',
        'enum': ['critical', 'high', 'normal', 'low'],
      },
      'risk': {
        'type': 'string',
        'enum': ['high', 'medium', 'low', 'unknown'],
      },
      'risk_reduction': {
        'type': 'string',
        'enum': ['high', 'medium', 'low', 'none'],
      },
      'effort': {
        'type': 'string',
        'enum': ['small', 'medium', 'large'],
      },
      'selection_rationale': {'type': 'string'},
      'acceptance': _taskAcceptanceSchema,
      'steps': _taskStepsSchema,
    },
    'required': ['task_id'],
  }),
);

const ToolDefinition _taskRemoveDefinition = ToolDefinition(
  id: 'task_remove',
  name: 'Remove task',
  description:
      'Remove the current task from active planning while preserving its history.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'task_id': {'type': 'integer', 'minimum': 1},
    },
    'required': ['task_id'],
  }),
);

const ToolDefinition _finalizeDefinition = ToolDefinition(
  id: 'plan_finalize',
  name: 'Finalize plan',
  description:
      'Finish planning and move the validated persisted task into implementation.',
  schema: ToolSchema({
    'type': 'object',
    'additionalProperties': false,
    'properties': {},
  }),
);

const Map<String, dynamic> _taskAcceptanceSchema = {
  'type': 'array',
  'minItems': 0,
  'items': {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'ref': {'type': 'string'},
      'statement': {'type': 'string'},
      'criterion_ids': {
        'type': 'array',
        'items': {'type': 'integer', 'minimum': 1},
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
  },
};

const Map<String, dynamic> _taskStepsSchema = {
  'type': 'array',
  'minItems': 1,
  'items': {
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
      'may_edit_files': {'type': 'boolean', 'default': false},
      'artifacts': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'path': {'type': 'string'},
            'description': {'type': 'string'},
            'kind': {'type': 'string', 'default': 'file'},
          },
          'required': ['path'],
        },
      },
      'acceptance_refs': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['objective'],
  },
};
