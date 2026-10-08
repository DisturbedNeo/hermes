import 'dart:convert';

import 'package:hermes/core/uuid.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/workspace/application/terminal_command_classifier.dart';

/// A compact validation issue returned by the task planning tools.
class TaskPlanIssue {
  final String code;
  final String path;
  final String message;

  const TaskPlanIssue({
    required this.code,
    required this.path,
    required this.message,
  });

  Map<String, dynamic> toMap() => {
    'code': code,
    'path': path,
    'message': message,
  };
}

class TaskPlanBuilderException implements Exception {
  final String code;
  final String path;
  final String message;

  const TaskPlanBuilderException({
    required this.code,
    required this.path,
    required this.message,
  });

  @override
  String toString() => '$code${path.isEmpty ? '' : ' ($path)'}: $message';
}

/// The model-facing shape of one task step.
///
/// Persistent IDs, statuses, timestamps, run history, and gate/evidence IDs
/// are deliberately absent. Hermes adds those values when the command is
/// applied.
class TaskPlanStepSpec {
  final String ref;
  final String title;
  final String objective;
  final List<String> instructions;
  final bool mayEditFiles;
  final List<TaskArtifact> artifacts;
  final List<String> acceptanceRefs;

  const TaskPlanStepSpec({
    this.ref = '',
    this.title = '',
    this.objective = '',
    this.instructions = const [],
    this.mayEditFiles = false,
    this.artifacts = const [],
    this.acceptanceRefs = const [],
  });
}

class TaskPlanBuilderPreview {
  final TaskAggregate task;
  final List<TaskPlanIssue> issues;

  const TaskPlanBuilderPreview({required this.task, required this.issues});

  bool get valid => issues.isEmpty;
}

class TaskPlanBuilderCommit {
  final TaskAggregate task;
  final List<TaskPlanIssue> issues;

  const TaskPlanBuilderCommit({required this.task, required this.issues});

  bool get valid => issues.isEmpty;
}

/// Builds an executable task plan without accepting model-authored runtime
/// state. The source task is never mutated; a service persists the committed
/// result after the command loop succeeds.
class TaskPlanBuilder {
  TaskPlanBuilder({
    required TaskAggregate task,
    required this.maxSteps,
    this.projectGoal = '',
    this.outOfScope = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.acceptance = const [],
    this.requireDeclaredWriteBoundary = false,
    this.preserveCompletedStepsOnly = false,
    DateTime? now,
  }) : _source = task,
       _now = now ?? DateTime.now(),
       _title = task.title,
       _objective = task.objective,
       _constraints = [...task.constraints],
       _steps = [
         for (final step in task.steps)
           if (!preserveCompletedStepsOnly || _isPreserved(step)) step,
       ],
       _acceptance = [...task.acceptance, ...acceptance] {
    if (maxSteps < 1) {
      throw const TaskPlanBuilderException(
        code: 'invalid_step_limit',
        path: 'max_steps',
        message: 'A task plan must allow at least one step.',
      );
    }
    for (final step in _steps) {
      _stepRefs[step.id] = step.id;
    }
  }

  final TaskAggregate _source;
  final int maxSteps;
  final String projectGoal;
  final List<String> outOfScope;
  final List<String> readPaths;
  final List<String> writePaths;
  final List<AcceptanceItem> acceptance;
  final bool requireDeclaredWriteBoundary;
  final bool preserveCompletedStepsOnly;
  final DateTime _now;
  final List<TaskStep> _steps;
  final List<AcceptanceItem> _acceptance;
  String _title;
  String _objective;
  List<String> _constraints;
  String? _replanReason;
  PendingTaskQuestion? _pendingQuestion;

  TaskAggregate get source => _source;
  List<TaskStep> get steps => List.unmodifiable(_steps);

  /// Resolves a model-facing temporary step reference to the generated
  /// persistent step ID in the current draft.
  ///
  /// A null result means the reference is not part of this draft. Commands
  /// that require a step continue to use [_stepFor] so they retain their
  /// structured unknown-reference error.
  String? stepIdFor(String reference) {
    final key = reference.trim();
    if (key.isEmpty) return null;
    return _stepRefs[key] ??
        _steps.where((step) => step.id == key).firstOrNull?.id;
  }

  void setBrief({
    String? title,
    String? objective,
    List<String>? constraints,
  }) {
    if (title != null) _title = title.trim();
    if (objective != null) _objective = objective.trim();
    if (constraints != null) _constraints = _cleanStrings(constraints);
  }

  /// Clears the current uncommitted draft while retaining work that must
  /// survive a replan. This lets the planner replace an invalid draft using
  /// the same command protocol instead of sending a whole replacement plan.
  bool resetDraft({String? commandId}) {
    const fingerprint = '{"op":"reset_draft"}';
    return _idempotent(commandId, fingerprint, () {
      final preserved = _steps.where(_isPreserved).toList();
      _steps
        ..clear()
        ..addAll(preserved);
      _stepRefs
        ..clear()
        ..addEntries([
          for (final step in preserved) MapEntry(step.id, step.id),
        ]);
      _acceptance
        ..clear()
        ..addAll(_source.acceptance);
      _title = _source.title;
      _objective = _source.objective;
      _constraints = [..._source.constraints];
      _replanReason = null;
      _pendingQuestion = null;
      return true;
    });
  }

  String addStep(TaskPlanStepSpec spec, {String? commandId}) {
    final fingerprint = _encode({
      'op': 'add_step',
      'ref': spec.ref.trim(),
      'title': spec.title.trim(),
      'objective': spec.objective.trim(),
      'instructions': spec.instructions,
      'mayEditFiles': spec.mayEditFiles,
      'artifacts': [
        for (final artifact in spec.artifacts)
          {
            'path': artifact.path,
            'description': artifact.description,
            'kind': artifact.kind,
          },
      ],
      'acceptanceRefs': spec.acceptanceRefs,
    });
    return _idempotent(commandId, fingerprint, () {
      if (_steps.length >= maxSteps) {
        throw _error(
          'step_limit',
          'steps',
          'This task allows at most $maxSteps steps; combine or simplify the remaining work.',
        );
      }
      final objective = spec.objective.trim().isEmpty
          ? spec.title.trim()
          : spec.objective.trim();
      if (objective.isEmpty) {
        throw _error(
          'missing_objective',
          'objective',
          'A step needs an objective or title.',
        );
      }
      final title = spec.title.trim().isEmpty ? objective : spec.title.trim();
      final ref = _claimReference(spec.ref, title);
      final id = _newId('step', {for (final step in _steps) step.id});
      final artifacts = _normaliseArtifacts(spec.artifacts, id);
      if (requireDeclaredWriteBoundary &&
          spec.mayEditFiles &&
          writePaths.isEmpty) {
        throw _error(
          'missing_write_boundary',
          'may_edit_files',
          'A file-editing step needs declared task write paths.',
        );
      }
      for (var index = 0; index < artifacts.length; index++) {
        _validateArtifactPath(artifacts[index].path, 'artifacts[$index].path');
      }
      final acceptanceRefs = _cleanStrings(spec.acceptanceRefs);
      if (acceptanceRefs.length != acceptanceRefs.toSet().length) {
        throw _error(
          'duplicate_acceptance_attachment',
          'acceptance_refs',
          'An acceptance ref may appear only once on a step.',
        );
      }
      final attachedRefs = {for (final step in _steps) ...step.acceptanceRefs};
      for (final acceptanceRef in acceptanceRefs) {
        if (!_acceptance.any((item) => item.ref == acceptanceRef)) {
          throw _error(
            'unknown_acceptance_ref',
            'acceptance_refs',
            'Acceptance ref $acceptanceRef does not exist in this task.',
          );
        }
        if (attachedRefs.contains(acceptanceRef)) {
          throw _error(
            'duplicate_acceptance_attachment',
            'acceptance_refs',
            'Acceptance ref $acceptanceRef is already attached to another step.',
          );
        }
      }
      _steps.add(
        TaskStep(
          id: id,
          title: title,
          objective: objective,
          instructions: _cleanStrings(spec.instructions),
          mayEditFiles: spec.mayEditFiles,
          artifacts: artifacts,
          acceptanceRefs: acceptanceRefs,
          status: TaskStepStatus.pending,
        ),
      );
      _stepRefs[ref] = id;
      _stepRefs[id] = id;
      return id;
    });
  }

  String addAcceptance({required AcceptanceItem item, String? commandId}) {
    final normalized = AcceptanceItem(
      ref: item.ref.trim(),
      statement: item.statement.trim(),
      criterionIds: _cleanStrings(item.criterionIds),
      verifiers: item.verifiers,
    );
    final fingerprint = _encode({
      'op': 'add_acceptance',
      'ref': normalized.ref,
      'statement': normalized.statement,
      'criterionIds': normalized.criterionIds,
      'verifiers': [
        for (final verifier in normalized.verifiers)
          {
            'kind': verifier.kind.name,
            'required': verifier.required,
            'command': verifier.command,
            'workingDirectory': verifier.workingDirectory,
            'path': verifier.path,
            'artifactKind': verifier.artifactKind,
            'description': verifier.description,
          },
      ],
    });
    return _idempotent(commandId, fingerprint, () {
      _validateAcceptance(normalized, 'acceptance');
      if (_acceptance.any((existing) => existing.ref == normalized.ref)) {
        throw _error(
          'duplicate_acceptance_ref',
          'acceptance.ref',
          'Acceptance ref ${normalized.ref} already exists.',
        );
      }
      _acceptance.add(normalized);
      return normalized.ref;
    });
  }

  void requestReplan(String reason, {String? commandId}) {
    final text = reason.trim();
    final fingerprint = _encode({'op': 'request_replan', 'reason': text});
    _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'missing_reason',
          'reason',
          'A replan request needs a concrete reason.',
        );
      }
      _replanReason = text;
    });
  }

  String requestUserDecision({
    required String question,
    String? stepReference,
    String? commandId,
  }) {
    final text = question.trim();
    final fingerprint = _encode({
      'op': 'request_user_decision',
      'question': text,
      'step': stepReference?.trim(),
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'empty_question',
          'question',
          'A user decision needs a non-empty question.',
        );
      }
      final stepId = stepReference == null || stepReference.trim().isEmpty
          ? _steps.firstOrNull?.id ?? 'planning'
          : _stepFor(stepReference).id;
      _pendingQuestion = PendingTaskQuestion(
        id: _newId('question', const {}),
        stepId: stepId,
        question: text,
        createdAt: _now,
      );
      return _pendingQuestion!.id;
    });
  }

  TaskPlanBuilderPreview preview() {
    final task = _materialize();
    return TaskPlanBuilderPreview(task: task, issues: _validate(task));
  }

  TaskPlanBuilderCommit commit() {
    final task = _materialize();
    return TaskPlanBuilderCommit(task: task, issues: _validate(task));
  }

  final Map<String, String> _stepRefs = {};
  final Map<String, _AppliedCommand> _commands = {};

  TaskAggregate _materialize() {
    final nextStep = _nextStepId(_steps);
    final hasQuestion = _pendingQuestion != null;
    final status = hasQuestion
        ? TaskStatus.blocked
        : nextStep == null
        ? TaskStatus.completed
        : TaskStatus.paused;
    return _source.copyWith(
      title: _title.trim().isEmpty ? _source.title : _title.trim(),
      objective: _objective.trim().isEmpty ? _source.objective : _objective,
      constraints: _constraints,
      // Preserve duplicate refs so preview/commit can report the contract
      // violation instead of silently replacing one planner item with another.
      acceptance: [..._acceptance],
      fingerprint: _fingerprintWithAcceptance(),
      steps: [..._steps],
      status: status,
      currentStepId: nextStep,
      memorySummary: [
        _source.memorySummary,
        if (_replanReason != null) 'Replan request: $_replanReason',
      ].where((item) => item.trim().isNotEmpty).join('\n\n'),
      pendingApproval: null,
      pendingQuestion: _pendingQuestion,
      failure: null,
      rejectionReason: null,
      completedAt: status == TaskStatus.completed ? _now : null,
      updatedAt: _now,
    );
  }

  List<TaskPlanIssue> _validate(TaskAggregate task) {
    final issues = <TaskPlanIssue>[];
    final acceptanceRefs = <String>{};
    final attachedAcceptanceRefs = <String, String>{};
    for (var index = 0; index < task.acceptance.length; index++) {
      final item = task.acceptance[index];
      try {
        _validateAcceptance(item, 'acceptance[$index]');
      } on TaskPlanBuilderException catch (error) {
        issues.add(
          TaskPlanIssue(
            code: error.code,
            path: error.path,
            message: error.message,
          ),
        );
      }
      if (!acceptanceRefs.add(item.ref)) {
        issues.add(
          TaskPlanIssue(
            code: 'duplicate_acceptance_ref',
            path: 'acceptance[$index].ref',
            message: 'Acceptance ref ${item.ref} is duplicated.',
          ),
        );
      }
    }
    if (task.acceptance.isEmpty) {
      issues.add(
        const TaskPlanIssue(
          code: 'missing_acceptance',
          path: 'acceptance',
          message: 'A task plan needs at least one acceptance item.',
        ),
      );
    }
    final sourceHasUnfinishedSteps = _source.steps.any(
      (step) => !_isPreserved(step),
    );
    if (preserveCompletedStepsOnly &&
        sourceHasUnfinishedSteps &&
        task.steps.length == _source.steps.where(_isPreserved).length) {
      issues.add(
        const TaskPlanIssue(
          code: 'missing_replacement_steps',
          path: 'steps',
          message: 'A replan must add replacement work for unfinished steps.',
        ),
      );
    }
    if (task.steps.isEmpty) {
      issues.add(
        const TaskPlanIssue(
          code: 'missing_steps',
          path: 'steps',
          message: 'A task plan needs at least one executable step.',
        ),
      );
    }
    if (task.steps.length > maxSteps) {
      issues.add(
        TaskPlanIssue(
          code: 'step_limit',
          path: 'steps',
          message: 'The task has ${task.steps.length} steps; max is $maxSteps.',
        ),
      );
    }
    if (_normalise(task.objective) == _normalise(projectGoal) &&
        projectGoal.trim().isNotEmpty) {
      issues.add(
        const TaskPlanIssue(
          code: 'project_scope_expansion',
          path: 'objective',
          message: 'The task objective must not expand to the whole project.',
        ),
      );
    }
    final lowerOutOfScope = outOfScope
        .map(_normalise)
        .where((item) => item.isNotEmpty)
        .toList();
    for (var index = 0; index < task.steps.length; index++) {
      final step = task.steps[index];
      final text = _normalise('${step.title} ${step.objective}');
      if (_looksLikeWholeProject(text, projectGoal)) {
        issues.add(
          TaskPlanIssue(
            code: 'project_scope_expansion',
            path: 'steps[$index].objective',
            message: 'Step ${step.id} appears to target the whole project.',
          ),
        );
      }
      if (lowerOutOfScope.any(
        (boundary) => boundary.isNotEmpty && text.contains(boundary),
      )) {
        issues.add(
          TaskPlanIssue(
            code: 'out_of_scope_work',
            path: 'steps[$index].objective',
            message: 'Step ${step.id} conflicts with an out-of-scope boundary.',
          ),
        );
      }
      if (requireDeclaredWriteBoundary &&
          step.mayEditFiles &&
          writePaths.isEmpty) {
        issues.add(
          TaskPlanIssue(
            code: 'missing_write_boundary',
            path: 'steps[$index].may_edit_files',
            message: 'File-editing steps require declared task write paths.',
          ),
        );
      }
      for (
        var artifactIndex = 0;
        artifactIndex < step.artifacts.length;
        artifactIndex++
      ) {
        try {
          _validateArtifactPath(
            step.artifacts[artifactIndex].path,
            'steps[$index].artifacts[$artifactIndex].path',
          );
        } on TaskPlanBuilderException catch (error) {
          issues.add(
            TaskPlanIssue(
              code: error.code,
              path: error.path,
              message: error.message,
            ),
          );
        }
      }
      for (final ref in step.acceptanceRefs) {
        if (!acceptanceRefs.contains(ref)) {
          issues.add(
            TaskPlanIssue(
              code: 'unknown_acceptance_ref',
              path: 'steps[$index].acceptance_refs',
              message: 'Step ${step.id} references unknown acceptance $ref.',
            ),
          );
        } else {
          final previousStep = attachedAcceptanceRefs[ref];
          if (previousStep != null && previousStep != step.id) {
            issues.add(
              TaskPlanIssue(
                code: 'duplicate_acceptance_attachment',
                path: 'steps[$index].acceptance_refs',
                message:
                    'Acceptance $ref is attached to both $previousStep and ${step.id}.',
              ),
            );
          } else {
            attachedAcceptanceRefs[ref] = step.id;
          }
        }
      }
    }
    return issues;
  }

  String _fingerprintWithAcceptance() {
    final base = _source.fingerprint.trim().isEmpty
        ? _objective.trim().toLowerCase()
        : _source.fingerprint;
    return '$base|acceptance:${_encode([
      for (final item in _acceptance) {
          'ref': item.ref,
          'statement': item.statement,
          'criterionIds': item.criterionIds,
          'verifiers': [
            for (final verifier in item.verifiers) {'kind': verifier.kind.name, 'required': verifier.required, 'command': verifier.command, 'workingDirectory': verifier.workingDirectory, 'path': verifier.path, 'artifactKind': verifier.artifactKind, 'description': verifier.description},
          ],
        },
    ])}';
  }


  TaskStep _stepFor(String reference) {
    final key = reference.trim();
    final id = stepIdFor(key);
    if (id == null) {
      throw _error(
        'unknown_reference',
        'step',
        'Step reference $key does not exist in this draft.',
      );
    }
    return _steps.firstWhere((step) => step.id == id);
  }

  String _claimReference(String value, String fallback) {
    final reference = value.trim().isEmpty ? _slug(fallback) : value.trim();
    if (reference.isEmpty) {
      throw _error(
        'missing_reference',
        'ref',
        'A step needs a non-empty reference or title.',
      );
    }
    if (_stepRefs.containsKey(reference)) {
      throw _error(
        'duplicate_reference',
        'ref',
        'Step reference $reference already exists in this draft.',
      );
    }
    return reference;
  }

  List<TaskArtifact> _normaliseArtifacts(
    Iterable<TaskArtifact> artifacts,
    String stepId,
  ) {
    final used = {
      for (final step in _steps)
        for (final artifact in step.artifacts)
          if (artifact.id.trim().isNotEmpty) artifact.id,
    };
    return [
      for (final artifact in artifacts)
        artifact.copyWith(
          id: _newId('artifact', used),
          taskId: _source.id,
          stepId: stepId,
          createdAt: artifact.createdAt ?? _now,
        ),
    ];
  }

  void _validateArtifactPath(String value, String fieldPath) {
    final artifactPath = value.trim();
    if (artifactPath.isEmpty) {
      throw _error(
        'missing_artifact_path',
        fieldPath,
        'An artifact needs a workspace-relative path.',
      );
    }
    if (artifactPath.startsWith('/') || artifactPath.contains('..')) {
      throw _error(
        'invalid_artifact_path',
        fieldPath,
        'Artifact paths must remain inside the workspace.',
      );
    }
    final taskPrefix = '.agent/tasks/${_source.id}/';
    final insideTaskFolder = artifactPath.startsWith(taskPrefix);
    final insideDeclaredWritePath = writePaths.any(
      (allowed) =>
          artifactPath == allowed ||
          artifactPath.startsWith('${allowed.replaceAll(RegExp(r'/+$'), '')}/'),
    );
    if (!insideTaskFolder &&
        !insideDeclaredWritePath &&
        writePaths.isNotEmpty) {
      throw _error(
        'undeclared_write_path',
        fieldPath,
        'Artifact path $artifactPath is outside the declared write paths.',
      );
    }
  }

  void _validateAcceptance(AcceptanceItem item, String fieldPath) {
    if (item.ref.trim().isEmpty) {
      throw _error(
        'missing_acceptance_ref',
        '$fieldPath.ref',
        'Acceptance refs must be non-empty.',
      );
    }
    if (item.statement.trim().isEmpty) {
      throw _error(
        'missing_acceptance_statement',
        '$fieldPath.statement',
        'Acceptance statements must be non-empty.',
      );
    }
    if (item.verifiers.isEmpty) {
      throw _error(
        'missing_acceptance_verifier',
        '$fieldPath.verifiers',
        'Each acceptance item needs at least one verifier.',
      );
    }
    if (!item.verifiers.any((verifier) => verifier.required)) {
      throw _error(
        'missing_required_verifier',
        '$fieldPath.verifiers',
        'Each acceptance item needs at least one required verifier.',
      );
    }
    for (var index = 0; index < item.verifiers.length; index++) {
      final verifier = item.verifiers[index];
      if (!verifier.hasConfiguration) {
        throw _error(
          'invalid_acceptance_verifier',
          '$fieldPath.verifiers[$index]',
          'The verifier does not contain the fields required for its kind.',
        );
      }
      if (verifier.kind == AcceptanceVerifierKind.command) {
        _throwIfCommandBlocked(verifier.command!.trim());
      }
      if (verifier.kind == AcceptanceVerifierKind.artifact) {
        _validateArtifactPath(
          verifier.path!,
          '$fieldPath.verifiers[$index].path',
        );
      }
    }
  }

  String? _nextStepId(List<TaskStep> steps) {
    for (final step in steps) {
      if (step.status == TaskStepStatus.pending ||
          step.status == TaskStepStatus.approved ||
          step.status == TaskStepStatus.blocked ||
          step.status == TaskStepStatus.failed) {
        return step.id;
      }
    }
    return null;
  }

  void _throwIfCommandBlocked(String command) {
    final reason = TerminalCommandClassifier.blockedReasonForCommand(command);
    if (reason == null) return;
    throw _error(
      'blocked_command',
      'command',
      'Verification command is rejected by terminal policy: $reason',
    );
  }

  bool _looksLikeWholeProject(String value, String goal) {
    final normalised = _normalise(value);
    final project = _normalise(goal);
    if (project.isNotEmpty && normalised == project) return true;
    return normalised.contains('entire project') ||
        normalised.contains('whole project') ||
        normalised.contains('complete the project') ||
        normalised.contains('finish the project');
  }

  static bool _isPreserved(TaskStep step) =>
      step.status == TaskStepStatus.completed ||
      step.status == TaskStepStatus.skipped;

  static String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<String> _cleanStrings(Iterable<String> values) => [
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  ];

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.length > 48 ? slug.substring(0, 48) : slug;
  }

  static String _newId(String prefix, Set<String> used) {
    String id;
    do {
      id = '${prefix}_${uuid.v7()}';
    } while (!used.add(id));
    return id;
  }

  T _idempotent<T>(
    String? commandId,
    String fingerprint,
    T Function() callback,
  ) {
    final key = commandId?.trim();
    if (key == null || key.isEmpty) return callback();
    final previous = _commands[key];
    if (previous != null) {
      if (previous.fingerprint != fingerprint) {
        throw _error(
          'duplicate_command',
          'command',
          'Command $key was already used with different arguments.',
        );
      }
      return previous.result as T;
    }
    final result = callback();
    _commands[key] = _AppliedCommand(fingerprint, result as Object);
    return result;
  }

  static String _encode(Object? value) => jsonEncode(value);

  static TaskPlanBuilderException _error(
    String code,
    String path,
    String message,
  ) => TaskPlanBuilderException(code: code, path: path, message: message);
}

class _AppliedCommand {
  final String fingerprint;
  final Object result;

  const _AppliedCommand(this.fingerprint, this.result);
}
