import 'dart:convert';

import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/task.dart';

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

  const TaskPlanStepSpec({
    this.ref = '',
    this.title = '',
    this.objective = '',
    this.instructions = const [],
    this.mayEditFiles = false,
    this.artifacts = const [],
  });
}

class TaskPlanBuilderPreview {
  final Task task;
  final List<TaskPlanIssue> issues;

  const TaskPlanBuilderPreview({required this.task, required this.issues});

  bool get valid => issues.isEmpty;
}

class TaskPlanBuilderCommit {
  final Task task;
  final List<TaskPlanIssue> issues;

  const TaskPlanBuilderCommit({required this.task, required this.issues});

  bool get valid => issues.isEmpty;
}

/// Builds an executable task plan without accepting model-authored runtime
/// state. The source task is never mutated; a service persists the committed
/// result after the command loop succeeds.
class TaskPlanBuilder {
  TaskPlanBuilder({
    required Task task,
    required this.maxSteps,
    this.projectGoal = '',
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.requiredArtifacts = const [],
    this.requiredGates = const [],
    this.requiredEvidence = const [],
    this.requireDeclaredWriteBoundary = false,
    this.preserveCompletedStepsOnly = false,
    DateTime? now,
  }) : _source = task,
       _now = now ?? DateTime.now(),
       _title = task.title,
       _objective = task.objective,
       _constraints = [...task.constraints],
       _successCriteria = [...task.successCriteria],
       _steps = [
         for (final step in task.steps)
           if (!preserveCompletedStepsOnly || _isPreserved(step)) step,
       ],
       _taskGates = [...task.gates, ...requiredGates],
       _expectedEvidence = [...task.expectedEvidence] {
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
    _dedupeTaskGates();
    _ensureRequiredProjectChecks();
    _dedupeTaskGates();
  }

  final Task _source;
  final int maxSteps;
  final String projectGoal;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<String> readPaths;
  final List<String> writePaths;
  final List<TaskArtifact> requiredArtifacts;
  final List<TaskGate> requiredGates;
  final List<TaskProjectEvidenceExpectation> requiredEvidence;
  final bool requireDeclaredWriteBoundary;
  final bool preserveCompletedStepsOnly;
  final DateTime _now;
  final List<TaskStep> _steps;
  final List<TaskGate> _taskGates;
  final List<TaskEvidenceExpectation> _expectedEvidence;
  String _title;
  String _objective;
  List<String> _constraints;
  List<String> _successCriteria;
  String? _replanReason;
  PendingTaskQuestion? _pendingQuestion;

  Task get source => _source;
  List<TaskStep> get steps => List.unmodifiable(_steps);
  List<TaskGate> get taskGates => List.unmodifiable(_taskGates);

  void setBrief({
    String? title,
    String? objective,
    List<String>? constraints,
    List<String>? successCriteria,
  }) {
    if (title != null) _title = title.trim();
    if (objective != null) _objective = objective.trim();
    if (constraints != null) _constraints = _cleanStrings(constraints);
    if (successCriteria != null) {
      _successCriteria = _cleanStrings(successCriteria);
    }
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
      _taskGates
        ..clear()
        ..addAll([..._source.gates, ...requiredGates]);
      _expectedEvidence
        ..clear()
        ..addAll(_source.expectedEvidence);
      _title = _source.title;
      _objective = _source.objective;
      _constraints = [..._source.constraints];
      _successCriteria = [..._source.successCriteria];
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
      _steps.add(
        TaskStep(
          id: id,
          title: title,
          objective: objective,
          instructions: _cleanStrings(spec.instructions),
          mayEditFiles: spec.mayEditFiles,
          artifacts: artifacts,
          gates: _artifactGates(artifacts),
          status: TaskStepStatus.pending,
        ),
      );
      _stepRefs[ref] = id;
      _stepRefs[id] = id;
      return id;
    });
  }

  String addCheck({
    String? stepReference,
    required String command,
    String workingDirectory = '.',
    bool required = true,
    String? description,
    String? commandId,
  }) {
    final commandText = command.trim();
    final directory = workingDirectory.trim().isEmpty
        ? '.'
        : workingDirectory.trim();
    final fingerprint = _encode({
      'op': 'add_check',
      'step': stepReference?.trim(),
      'command': commandText,
      'workingDirectory': directory,
      'required': required,
      'description': description,
    });
    return _idempotent(commandId, fingerprint, () {
      if (commandText.isEmpty) {
        throw _error(
          'missing_command',
          'command',
          'A verification check needs a command.',
        );
      }
      final step = stepReference == null || stepReference.trim().isEmpty
          ? null
          : _stepFor(stepReference);
      // Copy task-level gates before clearing/replacing the backing list below.
      // Referencing _taskGates directly would make addCheck clear its own
      // source list and silently drop the newly added gate.
      final targetGates = step == null ? [..._taskGates] : [...step.gates];
      final gateIndex = targetGates.indexWhere(
        (gate) =>
            gate.id == 'command_passes' &&
            gate.params['command']?.toString() == commandText &&
            _workingDirectory(gate) == directory,
      );
      if (gateIndex < 0) {
        targetGates.add(
          TaskGate(
            id: 'command_passes',
            required: required,
            scope: step == null ? 'task' : 'step',
            params: {'command': commandText, 'working_directory': directory},
            description: description?.trim().isNotEmpty == true
                ? description!.trim()
                : 'The verification command passes.',
          ),
        );
      } else if (required && !targetGates[gateIndex].required) {
        final previous = targetGates[gateIndex];
        targetGates[gateIndex] = TaskGate(
          id: previous.id,
          required: true,
          scope: previous.scope,
          params: previous.params,
          description: previous.description,
        );
      }
      if (step == null) {
        _taskGates
          ..clear()
          ..addAll(targetGates);
      } else {
        final index = _steps.indexWhere((item) => item.id == step.id);
        _steps[index] = step.copyWith(gates: _dedupeGates(targetGates));
      }

      final existing = _expectedEvidence.where((expectation) {
        return expectation.type == ProjectEvidenceType.command &&
            expectation.sourceRef == commandText &&
            _workingDirectoryFromEvidence(expectation) == directory;
      }).firstOrNull;
      if (existing != null) {
        if (required && !existing.required) {
          final index = _expectedEvidence.indexOf(existing);
          _expectedEvidence[index] = TaskEvidenceExpectation(
            id: existing.id,
            type: existing.type,
            criterionIds: existing.criterionIds,
            description: existing.description,
            required: true,
            sourceRef: existing.sourceRef,
            details: existing.details,
          );
        }
        return existing.id;
      }
      final expectation = TaskEvidenceExpectation(
        id: _newId('expect', {for (final item in _expectedEvidence) item.id}),
        type: ProjectEvidenceType.command,
        description: description?.trim().isNotEmpty == true
            ? description!.trim()
            : 'The verification command passes.',
        required: required,
        sourceRef: commandText,
        details: {'working_directory': directory},
      );
      _expectedEvidence.add(expectation);
      return expectation.id;
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

  Task _materialize() {
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
      successCriteria: _successCriteria,
      gates: _dedupeGates([..._taskGates, ..._defaultTaskGates(_steps)]),
      expectedEvidence: _dedupeEvidence(_expectedEvidence),
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

  List<TaskPlanIssue> _validate(Task task) {
    final issues = <TaskPlanIssue>[];
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
    if (_successCriteria.isEmpty) {
      issues.add(
        const TaskPlanIssue(
          code: 'missing_success_criteria',
          path: 'success_criteria',
          message: 'A task plan needs at least one success criterion.',
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
    }
    for (final gate in requiredGates) {
      if (!_hasMatchingGate(task, gate)) {
        issues.add(
          TaskPlanIssue(
            code: 'missing_required_check',
            path: 'gates',
            message: 'Required check ${gate.id} is missing from the task.',
          ),
        );
      }
    }
    final declaredArtifacts = {
      for (final step in task.steps)
        for (final artifact in step.artifacts) artifact.path,
    };
    for (final artifact in requiredArtifacts) {
      if (artifact.path.trim().isEmpty ||
          declaredArtifacts.contains(artifact.path.trim())) {
        continue;
      }
      issues.add(
        TaskPlanIssue(
          code: 'missing_expected_artifact',
          path: 'steps',
          message:
              'Expected artifact ${artifact.path} must be declared on a step.',
        ),
      );
    }
    for (final expectation in requiredEvidence) {
      if (!expectation.required || expectation.type != 'command') continue;
      final command = expectation.sourceRef?.trim() ?? '';
      if (command.isEmpty) continue;
      final directory =
          expectation.details['working_directory']?.toString() ??
          expectation.details['workingDirectory']?.toString() ??
          '.';
      final hasCommand =
          [...task.gates, for (final step in task.steps) ...step.gates].any(
            (gate) =>
                gate.id == 'command_passes' &&
                gate.params['command']?.toString() == command &&
                _workingDirectory(gate) == directory,
          );
      if (!hasCommand) {
        issues.add(
          TaskPlanIssue(
            code: 'missing_required_check',
            path: 'gates',
            message: 'Required project command check "$command" is missing.',
          ),
        );
      }
    }
    return issues;
  }

  void _ensureRequiredProjectChecks() {
    for (final gate in requiredGates) {
      if (gate.id == 'command_passes') {
        final command = gate.params['command']?.toString().trim() ?? '';
        if (command.isEmpty) continue;
        final directory = _workingDirectory(gate);
        final matchingIndex = _taskGates.indexWhere(
          (item) =>
              item.id == 'command_passes' &&
              item.params['command']?.toString() == command &&
              _workingDirectory(item) == directory,
        );
        if (matchingIndex >= 0) {
          final existing = _taskGates[matchingIndex];
          if (gate.required && !existing.required) {
            _taskGates[matchingIndex] = TaskGate(
              id: existing.id,
              required: true,
              scope: existing.scope,
              params: existing.params,
              description: existing.description,
            );
          }
          continue;
        }
      }
      _taskGates.add(gate);
    }
  }

  List<TaskGate> _defaultTaskGates(Iterable<TaskStep> steps) {
    final mutating = steps.any((step) => step.mayEditFiles);
    final coding = _normalise('$_objective $_title')
        .split(' ')
        .any(
          (word) => const {
            'code',
            'test',
            'build',
            'bug',
            'fix',
            'implement',
            'refactor',
            'compile',
            'flutter',
            'dart',
            'api',
          }.contains(word),
        );
    if (!mutating && !coding) return const [];
    return const [
      TaskGate(
        id: 'no_tool_errors',
        required: true,
        scope: 'task',
        description: 'No unresolved fatal workspace tool errors.',
      ),
      TaskGate(
        id: 'no_failed_commands',
        required: true,
        scope: 'task',
        description: 'No failed terminal commands after workspace mutation.',
      ),
    ];
  }

  List<TaskGate> _artifactGates(List<TaskArtifact> artifacts) {
    final paths = [
      for (final artifact in artifacts)
        if (artifact.path.trim().isNotEmpty) artifact.path,
    ];
    if (paths.isEmpty) return const [];
    final filePaths = [
      for (final artifact in artifacts)
        if (artifact.path.trim().isNotEmpty &&
            artifact.kind.trim().toLowerCase() != 'directory')
          artifact.path,
    ];
    return [
      TaskGate(
        id: 'artifact_exists',
        required: true,
        scope: 'step',
        params: {'paths': paths},
        description: 'Declared artifacts must exist.',
      ),
      if (filePaths.isNotEmpty)
        TaskGate(
          id: 'artifact_nonempty',
          required: true,
          scope: 'step',
          params: {'paths': filePaths},
          description: 'Declared file artifacts must be non-empty.',
        ),
    ];
  }

  bool _hasMatchingGate(Task task, TaskGate required) {
    return task.gates.any((gate) {
      if (gate.id != required.id) {
        return false;
      }
      if (gate.id == 'command_passes') {
        return gate.params['command']?.toString() ==
                required.params['command']?.toString() &&
            _workingDirectory(gate) == _workingDirectory(required);
      }
      return _encode(gate.params) == _encode(required.params);
    });
  }

  void _dedupeTaskGates() {
    final deduped = _dedupeGates(_taskGates);
    _taskGates
      ..clear()
      ..addAll(deduped);
  }

  List<TaskGate> _dedupeGates(Iterable<TaskGate> gates) {
    final seen = <String>{};
    final result = <TaskGate>[];
    for (final gate in gates) {
      final params = Map<String, dynamic>.from(gate.params);
      if (gate.id == 'command_passes') {
        final directory = _workingDirectory(gate);
        params
          ..remove('workingDirectory')
          ..['working_directory'] = directory;
      }
      final key = _encode({
        'id': gate.id,
        'scope': gate.scope,
        'params': params,
      });
      if (seen.add(key)) {
        result.add(gate);
      } else if (gate.required) {
        final index = result.indexWhere(
          (existing) =>
              _encode({
                'id': existing.id,
                'scope': existing.scope,
                'params': existing.params,
              }) ==
              key,
        );
        if (index >= 0 && !result[index].required) {
          final existing = result[index];
          result[index] = TaskGate(
            id: existing.id,
            required: true,
            scope: existing.scope,
            params: existing.params,
            description: existing.description ?? gate.description,
          );
        }
      }
    }
    return result;
  }

  List<TaskEvidenceExpectation> _dedupeEvidence(
    Iterable<TaskEvidenceExpectation> expectations,
  ) {
    final seen = <String>{};
    final result = <TaskEvidenceExpectation>[];
    for (final expectation in expectations) {
      final key = _encode({
        'id': expectation.id,
        'type': expectation.type.name,
        'criterionIds': expectation.criterionIds,
        'source': expectation.sourceRef,
        'description': expectation.description,
        'required': expectation.required,
        'details': expectation.details,
      });
      if (seen.add(key)) result.add(expectation);
    }
    return result;
  }

  TaskStep _stepFor(String reference) {
    final key = reference.trim();
    final id =
        _stepRefs[key] ??
        _steps.where((step) => step.id == key).firstOrNull?.id;
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

  String _workingDirectory(TaskGate gate) =>
      gate.params['working_directory']?.toString() ??
      gate.params['workingDirectory']?.toString() ??
      '.';

  String _workingDirectoryFromEvidence(TaskEvidenceExpectation expectation) =>
      expectation.details['working_directory']?.toString() ??
      expectation.details['workingDirectory']?.toString() ??
      '.';

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
