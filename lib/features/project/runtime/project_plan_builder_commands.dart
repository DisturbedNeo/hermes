part of 'project_plan_builder.dart';

extension ProjectPlanBuilderCommands on ProjectPlanBuilder {
  void setValidationRefinedGoal(String refinedGoal) {
    _validationRefinedGoal = refinedGoal.trim();
  }

  void setSummary(String summary) {
    _summary = _requiredText(summary, 'summary');
  }

  void setRationale(String rationale) {
    _rationale = _requiredText(rationale, 'rationale');
  }

  String criterionIdFor(String reference) => _resolveCriterion(reference);

  String milestoneIdFor(String reference) => _resolveMilestone(reference);

  String taskIdFor(String reference) => _resolveTask(reference);

  String workspaceNodeIdFor(String reference) =>
      _resolveWorkspaceNode(reference);

  String workspaceEdgeIdFor(String reference) =>
      _resolveWorkspaceEdge(reference);

  String addCriterion({
    required String statement,
    String ref = '',
    bool required = true,
    ProjectVerificationMode verificationMode = ProjectVerificationMode.mixed,
    String? commandId,
  }) {
    final text = statement.trim();
    final fingerprint = _encode({
      'op': 'add_criterion',
      'statement': text,
      'ref': ref.trim(),
      'required': required,
      'verificationMode': verificationMode.name,
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'missing_criterion_statement',
          'statement',
          'A criterion statement is required.',
        );
      }
      return _atomic(() {
        final reference = _claimReference(
          ref,
          namespace: 'criterion',
          fallback: 'criterion',
        );
        final id = _newId('criterion', _criteria.keys);
        final criterion = ProjectCriterion(
          id: id,
          statement: text,
          required: required,
          verificationMode: verificationMode,
          createdAt: _now,
          updatedAt: _now,
          verifiedAt: null,
        );
        _criteria[id] = criterion;
        _criterionRefs[reference] = id;
        _criterionRefs[id] = id;
        return id;
      });
    });
  }

  String addMilestone({
    required String title,
    required String objective,
    Iterable<String> criterionRefs = const [],
    Iterable<String> exitConditions = const [],
    String ref = '',
    int? order,
    String? commandId,
  }) {
    final milestoneTitle = title.trim();
    final milestoneObjective = objective.trim();
    final fingerprint = _encode({
      'op': 'add_milestone',
      'title': milestoneTitle,
      'objective': milestoneObjective,
      'criterionRefs': [...criterionRefs],
      'exitConditions': [...exitConditions],
      'ref': ref.trim(),
      'order': order,
    });
    return _idempotent(commandId, fingerprint, () {
      if (milestoneTitle.isEmpty || milestoneObjective.isEmpty) {
        throw _error(
          'invalid_milestone',
          'milestone',
          'A milestone needs a title and objective.',
        );
      }
      return _atomic(() {
        final reference = _claimReference(
          ref,
          namespace: 'milestone',
          fallback: 'milestone',
        );
        final id = _newId('milestone', _milestones.keys);
        final criterionIds = _resolveReferences(
          criterionRefs,
          _resolveCriterion,
          'criterionRefs',
        );
        final conditions = _cleanStrings(exitConditions);
        final milestone = ProjectMilestone(
          id: id,
          title: milestoneTitle,
          objective: milestoneObjective,
          criterionIds: criterionIds,
          exitConditions: conditions.isEmpty
              ? [milestoneObjective]
              : conditions,
          order: order ?? _nextMilestoneOrder(),
          status: ProjectMilestoneStatus.planned,
          createdAt: _now,
          updatedAt: _now,
        );
        _milestones[id] = milestone;
        _milestoneRefs[reference] = id;
        _milestoneRefs[id] = id;
        return id;
      });
    });
  }

  String addTask(ProjectPlanTaskSpec spec, {String? commandId}) {
    return addTasks([spec], commandId: commandId).single;
  }

  List<String> addTasks(
    Iterable<ProjectPlanTaskSpec> specs, {
    String? commandId,
  }) {
    final items = [...specs];
    final fingerprint = _encode({
      'op': 'add_tasks',
      'tasks': [for (final spec in items) _specMap(spec)],
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() => _addTasksInternal(items));
    });
  }

  ProjectTaskNode updateTask(
    String taskReference, {
    String? title,
    String? objective,
    Iterable<String>? criterionRefs,
    Iterable<String>? dependencyRefs,
    String? milestoneRef,
    bool clearMilestone = false,
    TaskPriority? priority,
    TaskRisk? risk,
    ProjectRiskReduction? riskReduction,
    TaskEffort? effort,
    String? selectionRationale,
    Iterable<String>? constraints,
    Iterable<String>? readPaths,
    Iterable<String>? writePaths,
    Iterable<String>? doneCriteria,
    Iterable<String>? outOfScope,
    Iterable<String>? context,
    Iterable<TaskArtifact>? expectedArtifacts,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'update_task',
      'task': taskReference.trim(),
      'title': title,
      'objective': objective,
      'criterionRefs': criterionRefs == null ? null : [...criterionRefs],
      'dependencyRefs': dependencyRefs == null ? null : [...dependencyRefs],
      'milestoneRef': milestoneRef,
      'clearMilestone': clearMilestone,
      'priority': priority?.name,
      'risk': risk?.name,
      'riskReduction': riskReduction?.name,
      'effort': effort?.name,
      'selectionRationale': selectionRationale,
      'constraints': constraints == null ? null : [...constraints],
      'readPaths': readPaths == null ? null : [...readPaths],
      'writePaths': writePaths == null ? null : [...writePaths],
      'doneCriteria': doneCriteria == null ? null : [...doneCriteria],
      'outOfScope': outOfScope == null ? null : [...outOfScope],
      'context': context == null ? null : [...context],
      'expectedArtifacts': expectedArtifacts == null
          ? null
          : [
              for (final artifact in expectedArtifacts)
                {
                  'path': artifact.path,
                  'description': artifact.description,
                  'kind': artifact.kind,
                },
            ],
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final existing = _editableTask(taskId);
        final nextObjective = objective?.trim() ?? existing.objective;
        if (nextObjective.isEmpty) {
          throw _error(
            'missing_objective',
            'objective',
            'A task objective is required.',
          );
        }
        final nextTitle = title == null ? existing.title : title.trim();
        if (nextTitle.isEmpty) {
          throw _error('missing_title', 'title', 'A task title is required.');
        }
        final nextCriterionIds = criterionRefs == null
            ? existing.criterionIds
            : _resolveReferences(
                criterionRefs,
                _resolveCriterion,
                'criterionRefs',
              );
        if (nextCriterionIds.isEmpty) {
          throw _error(
            'missing_criterion_reference',
            'criterionRefs',
            'A task must link to at least one criterion.',
          );
        }
        final nextDependencyIds = dependencyRefs == null
            ? existing.dependsOnTaskIds
            : _resolveReferences(
                dependencyRefs,
                _resolveTask,
                'dependencyRefs',
              );
        for (final dependencyId in nextDependencyIds) {
          _ensureDependencyCanComplete(dependencyId, 'dependencyRefs');
        }
        final nextMilestoneId = clearMilestone
            ? null
            : milestoneRef == null
            ? existing.milestoneId
            : _resolveMilestone(milestoneRef);
        final nextDoneCriteria = doneCriteria == null
            ? existing.doneCriteria
            : _requiredList(doneCriteria, 'doneCriteria');
        final nextOutOfScope = outOfScope == null
            ? existing.outOfScope
            : _requiredList(outOfScope, 'outOfScope');
        final next = existing.copyWith(
          title: nextTitle,
          objective: nextObjective,
          criterionIds: nextCriterionIds,
          dependsOnTaskIds: nextDependencyIds,
          milestoneId: nextMilestoneId,
          priority: priority,
          risk: risk,
          riskReduction: riskReduction,
          effort: effort,
          selectionRationale: selectionRationale,
          constraints: constraints == null ? null : _cleanStrings(constraints),
          readPaths: readPaths == null ? null : _cleanStrings(readPaths),
          writePaths: writePaths == null ? null : _cleanStrings(writePaths),
          doneCriteria: nextDoneCriteria,
          outOfScope: nextOutOfScope,
          context: context == null ? null : _cleanStrings(context),
          expectedArtifacts: expectedArtifacts == null
              ? null
              : _normaliseArtifacts(expectedArtifacts, taskId),
          fingerprint: objective == null && criterionRefs == null
              ? null
              : projectTaskFingerprint(nextObjective, nextCriterionIds),
          updatedAt: _now,
        );
        _tasks[taskId] = next;
        _taskCatalog[taskId] = next;
        _ensureNoCycles();
        return next;
      });
    });
  }

  ProjectTaskNode setDependency({
    required String taskReference,
    required String dependencyReference,
    bool enabled = true,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'set_dependency',
      'task': taskReference.trim(),
      'dependency': dependencyReference.trim(),
      'enabled': enabled,
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final dependencyId = _resolveTask(dependencyReference);
        final existing = _editableTask(taskId);
        if (taskId == dependencyId) {
          throw _error(
            'self_dependency',
            'dependency',
            'A task cannot depend on itself.',
          );
        }
        if (enabled) {
          _ensureDependencyCanComplete(dependencyId, 'dependency');
        }
        final dependencies = [...existing.dependsOnTaskIds];
        if (enabled) {
          if (!dependencies.contains(dependencyId)) {
            dependencies.add(dependencyId);
          }
        } else {
          dependencies.remove(dependencyId);
        }
        final updated = existing.copyWith(
          dependsOnTaskIds: dependencies,
          updatedAt: _now,
        );
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        _ensureNoCycles();
        return updated;
      });
    });
  }

  ProjectTaskNode setDisposition({
    required String taskReference,
    required ProjectPlanTaskDisposition disposition,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'set_disposition',
      'task': taskReference.trim(),
      'disposition': disposition.name,
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final existing = _editableTask(taskId);
        _deferredTaskIds.remove(taskId);
        _obsoleteTaskIds.remove(taskId);
        final status = disposition == ProjectPlanTaskDisposition.deferred
            ? TaskStatus.deferred
            : TaskStatus.obsolete;
        final updated = existing.copyWith(status: status, updatedAt: _now);
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        if (disposition == ProjectPlanTaskDisposition.deferred) {
          _deferredTaskIds.add(taskId);
        } else {
          _obsoleteTaskIds.add(taskId);
        }
        return updated;
      });
    });
  }

  ProjectTaskNode clearDisposition(String taskReference, {String? commandId}) {
    final fingerprint = _encode({
      'op': 'clear_disposition',
      'task': taskReference.trim(),
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final existing = _editableTask(taskId);
        _deferredTaskIds.remove(taskId);
        _obsoleteTaskIds.remove(taskId);
        final updated = existing.copyWith(
          status:
              existing.status == TaskStatus.deferred ||
                  existing.status == TaskStatus.obsolete
              ? TaskStatus.queued
              : null,
          updatedAt: _now,
        );
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        return updated;
      });
    });
  }

  /// Adds a command gate and its matching evidence expectation as one unit.
  String addCommandCheck({
    required String taskReference,
    required String command,
    String workingDirectory = '.',
    Iterable<String>? criterionRefs,
    bool required = true,
    String? description,
    String? commandId,
  }) {
    final commandText = command.trim();
    final directory = workingDirectory.trim().isEmpty
        ? '.'
        : workingDirectory.trim();
    final fingerprint = _encode({
      'op': 'add_command_check',
      'task': taskReference.trim(),
      'command': commandText,
      'workingDirectory': directory,
      'criterionRefs': criterionRefs == null ? null : [...criterionRefs],
      'required': required,
      'description': description,
    });
    return _idempotent(commandId, fingerprint, () {
      if (commandText.isEmpty) {
        throw _error(
          'missing_command',
          'command',
          'A command check needs a command.',
        );
      }
      return _atomic(() {
        final taskId = _resolveTask(taskReference);
        final task = _editableTask(taskId);
        final criterionIds = criterionRefs == null
            ? task.criterionIds
            : _resolveReferences(
                criterionRefs,
                _resolveCriterion,
                'criterionRefs',
              );
        if (criterionIds.isEmpty ||
            criterionIds.any((id) => !task.criterionIds.contains(id))) {
          throw _error(
            'unlinked_criterion',
            'criterionRefs',
            'A check must link to criteria already owned by the task.',
          );
        }

        final gateIndex = task.gates.indexWhere(
          (gate) =>
              gate.id == 'command_passes' &&
              gate.params['command']?.toString() == commandText &&
              _workingDirectory(gate.params) == directory,
        );
        final gates = [...task.gates];
        if (gateIndex < 0) {
          gates.add(
            TaskGate(
              id: 'command_passes',
              required: required,
              scope: 'task',
              params: {'command': commandText, 'working_directory': directory},
              description: description?.trim().isNotEmpty == true
                  ? description!.trim()
                  : 'The verification command passes.',
            ),
          );
        } else if (required && !gates[gateIndex].required) {
          final previous = gates[gateIndex];
          gates[gateIndex] = TaskGate(
            id: previous.id,
            required: true,
            scope: previous.scope,
            params: previous.params,
            description: previous.description,
          );
        }

        final existingExpectation = task.expectedEvidence.where((expectation) {
          return expectation.type == ProjectEvidenceType.command &&
              expectation.sourceRef == commandText &&
              _sameStrings(expectation.criterionIds, criterionIds) &&
              _workingDirectory(expectation.details) == directory;
        }).firstOrNull;
        final expectedEvidence = [...task.expectedEvidence];
        final expectationId = existingExpectation?.id ?? _newExpectationId();
        if (existingExpectation == null) {
          expectedEvidence.add(
            TaskEvidenceExpectation(
              id: expectationId,
              type: ProjectEvidenceType.command,
              criterionIds: criterionIds,
              description: description?.trim().isNotEmpty == true
                  ? description!.trim()
                  : 'The verification command passes.',
              required: required,
              sourceRef: commandText,
              details: {'working_directory': directory},
            ),
          );
        } else if (required && !existingExpectation.required) {
          final expectationIndex = expectedEvidence.indexOf(
            existingExpectation,
          );
          expectedEvidence[expectationIndex] = TaskEvidenceExpectation(
            id: existingExpectation.id,
            type: existingExpectation.type,
            criterionIds: existingExpectation.criterionIds,
            description: existingExpectation.description,
            required: true,
            sourceRef: existingExpectation.sourceRef,
            details: existingExpectation.details,
          );
        }
        final updated = task.copyWith(
          gates: gates,
          expectedEvidence: expectedEvidence,
          updatedAt: _now,
        );
        _tasks[taskId] = updated;
        _taskCatalog[taskId] = updated;
        return expectationId;
      });
    });
  }

  String addNote({
    required ProjectMemoryKind kind,
    required String content,
    String? sourceId,
    String? commandId,
  }) {
    final text = content.trim();
    final fingerprint = _encode({
      'op': 'add_note',
      'kind': kind.name,
      'content': text,
      'sourceId': sourceId,
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'empty_note',
          'content',
          'A note needs non-empty content.',
        );
      }
      return _atomic(() {
        final existing = [..._project.memory, ..._memoryAdditions]
            .where((entry) => _normalise(entry.content) == _normalise(text))
            .firstOrNull;
        if (existing != null) return existing.id;
        final entry = ProjectMemoryEntry(
          id: _newId(
            'memory',
            [..._project.memory, ..._memoryAdditions].map((item) => item.id),
          ),
          kind: kind,
          content: text,
          sourceType: ProjectMemorySourceType.planner,
          sourceId: sourceId?.trim().isEmpty == true ? null : sourceId?.trim(),
          confidence: ProjectMemoryConfidence.inferred,
          protected: false,
          active: true,
          createdAt: _now,
          updatedAt: _now,
        );
        _memoryAdditions.add(entry);
        return entry.id;
      });
    });
  }

  /// Adds a blocking question to the draft. The question ID is generated by
  /// Hermes and repeated question text is returned rather than duplicated.
  String requestUserDecision({required String question, String? commandId}) {
    final text = question.trim();
    final fingerprint = _encode({
      'op': 'request_user_decision',
      'question': text,
    });
    return _idempotent(commandId, fingerprint, () {
      if (text.isEmpty) {
        throw _error(
          'empty_question',
          'question',
          'A user decision needs a non-empty question.',
        );
      }
      return _atomic(() {
        final existing = [
          ..._project.openQuestions,
          ..._openQuestions,
        ].where((item) => _normalise(item.question) == _normalise(text));
        final previous = existing.firstOrNull;
        if (previous != null) return previous.id;
        final id = _newId(
          'question',
          [..._project.openQuestions, ..._openQuestions].map((item) => item.id),
        );
        _openQuestions.add(
          PendingProjectQuestion(id: id, question: text, createdAt: _now),
        );
        return id;
      });
    });
  }

  /// Splits one mutable task into fresh child tasks. The parent is marked
  /// split by [ProjectPlanRevisionService] at commit; it is never rewritten
  /// by a model-supplied task record.
  List<String> splitTask({
    required String taskReference,
    required Iterable<ProjectPlanTaskSpec> children,
    String? commandId,
  }) {
    final items = [...children];
    final fingerprint = _encode({
      'op': 'split_task',
      'task': taskReference.trim(),
      'children': [for (final child in items) _specMap(child)],
    });
    return _idempotent(commandId, fingerprint, () {
      if (items.isEmpty) {
        throw _error(
          'missing_split_children',
          'children',
          'A split needs at least one child task.',
        );
      }
      return _atomic(() {
        final sourceId = _resolveTask(taskReference);
        final source = _editableTask(sourceId);
        final sourceContext = [
          ...source.context,
          'Split from task ${source.id}: ${source.title}.',
        ];
        final inheritedCriteria = source.criterionIds;
        final inheritedDependencies = source.dependsOnTaskIds;
        final inheritedDoneCriteria = source.doneCriteria;
        final inheritedOutOfScope = source.outOfScope;
        final inheritedReadPaths = source.readPaths;
        final inheritedWritePaths = source.writePaths;
        final inheritedArtifacts = source.expectedArtifacts;
        final childSpecs = [
          for (var index = 0; index < items.length; index++)
            _splitChildSpec(
              source: source,
              child: items[index],
              sourceContext: sourceContext,
              inheritedCriteria: inheritedCriteria,
              inheritedDependencies: inheritedDependencies,
              inheritedDoneCriteria: inheritedDoneCriteria,
              inheritedOutOfScope: inheritedOutOfScope,
              inheritedReadPaths: inheritedReadPaths,
              inheritedWritePaths: inheritedWritePaths,
              inheritedArtifacts: inheritedArtifacts,
              fieldPath: 'children[$index]',
            ),
        ];
        final ids = _addTasksInternal(childSpecs);
        // A dependent task that waited for the oversized task must now wait
        // for every child. Leaving the old dependency in place would turn a
        // successful split into a permanently dead dependency at commit.
        for (final entry in _tasks.entries.toList()) {
          if (entry.key == sourceId ||
              !entry.value.dependsOnTaskIds.contains(sourceId)) {
            continue;
          }
          final dependencies = <String>[];
          for (final dependencyId in entry.value.dependsOnTaskIds) {
            if (dependencyId == sourceId) {
              for (final childId in ids) {
                if (!dependencies.contains(childId)) dependencies.add(childId);
              }
            } else if (!dependencies.contains(dependencyId)) {
              dependencies.add(dependencyId);
            }
          }
          final updated = entry.value.copyWith(
            dependsOnTaskIds: dependencies,
            updatedAt: _now,
          );
          _tasks[entry.key] = updated;
          _taskCatalog[entry.key] = updated;
        }
        _ensureNoCycles();
        _deferredTaskIds.remove(sourceId);
        _obsoleteTaskIds.remove(sourceId);
        _splitTaskIds.add(sourceId);
        return ids;
      });
    });
  }

  ProjectPlanTaskSpec _splitChildSpec({
    required ProjectTaskNode source,
    required ProjectPlanTaskSpec child,
    required List<String> sourceContext,
    required List<String> inheritedCriteria,
    required List<String> inheritedDependencies,
    required List<String> inheritedDoneCriteria,
    required List<String> inheritedOutOfScope,
    required List<String> inheritedReadPaths,
    required List<String> inheritedWritePaths,
    required List<TaskArtifact> inheritedArtifacts,
    required String fieldPath,
  }) {
    for (var index = 0; index < child.dependencyRefs.length; index++) {
      final reference = child.dependencyRefs.elementAt(index);
      if (_taskRefs[reference.trim()] == source.id) {
        throw _error(
          'split_child_dependency',
          '$fieldPath.dependencyRefs[$index]',
          'A split child cannot depend on its parent task ${source.id}. Depend on the parent\'s prerequisites instead.',
        );
      }
    }
    return ProjectPlanTaskSpec(
      ref: child.ref,
      title: child.title,
      objective: child.objective,
      criterionRefs: child.criterionRefs.isEmpty
          ? inheritedCriteria
          : child.criterionRefs,
      dependencyRefs: child.dependencyRefs.isEmpty
          ? inheritedDependencies
          : child.dependencyRefs,
      milestoneRef: child.milestoneRef ?? source.milestoneId,
      priority: child.priority,
      risk: child.risk,
      riskReduction: child.riskReduction,
      effort: child.effort,
      selectionRationale: child.selectionRationale,
      constraints: child.constraints.isEmpty
          ? source.constraints
          : child.constraints,
      readPaths: child.readPaths.isEmpty ? inheritedReadPaths : child.readPaths,
      writePaths: child.writePaths.isEmpty
          ? inheritedWritePaths
          : child.writePaths,
      doneCriteria: child.doneCriteria.isEmpty
          ? inheritedDoneCriteria
          : child.doneCriteria,
      outOfScope: child.outOfScope.isEmpty
          ? inheritedOutOfScope
          : child.outOfScope,
      context: [...sourceContext, ...child.context],
      expectedArtifacts: child.expectedArtifacts.isEmpty
          ? inheritedArtifacts
          : child.expectedArtifacts,
    );
  }

  /// Creates a fresh queued task from a failed task while preserving the
  /// failed task and its execution history.
  String retryTask({
    required String taskReference,
    String ref = '',
    String? title,
    String? objective,
    String? commandId,
  }) {
    final fingerprint = _encode({
      'op': 'retry_task',
      'task': taskReference.trim(),
      'ref': ref.trim(),
      'title': title,
      'objective': objective,
    });
    return _idempotent(commandId, fingerprint, () {
      return _atomic(() {
        final sourceId = _resolveTask(taskReference);
        final source = _taskCatalog[sourceId];
        if (source == null ||
            (source.status != TaskStatus.failed &&
                source.status != TaskStatus.rejected)) {
          throw _error(
            'retry_requires_failed_task',
            'task',
            'Retry is only available for failed or rejected tasks.',
          );
        }
        final baseObjective = objective?.trim().isNotEmpty == true
            ? objective!.trim()
            : source.objective;
        final retryObjective =
            'Retry failed task after addressing the previous failure: '
            '$baseObjective';
        final failureContext = source.failureKey?.trim();
        final spec = ProjectPlanTaskSpec(
          ref: ref,
          title: title?.trim().isNotEmpty == true
              ? title!.trim()
              : 'Retry ${source.title}',
          objective: retryObjective,
          criterionRefs: source.criterionIds,
          dependencyRefs: source.dependsOnTaskIds,
          milestoneRef: source.milestoneId,
          priority: source.priority,
          risk: source.risk,
          riskReduction: source.riskReduction,
          effort: source.effort,
          selectionRationale: 'Created as a fresh retry of ${source.id}.',
          constraints: source.constraints,
          readPaths: source.readPaths,
          writePaths: source.writePaths,
          doneCriteria: source.doneCriteria,
          outOfScope: source.outOfScope,
          context: [
            ...source.context,
            'Retry of failed task ${source.id}.',
            if (failureContext != null && failureContext.isNotEmpty)
              'Previous failure: $failureContext',
            if (source.rejectionReason?.trim().isNotEmpty == true)
              'Previous rejection: ${source.rejectionReason!.trim()}',
          ],
          expectedArtifacts: source.expectedArtifacts,
        );
        return _addTasksInternal([spec]).single;
      });
    });
  }

  /// Materializes and commits the complete desired plan atomically through
  /// the existing revision service.
}
