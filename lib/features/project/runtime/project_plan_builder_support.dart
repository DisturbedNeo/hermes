part of 'project_plan_builder.dart';

extension ProjectPlanBuilderSupport on ProjectPlanBuilder {
  ProjectDesiredPlan _materialize() => ProjectDesiredPlan(
    revision: _project.nextRevision,
    triggers: [..._triggers],
    summary: _summary,
    rationale: _rationale,
    hasCompleteCollections: true,
    criteria: _criteria.values.toList(),
    milestones: _milestones.values.toList(),
    tasks: [
      for (final task in _tasks.values)
        if (!_splitTaskIds.contains(task.id)) task,
    ],
    splitTaskIds: _splitTaskIds.toList(),
    deferredTaskIds: _deferredTaskIds.toList(),
    obsoleteTaskIds: _obsoleteTaskIds.toList(),
    memoryAdditions: [..._memoryAdditions],
    workspaceGraph: ProjectWorkspaceGraph(
      orientation: _workspaceOrientation,
      nodes: _workspaceNodes.values.toList(),
      edges: _workspaceEdges.values.toList(),
      updatedAt: _now,
    ),
    openQuestions: [..._project.openQuestions, ..._openQuestions],
    requiresApproval: _requiresApproval,
    approvalReason: _approvalReason,
    createdAt: _now,
  );

  ProjectAggregate get _planningProject =>
      _project.copyWith(refinedGoal: _validationRefinedGoal);

  List<String> _addTasksInternal(List<ProjectTaskSpec> specs) {
    if (specs.isEmpty) {
      throw _error('missing_tasks', 'tasks', 'At least one task is required.');
    }
    if (_newTaskIds.length + specs.length > planningLimits.maxNewTasks) {
      throw _error(
        'new_task_limit_exceeded',
        'tasks',
        'This planning pass may add at most ${planningLimits.maxNewTasks} '
            'new task${planningLimits.maxNewTasks == 1 ? '' : 's'}.',
      );
    }
    final references = <String, String>{};
    final ids = <String>[];
    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      final reference = _claimReference(
        spec.ref,
        namespace: 'task',
        fallback: _slug(spec.title.isEmpty ? spec.objective : spec.title),
        additional: references.keys,
      );
      if (references.containsKey(reference)) {
        throw _error(
          'duplicate_reference',
          'tasks[$index].ref',
          'Task reference $reference already exists in this command.',
        );
      }
      final id = _newId('task', {..._taskCatalog.keys, ...ids});
      references[reference] = id;
      ids.add(id);
    }

    final created = <ProjectTaskNode>[];
    final reservedExpectationIds = <String>{};
    final reservedArtifactIds = <String>{};
    for (var index = 0; index < specs.length; index++) {
      final spec = specs[index];
      final id = ids[index];
      final objective = spec.objective.trim().isEmpty
          ? spec.title.trim()
          : spec.objective.trim();
      if (objective.isEmpty) {
        throw _error(
          'missing_objective',
          'tasks[$index].objective',
          'A task needs an objective or title.',
        );
      }
      final title = spec.title.trim().isEmpty ? objective : spec.title.trim();
      final criterionIds = _resolveReferences(
        spec.criterionRefs,
        _resolveCriterion,
        'tasks[$index].criterionRefs',
      );
      if (criterionIds.isEmpty) {
        throw _error(
          'missing_criterion_reference',
          'tasks[$index].criterionRefs',
          'A task must link to at least one criterion.',
        );
      }
      final dependencies = _resolveReferences(
        spec.dependencyRefs,
        (reference) => references[reference.trim()] ?? _resolveTask(reference),
        'tasks[$index].dependencyRefs',
      );
      for (final dependencyId in dependencies) {
        if (!references.values.contains(dependencyId)) {
          _ensureDependencyCanComplete(
            dependencyId,
            'tasks[$index].dependencyRefs',
          );
        }
      }
      final milestoneId =
          spec.milestoneRef == null || spec.milestoneRef!.trim().isEmpty
          ? null
          : _resolveMilestone(spec.milestoneRef!);
      final doneCriteria = _requiredList(
        spec.doneCriteria,
        'tasks[$index].doneCriteria',
      );
      final outOfScope = _requiredList(
        spec.outOfScope,
        'tasks[$index].outOfScope',
      );
      final expectedEvidence = TaskEvidenceExpectation(
        id: _newExpectationId(additional: reservedExpectationIds),
        type: ProjectEvidenceType.taskClaim,
        criterionIds: criterionIds,
        description: doneCriteria.join(' '),
      );
      reservedExpectationIds.add(expectedEvidence.id);
      final expectedArtifacts = _normaliseArtifacts(
        spec.expectedArtifacts,
        id,
        additionalIds: reservedArtifactIds,
      );
      reservedArtifactIds.addAll(
        expectedArtifacts.map((artifact) => artifact.id),
      );
      final task = ProjectTaskNode(
        id: id,
        title: title,
        objective: objective,
        constraints: _cleanStrings(spec.constraints),
        status: TaskStatus.queued,
        criterionIds: criterionIds,
        milestoneId: milestoneId,
        dependsOnTaskIds: dependencies,
        priority: spec.priority,
        risk: spec.risk,
        riskReduction: spec.riskReduction,
        effort: spec.effort,
        selectionRationale: spec.selectionRationale.trim(),
        expectedEvidence: [expectedEvidence],
        readPaths: _cleanStrings(spec.readPaths),
        writePaths: _cleanStrings(spec.writePaths),
        doneCriteria: doneCriteria,
        outOfScope: outOfScope,
        context: _cleanStrings(spec.context),
        expectedArtifacts: expectedArtifacts,
        fingerprint: projectTaskFingerprint(objective, criterionIds),
        createdAt: _now,
        updatedAt: _now,
      );
      created.add(task);
    }
    for (var index = 0; index < created.length; index++) {
      final task = created[index];
      _tasks[task.id] = task;
      _taskCatalog[task.id] = task;
      _newTaskIds.add(task.id);
      final reference = references.keys.elementAt(index);
      _taskRefs[reference] = task.id;
      _taskRefs[task.id] = task.id;
    }
    _ensureNoCycles();
    return ids;
  }

  ProjectTaskNode _editableTask(String id) {
    final task = _tasks[id];
    if (task == null) {
      final known = _taskCatalog[id];
      if (known != null && _isTerminal(known)) {
        throw _error(
          'terminal_task_immutable',
          'task',
          'Terminal task $id cannot be changed by a draft.',
        );
      }
      throw _error('unknown_task', 'task', 'Task $id is not mutable.');
    }
    if (_splitTaskIds.contains(id)) {
      throw _error(
        'split_task_immutable',
        'task',
        'Task $id has already been split in this draft.',
      );
    }
    if (task.status == TaskStatus.running) {
      throw _error(
        'active_task_immutable',
        'task',
        'The running task $id cannot be changed by a draft.',
      );
    }
    if (_isTerminal(task)) {
      throw _error(
        'terminal_task_immutable',
        'task',
        'Terminal task $id cannot be changed by a draft.',
      );
    }
    return task;
  }

  String _resolveTask(String reference) {
    final key = reference.trim();
    final id = _taskRefs[key];
    if (id == null) {
      throw _error(
        'unknown_reference',
        'task',
        'Task reference $reference does not exist.',
      );
    }
    return id;
  }

  String _resolveCriterion(String reference) {
    final key = reference.trim();
    final id = _criterionRefs[key];
    if (id == null) {
      throw _error(
        'unknown_reference',
        'criterion',
        'Criterion reference $reference does not exist.',
      );
    }
    return id;
  }

  String _resolveMilestone(String reference) {
    final key = reference.trim();
    final id = _milestoneRefs[key];
    if (id == null) {
      throw _error(
        'unknown_reference',
        'milestone',
        'Milestone reference $reference does not exist.',
      );
    }
    return id;
  }

  String _resolveWorkspaceNode(String reference) {
    final key = reference.trim();
    final id = _workspaceNodeRefs[key];
    if (id == null || !_workspaceNodes.containsKey(id)) {
      throw _error(
        'unknown_reference',
        'workspace_node',
        'Workspace node reference $reference does not exist.',
      );
    }
    return id;
  }

  String _resolveWorkspaceEdge(String reference) {
    final key = reference.trim();
    final id = _workspaceEdgeRefs[key];
    if (id == null || !_workspaceEdges.containsKey(id)) {
      throw _error(
        'unknown_reference',
        'workspace_edge',
        'Workspace edge reference $reference does not exist.',
      );
    }
    return id;
  }

  String _claimWorkspaceReference(
    String reference, {
    required String namespace,
    required String fallback,
    Map<String, String>? existing,
  }) {
    final occupied =
        existing ??
        (namespace == 'workspace_edge'
            ? _workspaceEdgeRefs
            : _workspaceNodeRefs);
    var candidate = reference.trim();
    if (candidate.isEmpty) {
      candidate = _uniqueReference(_slug(fallback), occupied.keys);
    }
    if (occupied.containsKey(candidate)) {
      throw _error(
        'duplicate_reference',
        '$namespace.ref',
        '$namespace reference $candidate already exists.',
      );
    }
    return candidate;
  }

  void _ensureDependencyCanComplete(String dependencyId, String field) {
    final dependency = _taskCatalog[dependencyId];
    if (dependency == null) return;
    final dead = switch (dependency.status) {
      TaskStatus.failed ||
      TaskStatus.rejected ||
      TaskStatus.split ||
      TaskStatus.deferred ||
      TaskStatus.obsolete ||
      TaskStatus.cancelled => true,
      _ => false,
    };
    if (dead ||
        _deferredTaskIds.contains(dependencyId) ||
        _obsoleteTaskIds.contains(dependencyId)) {
      throw _error(
        'dead_dependency',
        field,
        'Task $dependencyId cannot be used as a dependency because it is not completable.',
      );
    }
  }

  List<String> _resolveReferences(
    Iterable<String> references,
    String Function(String) resolver,
    String fieldPath,
  ) {
    final resolved = <String>[];
    for (final reference in references) {
      if (reference.trim().isEmpty) {
        throw _error(
          'empty_reference',
          fieldPath,
          'References must not be empty.',
        );
      }
      final id = resolver(reference);
      if (!resolved.contains(id)) resolved.add(id);
    }
    return resolved;
  }

  String _claimReference(
    String reference, {
    required String namespace,
    required String fallback,
    Iterable<String> additional = const [],
  }) {
    final occupied = _referencesFor(namespace);
    var candidate = reference.trim();
    if (candidate.isEmpty) {
      candidate = _uniqueReference(_slug(fallback).ifEmpty(namespace), [
        ...occupied.keys,
        ...additional,
      ]);
    }
    if (occupied.containsKey(candidate) || additional.contains(candidate)) {
      throw _error(
        'duplicate_reference',
        '$namespace.ref',
        '$namespace reference $candidate already exists.',
      );
    }
    return candidate;
  }

  Map<String, String> _referencesFor(String namespace) => switch (namespace) {
    'criterion' => _criterionRefs,
    'milestone' => _milestoneRefs,
    _ => _taskRefs,
  };

  String _uniqueReference(String base, Iterable<String> additional) {
    final occupied = additional.toSet();
    var candidate = base;
    var suffix = 2;
    while (occupied.contains(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  int _nextMilestoneOrder() =>
      _milestones.values.fold<int>(0, (highest, item) {
        return item.order > highest ? item.order : highest;
      }) +
      1;

  String _newExpectationId({Iterable<String> additional = const []}) {
    final used = {
      for (final task in _taskCatalog.values)
        for (final expectation in task.expectedEvidence) expectation.id,
      for (final task in _tasks.values)
        for (final expectation in task.expectedEvidence) expectation.id,
      ...additional,
    };
    return _newId('expect', used);
  }

  List<TaskArtifact> _normaliseArtifacts(
    Iterable<TaskArtifact> artifacts,
    String taskId, {
    Iterable<String> additionalIds = const [],
  }) {
    final used = {
      for (final task in _taskCatalog.values)
        for (final artifact in task.expectedArtifacts)
          if (artifact.id.trim().isNotEmpty) artifact.id,
      ...additionalIds,
    };
    final normalized = <TaskArtifact>[];
    for (final artifact in artifacts) {
      final id = _newId('artifact', used);
      used.add(id);
      normalized.add(
        artifact.copyWith(
          id: id,
          taskId: taskId,
          createdAt: artifact.createdAt ?? _now,
        ),
      );
    }
    return normalized;
  }

  void _ensureNoCycles() {
    final graph = {
      for (final task in _tasks.values) task.id: task.dependsOnTaskIds,
    };
    final visiting = <String>{};
    final visited = <String>{};
    bool visit(String id) {
      if (visiting.contains(id)) return true;
      if (!visited.add(id)) return false;
      visiting.add(id);
      for (final dependency in graph[id] ?? const <String>[]) {
        if (visit(dependency)) return true;
      }
      visiting.remove(id);
      return false;
    }

    for (final id in graph.keys) {
      if (visit(id)) {
        throw _error(
          'dependency_cycle',
          'tasks',
          'The draft dependency graph contains a cycle.',
        );
      }
    }
  }

  T _idempotent<T>(String? commandId, String fingerprint, T Function() action) {
    final key = commandId?.trim();
    if (key == null || key.isEmpty) return action();
    final previous = _commands[key];
    if (previous != null) {
      if (previous.fingerprint != fingerprint) {
        throw _error(
          'duplicate_command',
          'commandId',
          'Command $key was already used with different arguments.',
        );
      }
      return previous.result as T;
    }
    final result = action();
    _commands[key] = _AppliedCommand(fingerprint, result);
    return result;
  }

  T _atomic<T>(T Function() action) {
    final criteria = Map<String, ProjectCriterion>.from(_criteria);
    final milestones = Map<String, ProjectMilestone>.from(_milestones);
    final tasks = Map<String, ProjectTaskNode>.from(_tasks);
    final catalog = Map<String, ProjectTaskNode>.from(_taskCatalog);
    final workspaceNodes = Map<String, ProjectWorkspaceNode>.from(
      _workspaceNodes,
    );
    final workspaceEdges = Map<String, ProjectWorkspaceEdge>.from(
      _workspaceEdges,
    );
    final criterionRefs = Map<String, String>.from(_criterionRefs);
    final milestoneRefs = Map<String, String>.from(_milestoneRefs);
    final taskRefs = Map<String, String>.from(_taskRefs);
    final workspaceNodeRefs = Map<String, String>.from(_workspaceNodeRefs);
    final workspaceEdgeRefs = Map<String, String>.from(_workspaceEdgeRefs);
    final deferred = {..._deferredTaskIds};
    final obsolete = {..._obsoleteTaskIds};
    final split = {..._splitTaskIds};
    final newTaskIds = {..._newTaskIds};
    final memories = [..._memoryAdditions];
    final questions = [..._openQuestions];
    final workspaceOrientation = _workspaceOrientation;
    final commands = Map<String, _AppliedCommand>.from(_commands);
    try {
      return action();
    } catch (_) {
      _criteria
        ..clear()
        ..addAll(criteria);
      _milestones
        ..clear()
        ..addAll(milestones);
      _tasks
        ..clear()
        ..addAll(tasks);
      _taskCatalog
        ..clear()
        ..addAll(catalog);
      _workspaceNodes
        ..clear()
        ..addAll(workspaceNodes);
      _workspaceEdges
        ..clear()
        ..addAll(workspaceEdges);
      _criterionRefs
        ..clear()
        ..addAll(criterionRefs);
      _milestoneRefs
        ..clear()
        ..addAll(milestoneRefs);
      _taskRefs
        ..clear()
        ..addAll(taskRefs);
      _workspaceNodeRefs
        ..clear()
        ..addAll(workspaceNodeRefs);
      _workspaceEdgeRefs
        ..clear()
        ..addAll(workspaceEdgeRefs);
      _deferredTaskIds
        ..clear()
        ..addAll(deferred);
      _obsoleteTaskIds
        ..clear()
        ..addAll(obsolete);
      _splitTaskIds
        ..clear()
        ..addAll(split);
      _newTaskIds
        ..clear()
        ..addAll(newTaskIds);
      _memoryAdditions
        ..clear()
        ..addAll(memories);
      _openQuestions
        ..clear()
        ..addAll(questions);
      _workspaceOrientation = workspaceOrientation;
      _commands
        ..clear()
        ..addAll(commands);
      rethrow;
    }
  }

  bool _isTerminal(ProjectTaskNode task) => switch (task.status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled => true,
    _ => false,
  };

  List<String> _requiredList(Iterable<String> values, String field) {
    final result = _cleanStrings(values);
    if (result.isEmpty) {
      throw _error('missing_$field', field, 'At least one value is required.');
    }
    return result;
  }

  List<String> _cleanStrings(Iterable<String> values) => [
    for (final value in values)
      if (value.trim().isNotEmpty) value.trim(),
  ];

  bool _sameStrings(Iterable<String> first, Iterable<String> second) {
    final left = first.toSet();
    final right = second.toSet();
    return left.length == right.length && left.containsAll(right);
  }

  String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _slug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'task' : slug;
  }

  String _newId(String prefix, Iterable<String> usedValues) {
    final used = usedValues.toSet();
    String id;
    do {
      id = '${prefix}_${uuid.v7()}';
    } while (used.contains(id));
    return id;
  }

  String _encode(Object value) => jsonEncode(value);

  String _requiredText(String value, String field) {
    final text = value.trim();
    if (text.isEmpty) {
      throw _error('missing_$field', field, 'A non-empty $field is required.');
    }
    return text;
  }

  String _boundedText(
    String value,
    String field, {
    int maxLength = 200,
    bool allowEmpty = false,
  }) {
    final text = value.trim();
    if (!allowEmpty && text.isEmpty) {
      throw _error('missing_$field', field, 'A non-empty $field is required.');
    }
    if (text.length > maxLength) {
      throw _error(
        'workspace_field_too_long',
        field,
        '$field must be at most $maxLength characters.',
      );
    }
    return text;
  }

  List<String> _boundedList(Iterable<String> values, String field) {
    final result = _cleanStrings(values);
    if (result.length > 20) {
      throw _error(
        'workspace_collection_too_large',
        field,
        '$field may contain at most 20 values.',
      );
    }
    for (final value in result) {
      if (value.length > 200) {
        throw _error(
          'workspace_field_too_long',
          field,
          'Values in $field must be at most 200 characters.',
        );
      }
    }
    return result;
  }

  ProjectPlanBuilderException _error(
    String code,
    String path,
    String message,
  ) => ProjectPlanBuilderException(code: code, path: path, message: message);

  Map<String, dynamic> _specMap(ProjectTaskSpec spec) => {
    'ref': spec.ref,
    'title': spec.title,
    'objective': spec.objective,
    'criterionRefs': spec.criterionRefs,
    'dependencyRefs': spec.dependencyRefs,
    'milestoneRef': spec.milestoneRef,
    'priority': spec.priority.name,
    'risk': spec.risk.name,
    'riskReduction': spec.riskReduction.name,
    'effort': spec.effort.name,
    'selectionRationale': spec.selectionRationale,
    'constraints': spec.constraints,
    'readPaths': spec.readPaths,
    'writePaths': spec.writePaths,
    'doneCriteria': spec.doneCriteria,
    'outOfScope': spec.outOfScope,
    'context': spec.context,
    'expectedArtifacts': [
      for (final artifact in spec.expectedArtifacts)
        {
          'id': artifact.id,
          'path': artifact.path,
          'description': artifact.description,
          'kind': artifact.kind,
        },
    ],
  };

  Map<String, dynamic> _workspaceNodeSpecMap(ProjectWorkspaceNodeSpec spec) => {
    'ref': spec.ref,
    'type': spec.type,
    'title': spec.title,
    'description': spec.description,
    'aliases': spec.aliases,
    'tags': spec.tags,
    'references': spec.references,
  };

  Map<String, dynamic> _workspaceEdgeSpecMap(ProjectWorkspaceEdgeSpec spec) => {
    'ref': spec.ref,
    'sourceRef': spec.sourceRef,
    'targetRef': spec.targetRef,
    'label': spec.label,
    'description': spec.description,
  };

  String _workingDirectory(Map<String, dynamic> values) {
    final value = values['working_directory'] ?? values['workingDirectory'];
    final directory = value?.toString().trim();
    return directory == null || directory.isEmpty ? '.' : directory;
  }
}
