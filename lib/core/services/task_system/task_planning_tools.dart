import 'dart:convert';

import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/task_system/task_plan_builder.dart';
import 'package:hermes/core/services/task_system/task_view_service.dart';

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
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.legacyWriteAccess = false,
    this.requiredArtifacts = const [],
    this.requiredGates = const [],
    this.requiredEvidence = const [],
    this.requireDeclaredWriteBoundary = false,
    this.preserveCompletedStepsOnly = false,
    this.viewService = const TaskViewService(),
    DateTime? now,
  }) : builder = TaskPlanBuilder(
         task: task,
         maxSteps: maxSteps,
         projectGoal: projectGoal,
         doneCriteria: doneCriteria,
         outOfScope: outOfScope,
         readPaths: readPaths,
         writePaths: writePaths,
         legacyWriteAccess: legacyWriteAccess,
         requiredArtifacts: requiredArtifacts,
         requiredGates: requiredGates,
         requiredEvidence: requiredEvidence,
         requireDeclaredWriteBoundary: requireDeclaredWriteBoundary,
         preserveCompletedStepsOnly: preserveCompletedStepsOnly,
         now: now,
       );

  final Task task;
  final String workspaceRoot;
  final int maxSteps;
  final String projectGoal;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> readPaths;
  final List<String> writePaths;
  final bool legacyWriteAccess;
  final List<TaskArtifact> requiredArtifacts;
  final List<TaskGate> requiredGates;
  final List<TaskProjectEvidenceExpectation> requiredEvidence;
  final bool requireDeclaredWriteBoundary;
  final bool preserveCompletedStepsOnly;
  final TaskViewService viewService;
  final TaskPlanBuilder builder;

  Task? committedTask;
  String? replanReason;
  bool closed = false;
}

class TaskPlanningToolRegistry {
  TaskPlanningToolRegistry({required this.context});

  final TaskPlanningToolContext context;
  final Map<String, _AppliedTaskCommand> _commands = {};

  List<ToolDefinition> get toolDefinitions => const [
    _taskViewDefinition,
    _setBriefDefinition,
    _addStepDefinition,
    _addCheckDefinition,
    _previewDefinition,
    _commitDefinition,
    _requestReplanDefinition,
    _requestDecisionDefinition,
  ];

  bool get allowsWorkspaceMutation => false;

  Future<String> execute(
    String toolId,
    String argumentsJson, {
    String? commandId,
  }) async {
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is! Map) {
        return jsonEncode(
          _error(
            code: 'invalid_argument',
            path: 'arguments',
            message: 'Tool arguments must be a JSON object.',
          ),
        );
      }
      final arguments = <String, dynamic>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          return jsonEncode(
            _error(
              code: 'invalid_argument',
              path: 'arguments',
              message: 'Tool argument names must be strings.',
            ),
          );
        }
        arguments[entry.key as String] = entry.value;
      }
      return jsonEncode(await invoke(toolId, arguments, commandId: commandId));
    } on FormatException catch (error) {
      return jsonEncode(
        _error(
          code: 'invalid_argument',
          path: 'arguments',
          message: 'Malformed JSON arguments: ${error.message}',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> invoke(
    String toolId,
    Map<String, dynamic> arguments, {
    String? commandId,
  }) async {
    try {
      final key = commandId?.trim();
      final fingerprint = key == null || key.isEmpty
          ? null
          : jsonEncode({'tool': toolId, 'arguments': arguments});
      if (key != null && key.isNotEmpty) {
        final previous = _commands[key];
        if (previous != null) {
          if (previous.fingerprint != fingerprint) {
            throw _argument(
              'duplicate_command',
              'command',
              'Command $key was already used with different arguments.',
            );
          }
          return previous.result;
        }
      }
      final result = switch (toolId) {
        'task_view' => _view(arguments),
        'task_set_brief' => _setBrief(arguments),
        'task_add_step' => _addStep(arguments, commandId),
        'task_add_check' => _addCheck(arguments, commandId),
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
      final response = {'ok': true, ...result};
      if (key != null && key.isNotEmpty) {
        _commands[key] = _AppliedTaskCommand(fingerprint!, response);
      }
      return response;
    } on TaskPlanBuilderException catch (error) {
      return _error(code: error.code, path: error.path, message: error.message);
    } on TaskViewException catch (error) {
      return _error(code: error.code, path: error.path, message: error.message);
    } on _TaskPlanningArgumentException catch (error) {
      return _error(code: error.code, path: error.path, message: error.message);
    } catch (error) {
      return _error(
        code: 'planning_tool_failed',
        path: 'tool',
        message: 'The task planning command could not be applied: $error',
      );
    }
  }

  Map<String, dynamic> _view(Map<String, dynamic> arguments) {
    _keys(arguments, const {'step_ref', 'max_items'});
    final stepRef = _optionalString(arguments['step_ref'], 'step_ref');
    final preview = context.builder.preview();
    final view = context.viewService.query(
      context.preserveCompletedStepsOnly ? context.task : preview.task,
      stepRef: stepRef,
      maxItems: _optionalInt(arguments['max_items'], 'max_items'),
      maxSteps: context.maxSteps,
      projectGoal: context.projectGoal,
      doneCriteria: context.doneCriteria,
      outOfScope: context.outOfScope,
      readPaths: context.readPaths,
      writePaths: context.writePaths,
      legacyWriteAccess: context.legacyWriteAccess,
      requiredArtifacts: context.requiredArtifacts,
      requiredGates: context.requiredGates,
      requiredEvidence: context.requiredEvidence,
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

  Map<String, dynamic> _setBrief(Map<String, dynamic> arguments) {
    _ensureOpen();
    _keys(arguments, const {
      'title',
      'objective',
      'constraints',
      'success_criteria',
    });
    final title = _optionalString(arguments['title'], 'title');
    final objective = _optionalString(arguments['objective'], 'objective');
    final constraints = arguments.containsKey('constraints')
        ? _stringList(arguments['constraints'], 'constraints')
        : null;
    final successCriteria = arguments.containsKey('success_criteria')
        ? _stringList(arguments['success_criteria'], 'success_criteria')
        : null;
    if (title == null &&
        objective == null &&
        constraints == null &&
        successCriteria == null) {
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
      successCriteria: successCriteria,
    );
    return {
      'title': context.builder.preview().task.title,
      'objective': context.builder.preview().task.objective,
      'success_criteria': context.builder.preview().task.successCriteria,
    };
  }

  Map<String, dynamic> _addStep(
    Map<String, dynamic> arguments,
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
    });
    final ref = _optionalString(arguments['ref'], 'ref') ?? '';
    final title = _optionalString(arguments['title'], 'title') ?? '';
    final objective =
        _optionalString(arguments['objective'], 'objective') ?? '';
    final instructions = _stringList(arguments['instructions'], 'instructions');
    final artifacts = _artifacts(arguments['artifacts'], 'artifacts');
    final mayEditFiles =
        _optionalBool(arguments['may_edit_files'], 'may_edit_files') ?? false;
    final id = context.builder.addStep(
      TaskPlanStepSpec(
        ref: ref,
        title: title,
        objective: objective,
        instructions: instructions,
        mayEditFiles: mayEditFiles,
        artifacts: artifacts,
      ),
      commandId: commandId,
    );
    return {
      'step': {'id': id, 'ref': ref.trim().isEmpty ? id : ref.trim()},
    };
  }

  Map<String, dynamic> _addCheck(
    Map<String, dynamic> arguments,
    String? commandId,
  ) {
    _ensureOpen();
    _keys(arguments, const {
      'step_ref',
      'command',
      'working_directory',
      'required',
      'description',
    });
    final stepRef = _optionalString(arguments['step_ref'], 'step_ref');
    final id = context.builder.addCheck(
      stepReference: stepRef,
      command: _requiredString(arguments['command'], 'command'),
      workingDirectory:
          _optionalString(
            arguments['working_directory'],
            'working_directory',
          ) ??
          '.',
      required: _optionalBool(arguments['required'], 'required') ?? true,
      description: _optionalString(arguments['description'], 'description'),
      commandId: commandId,
    );
    return {
      'check': {'expectation_id': id, 'step_ref': stepRef},
    };
  }

  Map<String, dynamic> _preview(Map<String, dynamic> arguments) {
    _ensureOpen();
    _keys(arguments, const {});
    final preview = context.builder.preview();
    return {
      'plan': _planSummary(preview.task),
      'issues': [for (final issue in preview.issues) issue.toMap()],
    };
  }

  Map<String, dynamic> _commit(Map<String, dynamic> arguments) {
    _ensureOpen();
    _keys(arguments, const {});
    final committed = context.builder.commit();
    final response = {
      'plan': _planSummary(committed.task),
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

  Map<String, dynamic> _requestReplan(Map<String, dynamic> arguments) {
    _ensureOpen();
    _keys(arguments, const {'reason'});
    final reason = _requiredString(arguments['reason'], 'reason');
    context.builder.requestReplan(reason);
    context.replanReason = reason;
    return {'reason': reason};
  }

  Map<String, dynamic> _requestDecision(
    Map<String, dynamic> arguments,
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
      'question': {'id': id, 'step_ref': stepRef},
    };
  }

  Map<String, dynamic> _planSummary(Task task) => {
    'task_id': task.id,
    'title': task.title,
    'objective': task.objective,
    'step_count': task.steps.length,
    'next_step_ref': task.currentStepId,
    'status': task.status.wire,
    'checks': [
      for (final gate in task.gates)
        {'kind': gate.id, 'scope': gate.scope, 'required': gate.required},
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

  void _rejectPersistentFields(Map<String, dynamic> value, String fieldPath) {
    const forbidden = {
      'id',
      'step_id',
      'stepId',
      'status',
      'created_at',
      'createdAt',
      'updated_at',
      'updatedAt',
      'run_id',
      'runId',
      'runs',
      'gates',
      'expected_evidence',
      'expectedEvidence',
      'current_step_id',
      'currentStepId',
      'failure',
      'completed_at',
      'completedAt',
    };
    for (final field in forbidden) {
      if (value.containsKey(field)) {
        throw _argument(
          'invalid_argument',
          '$fieldPath.$field',
          'Planning commands generate persistent fields; $field is not accepted.',
        );
      }
    }
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
    Map<String, dynamic> value,
    Set<String> allowed, {
    String fieldPath = 'arguments',
  }) {
    for (final key in value.keys) {
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

class _AppliedTaskCommand {
  final String fingerprint;
  final Map<String, dynamic> result;

  const _AppliedTaskCommand(this.fingerprint, this.result);
}

class _TaskPlanningArgumentException implements Exception {
  final String code;
  final String path;
  final String message;

  const _TaskPlanningArgumentException(this.code, this.path, this.message);
}

const ToolDefinition _taskViewDefinition = ToolDefinition(
  id: 'task_view',
  name: 'View task plan',
  description:
      'Inspect a bounded task summary, its step statuses, boundaries, and required checks.',
  schema: {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'step_ref': {'type': 'string'},
      'max_items': {'type': 'integer', 'minimum': 1},
    },
  },
);

const ToolDefinition _setBriefDefinition = ToolDefinition(
  id: 'task_set_brief',
  name: 'Set task brief',
  description:
      'Refine the task title, objective, constraints, or success criteria.',
  schema: {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'constraints': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'success_criteria': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
  },
);

const ToolDefinition _addStepDefinition = ToolDefinition(
  id: 'task_add_step',
  name: 'Add task step',
  description:
      'Add one independently executable step. Hermes generates its persistent ID.',
  schema: {
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
      'may_edit_files': {'type': 'boolean'},
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
              'description':
                  'Use directory for a directory output; file is the default.',
            },
          },
          'required': ['path'],
        },
      },
    },
    'required': ['title', 'objective', 'instructions'],
  },
);

const ToolDefinition _addCheckDefinition = ToolDefinition(
  id: 'task_add_check',
  name: 'Add task check',
  description:
      'Add an exact verification command to the task or one step. Hermes creates the gate and evidence ID.',
  schema: {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'step_ref': {'type': 'string'},
      'command': {'type': 'string'},
      'working_directory': {'type': 'string'},
      'required': {'type': 'boolean'},
      'description': {'type': 'string'},
    },
    'required': ['command'],
  },
);

const ToolDefinition _previewDefinition = ToolDefinition(
  id: 'task_preview_plan',
  name: 'Preview task plan',
  description: 'Validate the current task draft without committing it.',
  schema: {'type': 'object', 'additionalProperties': false, 'properties': {}},
);

const ToolDefinition _commitDefinition = ToolDefinition(
  id: 'task_commit_plan',
  name: 'Commit task plan',
  description: 'Validate and finish the task plan draft.',
  schema: {'type': 'object', 'additionalProperties': false, 'properties': {}},
);

const ToolDefinition _requestReplanDefinition = ToolDefinition(
  id: 'task_request_replan',
  name: 'Request task replan',
  description: 'Record a concrete reason why unfinished work needs replanning.',
  schema: {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'reason': {'type': 'string'},
    },
    'required': ['reason'],
  },
);

const ToolDefinition _requestDecisionDefinition = ToolDefinition(
  id: 'task_request_user_decision',
  name: 'Request user decision',
  description: 'Ask one genuinely blocking user question.',
  schema: {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'question': {'type': 'string'},
      'step_ref': {'type': 'string'},
    },
    'required': ['question'],
  },
);
