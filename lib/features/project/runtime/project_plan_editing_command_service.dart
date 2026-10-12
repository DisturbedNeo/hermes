part of 'project_planning_tools.dart';

class ProjectPlanEditingCommandService {
  ProjectPlanEditingCommandService(this.context);

  final ProjectPlanningContext context;

  void _ensureOpen() {
    if (context.closed) {
      throw ProjectPlanningToolCommandService._argument(
        'planning_closed',
        'tool',
        'The planning session has already been finalized.',
      );
    }
  }

  Future<Map<String, dynamic>> updateProject(
    PlanningArguments arguments,
    String? commandId,
  ) async {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'title',
      'refined_goal',
      'constraints',
      'criteria',
      'milestones',
    });
    final hasChange = arguments.keys.any((key) => arguments[key] != null);
    if (!hasChange) {
      throw ProjectPlanningToolCommandService._argument(
        'empty_update',
        'tool',
        'Provide at least one project field, criterion, or milestone to update.',
      );
    }
    final criteria = ProjectPlanningToolCommandService._maps(
      arguments['criteria'],
      'criteria',
    );
    final milestones = ProjectPlanningToolCommandService._maps(
      arguments['milestones'],
      'milestones',
    );
    context.builder.transaction(() {
      context.setProjectDetails(
        title:
            ProjectPlanningToolCommandService._optionalString(
              arguments['title'],
              'title',
            ) ??
            context.draftTitle,
        refinedGoal:
            ProjectPlanningToolCommandService._optionalString(
              arguments['refined_goal'],
              'refined_goal',
            ) ??
            context.draftRefinedGoal,
        constraints: arguments.containsKey('constraints')
            ? ProjectPlanningToolCommandService._stringList(
                arguments['constraints'],
                'constraints',
              )
            : null,
      );
      for (var index = 0; index < criteria.length; index++) {
        final value = criteria[index];
        ProjectPlanningToolCommandService._keys(value, const {
          'criterion_id',
          'statement',
          'required',
          'verification_mode',
        });
        final criterionId = ProjectPlanningToolCommandService._optionalInt(
          value['criterion_id'],
          'criteria[$index].criterion_id',
        );
        final statement = ProjectPlanningToolCommandService._optionalString(
          value['statement'],
          'criteria[$index].statement',
        );
        final required = ProjectPlanningToolCommandService._optionalBool(
          value['required'],
          'criteria[$index].required',
        );
        final mode = ProjectPlanningToolCommandService._enumValue(
          ProjectVerificationMode.values,
          value['verification_mode'],
          'criteria[$index].verification_mode',
        );
        if (criterionId == null) {
          context.builder.addCriterion(
            statement: ProjectPlanningToolCommandService._requiredString(
              statement,
              'criteria[$index].statement',
            ),
            required: required ?? true,
            verificationMode: mode ?? ProjectVerificationMode.mixed,
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'criterion:$index',
            ),
          );
        } else {
          context.builder.updateCriterion(
            criterionId.toString(),
            statement: statement,
            required: required,
            verificationMode: mode,
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'criterion:$index',
            ),
          );
        }
      }
      for (var index = 0; index < milestones.length; index++) {
        final value = milestones[index];
        ProjectPlanningToolCommandService._keys(value, const {
          'milestone_id',
          'title',
          'objective',
          'criterion_ids',
          'exit_conditions',
          'order',
        });
        final milestoneId = ProjectPlanningToolCommandService._optionalInt(
          value['milestone_id'],
          'milestones[$index].milestone_id',
        );
        final title = ProjectPlanningToolCommandService._optionalString(
          value['title'],
          'milestones[$index].title',
        );
        final objective = ProjectPlanningToolCommandService._optionalString(
          value['objective'],
          'milestones[$index].objective',
        );
        final criterionRefs = value.containsKey('criterion_ids')
            ? [
                for (final id in ProjectPlanningToolCommandService._intList(
                  value['criterion_ids'],
                  'milestones[$index].criterion_ids',
                ))
                  id.toString(),
              ]
            : null;
        if (milestoneId == null) {
          context.builder.addMilestone(
            title: ProjectPlanningToolCommandService._requiredString(
              title,
              'milestones[$index].title',
            ),
            objective: ProjectPlanningToolCommandService._requiredString(
              objective,
              'milestones[$index].objective',
            ),
            criterionRefs: criterionRefs ?? const [],
            exitConditions: value.containsKey('exit_conditions')
                ? ProjectPlanningToolCommandService._stringList(
                    value['exit_conditions'],
                    'milestones[$index].exit_conditions',
                  )
                : const [],
            order: ProjectPlanningToolCommandService._optionalInt(
              value['order'],
              'milestones[$index].order',
            ),
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'milestone:$index',
            ),
          );
        } else {
          context.builder.updateMilestone(
            milestoneId.toString(),
            title: title,
            objective: objective,
            criterionRefs: criterionRefs,
            exitConditions: value.containsKey('exit_conditions')
                ? ProjectPlanningToolCommandService._stringList(
                    value['exit_conditions'],
                    'milestones[$index].exit_conditions',
                  )
                : null,
            order: ProjectPlanningToolCommandService._optionalInt(
              value['order'],
              'milestones[$index].order',
            ),
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'milestone:$index',
            ),
          );
        }
      }
    });
    final persisted = await context.persistDraft();
    return {
      'updated': true,
      'project': _projectWire(persisted),
      'persistence_revision': persisted.persistenceRevision,
      'next_action': 'plan_finalize',
    };
  }

  Future<Map<String, dynamic>> _mutateTask(
    PlanningArguments arguments,
    String? commandId,
  ) async {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task_id',
      'title',
      'objective',
      'acceptance',
      'dependency_task_ids',
      'milestone_id',
      'clear_milestone',
      'priority',
      'risk',
      'risk_reduction',
      'effort',
      'selection_rationale',
      'constraints',
      'read_paths',
      'write_paths',
      'out_of_scope',
      'context',
      'steps',
      'remove_step_refs',
      'replace_steps',
      'remove_acceptance_refs',
      'replace_acceptance',
      'disposition',
    });
    final taskNumber = ProjectPlanningToolCommandService._optionalInt(
      arguments['task_id'],
      'task_id',
    );
    late Map<String, dynamic> transformed;
    late String taskId;
    final suppliedSteps = arguments.containsKey('steps')
        ? ProjectPlanningToolCommandService._steps(
            arguments['steps'],
            'steps',
            requireRefs: taskNumber != null,
            requireComplete: taskNumber != null,
          )
        : null;
    final replacementSteps = arguments.containsKey('replace_steps')
        ? ProjectPlanningToolCommandService._withStepRefs(
            ProjectPlanningToolCommandService._steps(
              arguments['replace_steps'],
              'replace_steps',
              requireRefs: true,
              requireComplete: true,
            ),
            'replace_steps',
          )
        : null;
    final removedStepRefs = arguments.containsKey('remove_step_refs')
        ? ProjectPlanningToolCommandService._stringList(
            arguments['remove_step_refs'],
            'remove_step_refs',
          )
        : const <String>[];
    final hasAcceptanceUpserts = arguments.containsKey('acceptance');
    final hasAcceptanceReplacement = arguments.containsKey(
      'replace_acceptance',
    );
    final removedAcceptanceRefs =
        arguments.containsKey('remove_acceptance_refs')
        ? ProjectPlanningToolCommandService._stringList(
            arguments['remove_acceptance_refs'],
            'remove_acceptance_refs',
          )
        : const <String>[];
    if (replacementSteps != null &&
        (suppliedSteps != null || arguments.containsKey('remove_step_refs'))) {
      throw ProjectPlanningToolCommandService._argument(
        'conflicting_list_operations',
        'replace_steps',
        'Use replace_steps by itself; do not combine it with steps or remove_step_refs.',
      );
    }
    if (hasAcceptanceReplacement &&
        (hasAcceptanceUpserts ||
            arguments.containsKey('remove_acceptance_refs'))) {
      throw ProjectPlanningToolCommandService._argument(
        'conflicting_list_operations',
        'replace_acceptance',
        'Use replace_acceptance by itself; do not combine it with acceptance or remove_acceptance_refs.',
      );
    }
    if (arguments.containsKey('remove_step_refs') && removedStepRefs.isEmpty) {
      throw ProjectPlanningToolCommandService._argument(
        'invalid_argument',
        'remove_step_refs',
        'At least one step ref is required.',
      );
    }
    if (arguments.containsKey('remove_acceptance_refs') &&
        removedAcceptanceRefs.isEmpty) {
      throw ProjectPlanningToolCommandService._argument(
        'invalid_argument',
        'remove_acceptance_refs',
        'At least one acceptance ref is required.',
      );
    }
    final previousTaskSteps = <String, List<ProjectTaskStepSpec>>{};
    for (final task in context.currentProject.tasks) {
      final steps = context.taskStepsFor(task.id);
      if (steps != null) previousTaskSteps[task.id] = steps;
    }
    try {
      context.builder.transaction(() {
        transformed = _transformTaskInput(arguments.toWire(), 'task');
        if (taskNumber == null) {
          final taskInput = Map<String, dynamic>.from(transformed)
            ..remove('inline_criterion_refs');
          final spec = ProjectPlanningToolCommandService._taskSpec(
            taskInput,
            'task',
            requireObjective: true,
          );
          taskId = context.builder.addTask(
            spec,
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'task',
            ),
          );
          context.setTaskSteps(taskId, spec.steps);
        } else {
          final existingTaskId = context.builder.taskIdFor(
            taskNumber.toString(),
          );
          final existingTask = context.currentProject.tasks.firstWhere(
            (task) => task.id == existingTaskId,
          );
          final acceptance = hasAcceptanceReplacement
              ? ProjectPlanningToolCommandService._acceptance(
                  arguments['replace_acceptance'],
                  'replace_acceptance',
                )
              : hasAcceptanceUpserts || removedAcceptanceRefs.isNotEmpty
              ? _mergeAcceptance(
                  existingTask.acceptance,
                  hasAcceptanceUpserts
                      ? ProjectPlanningToolCommandService._acceptance(
                          transformed['acceptance'],
                          'acceptance',
                        )
                      : const [],
                  removedAcceptanceRefs,
                )
              : null;
          final updated = context.builder.updateTask(
            existingTaskId,
            title: ProjectPlanningToolCommandService._optionalString(
              arguments['title'],
              'title',
            ),
            objective: ProjectPlanningToolCommandService._optionalString(
              arguments['objective'],
              'objective',
            ),
            acceptance: acceptance,
            dependencyRefs: arguments.containsKey('dependency_task_ids')
                ? (transformed['dependency_refs'] as List).cast<String>()
                : null,
            milestoneRef: arguments.containsKey('milestone_id')
                ? transformed['milestone_ref'] as String?
                : null,
            clearMilestone:
                ProjectPlanningToolCommandService._optionalBool(
                  arguments['clear_milestone'],
                  'clear_milestone',
                ) ??
                false,
            priority: ProjectPlanningToolCommandService._enumValue(
              TaskPriority.values,
              arguments['priority'],
              'priority',
            ),
            risk: ProjectPlanningToolCommandService._enumValue(
              TaskRisk.values,
              arguments['risk'],
              'risk',
            ),
            riskReduction: ProjectPlanningToolCommandService._enumValue(
              ProjectRiskReduction.values,
              arguments['risk_reduction'],
              'risk_reduction',
            ),
            effort: ProjectPlanningToolCommandService._enumValue(
              TaskEffort.values,
              arguments['effort'],
              'effort',
            ),
            selectionRationale:
                ProjectPlanningToolCommandService._optionalString(
                  arguments['selection_rationale'],
                  'selection_rationale',
                ),
            constraints: ProjectPlanningToolCommandService._optionalStringList(
              arguments['constraints'],
              'constraints',
            ),
            readPaths: ProjectPlanningToolCommandService._optionalStringList(
              arguments['read_paths'],
              'read_paths',
            ),
            writePaths: ProjectPlanningToolCommandService._optionalStringList(
              arguments['write_paths'],
              'write_paths',
            ),
            outOfScope: ProjectPlanningToolCommandService._optionalStringList(
              arguments['out_of_scope'],
              'out_of_scope',
            ),
            context: ProjectPlanningToolCommandService._optionalStringList(
              arguments['context'],
              'context',
            ),
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'task',
            ),
          );
          taskId = updated.id;
          var nextSteps = context.currentTaskStepSpecs(taskId);
          if (replacementSteps != null ||
              suppliedSteps != null ||
              removedStepRefs.isNotEmpty) {
            nextSteps =
                replacementSteps ??
                _mergeStepSpecs(
                  context.currentTaskStepSpecs(taskId),
                  suppliedSteps ?? const [],
                  removedStepRefs,
                );
            _validateCompletedStepPreservation(
              context.canonicalTasks[taskId],
              nextSteps,
            );
            context.setTaskSteps(taskId, nextSteps);
          }
          _validateStepAcceptanceRefs(nextSteps, updated.acceptance);
        }
        final disposition = ProjectPlanningToolCommandService._enumValue(
          ProjectPlanTaskDisposition.values,
          arguments['disposition'],
          'disposition',
        );
        if (disposition != null) {
          context.builder.setDisposition(
            taskReference: taskId,
            disposition: disposition,
            commandId: ProjectPlanningToolCommandService._scopedCommandId(
              commandId,
              'disposition',
            ),
          );
        }
      });
    } catch (_) {
      context.restoreTaskSteps(previousTaskSteps);
      rethrow;
    }
    final persisted = await context.persistDraft();
    return {
      'task_id': context.builder.taskAgentNumberFor(taskId),
      'created': taskNumber == null,
      'task': _taskWire(
        persisted.tasks.firstWhere((task) => task.id == taskId),
      ),
      'persistence_revision': persisted.persistenceRevision,
      'next_action': 'plan_finalize',
    };
  }

  Future<Map<String, dynamic>> addTask(
    PlanningArguments arguments,
    String? commandId,
  ) async {
    ProjectPlanningToolCommandService._keys(arguments, const {
      'title',
      'objective',
      'acceptance',
      'dependency_task_ids',
      'milestone_id',
      'priority',
      'risk',
      'risk_reduction',
      'effort',
      'selection_rationale',
      'constraints',
      'read_paths',
      'write_paths',
      'out_of_scope',
      'context',
      'steps',
    });
    if (arguments.containsKey('task_id')) {
      throw ProjectPlanningToolCommandService._argument(
        'invalid_argument',
        'task_id',
        'task_add does not accept an existing task ID.',
      );
    }
    return _mutateTask(arguments, commandId);
  }

  Future<Map<String, dynamic>> updateTask(
    PlanningArguments arguments,
    String? commandId,
  ) async {
    if (!arguments.containsKey('task_id')) {
      throw ProjectPlanningToolCommandService._argument(
        'missing_argument',
        'task_id',
        'task_update requires a task ID.',
      );
    }
    return _mutateTask(arguments, commandId);
  }

  Future<Map<String, dynamic>> removeTask(
    PlanningArguments arguments,
    String? commandId,
  ) async {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'task_id'});
    final taskNumber = ProjectPlanningToolCommandService._optionalInt(
      arguments['task_id'],
      'task_id',
    );
    if (taskNumber == null) {
      throw ProjectPlanningToolCommandService._argument(
        'missing_argument',
        'task_id',
        'task_remove requires a task ID.',
      );
    }
    final taskId = context.builder.taskIdFor(taskNumber.toString());
    context.builder.setDisposition(
      taskReference: taskId,
      disposition: ProjectPlanTaskDisposition.obsolete,
      commandId: commandId,
    );
    final persisted = await context.persistDraft();
    return {
      'removed': true,
      'task_id': taskNumber,
      'task': _taskWire(
        persisted.tasks.firstWhere((task) => task.id == taskId),
      ),
      'persistence_revision': persisted.persistenceRevision,
      'next_action': 'plan_finalize',
    };
  }

  List<AcceptanceItem> _mergeAcceptance(
    List<AcceptanceItem> existing,
    List<AcceptanceItem> upserts,
    List<String> removals,
  ) {
    final removalRefs = <String>{};
    for (var index = 0; index < removals.length; index++) {
      final ref = removals[index].trim();
      if (ref.isEmpty || !removalRefs.add(ref)) {
        throw ProjectPlanningToolCommandService._argument(
          'invalid_reference',
          'remove_acceptance_refs[$index]',
          'Acceptance refs to remove must be non-empty and unique.',
        );
      }
    }
    final upsertRefs = {for (final item in upserts) item.ref};
    if (upsertRefs.any(removalRefs.contains)) {
      throw ProjectPlanningToolCommandService._argument(
        'conflicting_list_operations',
        'acceptance',
        'An acceptance ref cannot be updated and removed in the same call.',
      );
    }
    for (final ref in removalRefs) {
      if (!existing.any((item) => item.ref == ref)) {
        throw ProjectPlanningToolCommandService._argument(
          'unknown_reference',
          'remove_acceptance_refs',
          'Acceptance ref $ref does not exist on this task.',
        );
      }
    }
    final merged = existing
        .where((item) => !removalRefs.contains(item.ref))
        .toList();
    for (final item in upserts) {
      final index = merged.indexWhere((existing) => existing.ref == item.ref);
      if (index < 0) {
        merged.add(item);
      } else {
        merged[index] = item;
      }
    }
    return merged;
  }

  List<ProjectTaskStepSpec> _mergeStepSpecs(
    List<ProjectTaskStepSpec> existing,
    List<ProjectTaskStepSpec> upserts,
    List<String> removals,
  ) {
    final removalRefs = <String>{};
    for (var index = 0; index < removals.length; index++) {
      final ref = removals[index].trim();
      if (ref.isEmpty || !removalRefs.add(ref)) {
        throw ProjectPlanningToolCommandService._argument(
          'invalid_reference',
          'remove_step_refs[$index]',
          'Step refs to remove must be non-empty and unique.',
        );
      }
    }
    final upsertRefs = <String>{};
    for (var index = 0; index < upserts.length; index++) {
      final ref = upserts[index].ref.trim();
      if (ref.isEmpty || !upsertRefs.add(ref)) {
        throw ProjectPlanningToolCommandService._argument(
          'invalid_step_ref',
          'steps[$index].ref',
          'Step refs must be non-empty and unique.',
        );
      }
    }
    if (upsertRefs.any(removalRefs.contains)) {
      throw ProjectPlanningToolCommandService._argument(
        'conflicting_list_operations',
        'steps',
        'A step ref cannot be updated and removed in the same call.',
      );
    }
    for (final ref in removalRefs) {
      if (!existing.any((step) => step.ref == ref)) {
        throw ProjectPlanningToolCommandService._argument(
          'unknown_reference',
          'remove_step_refs',
          'Step ref $ref does not exist on this task.',
        );
      }
    }
    final merged = existing
        .where((step) => !removalRefs.contains(step.ref))
        .toList();
    for (final step in upserts) {
      final index = merged.indexWhere((existing) => existing.ref == step.ref);
      if (index < 0) {
        merged.add(step);
      } else {
        merged[index] = step;
      }
    }
    if (merged.isEmpty) {
      throw ProjectPlanningToolCommandService._argument(
        'missing_steps',
        'steps',
        'A task needs at least one executable step.',
      );
    }
    return merged;
  }

  void _validateCompletedStepPreservation(
    TaskAggregate? task,
    List<ProjectTaskStepSpec> nextSteps,
  ) {
    if (task == null) return;
    for (var index = 0; index < task.steps.length; index++) {
      final existing = task.steps[index];
      if (existing.status != TaskStepStatus.completed &&
          existing.status != TaskStepStatus.skipped) {
        continue;
      }
      final ref = existing.planningRef.trim().isEmpty
          ? 'step_${index + 1}'
          : existing.planningRef;
      final replacement = nextSteps
          .where((step) => step.ref == ref)
          .firstOrNull;
      if (replacement == null || !_sameStep(existing, replacement)) {
        throw ProjectPlanningToolCommandService._argument(
          'completed_step_immutable',
          'steps',
          'Completed or skipped step $ref cannot be changed or removed.',
        );
      }
    }
  }

  bool _sameStep(TaskStep existing, ProjectTaskStepSpec candidate) {
    if (existing.title != candidate.title ||
        existing.objective != candidate.objective ||
        existing.mayEditFiles != candidate.mayEditFiles ||
        !_sameStrings(existing.instructions, candidate.instructions) ||
        !_sameStrings(existing.acceptanceRefs, candidate.acceptanceRefs) ||
        existing.artifacts.length != candidate.artifacts.length) {
      return false;
    }
    for (var index = 0; index < existing.artifacts.length; index++) {
      final current = existing.artifacts[index];
      final next = candidate.artifacts[index];
      if (current.path != next.path ||
          current.description != next.description ||
          current.kind != next.kind) {
        return false;
      }
    }
    return true;
  }

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _validateStepAcceptanceRefs(
    List<ProjectTaskStepSpec> steps,
    List<AcceptanceItem> acceptance,
  ) {
    final acceptanceRefs = {for (final item in acceptance) item.ref};
    for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
      for (final ref in steps[stepIndex].acceptanceRefs) {
        if (!acceptanceRefs.contains(ref)) {
          throw ProjectPlanningToolCommandService._argument(
            'unknown_reference',
            'steps[$stepIndex].acceptance_refs',
            'Unknown acceptance ref $ref for this task.',
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>> requestUserDecision(
    PlanningArguments arguments,
    String? commandId,
  ) async {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'question'});
    final question = ProjectPlanningToolCommandService._requiredString(
      arguments['question'],
      'question',
    );
    final id = context.builder.requestUserDecision(
      question: question,
      commandId: commandId,
    );
    final persisted = await context.persistDraft();
    context.closed = true;
    return {
      'awaiting_user_input': true,
      'question': {'id': id, 'question': question},
      'project': _projectWire(persisted),
      'persistence_revision': persisted.persistenceRevision,
    };
  }

  Map<String, dynamic> _projectWire(ProjectAggregate project) => {
    'id': project.id,
    'status': project.status.wire,
    'persistence_revision': project.persistenceRevision,
    'title': project.title,
    'refined_goal': project.refinedGoal,
    'constraints': project.constraints,
    'criteria': [
      for (final criterion in project.criteria)
        {
          'criterion_id': project.criterionAgentNumber(criterion.id),
          'statement': criterion.statement,
          'required': criterion.required,
          'verification_mode': criterion.verificationMode.name,
        },
    ],
    'milestones': [
      for (final milestone in project.milestones)
        {
          'milestone_id': project.milestoneAgentNumber(milestone.id),
          'title': milestone.title,
          'objective': milestone.objective,
          'criterion_ids': [
            for (final id in milestone.criterionIds)
              project.criterionAgentNumber(id),
          ],
          'order': milestone.order,
        },
    ],
    'tasks': [for (final task in project.tasks) _taskWire(task)],
    'open_questions': [
      for (final question in project.openQuestions)
        {'id': question.id, 'question': question.question},
    ],
  };

  Map<String, dynamic> _taskWire(ProjectTaskNode task) => {
    'task_id': context.currentProject.taskAgentNumber(task.id),
    'title': task.title,
    'objective': task.objective,
    'status': task.status.wire,
    'constraints': task.constraints,
    'out_of_scope': task.outOfScope,
    'read_paths': task.readPaths,
    'write_paths': task.writePaths,
    'context': task.context,
    'priority': task.priority.name,
    'risk': task.risk.name,
    'risk_reduction': task.riskReduction.name,
    'effort': task.effort.name,
    'selection_rationale': task.selectionRationale,
    'dependency_task_ids': [
      for (final id in task.dependsOnTaskIds)
        context.currentProject.taskAgentNumber(id),
    ],
    'milestone_id': task.milestoneId == null
        ? null
        : context.currentProject.milestoneAgentNumber(task.milestoneId!),
    'acceptance': [
      for (final item in task.acceptance)
        {
          'ref': item.ref,
          'statement': item.statement,
          'criterion_ids': [
            for (final id in item.criterionIds)
              context.currentProject.criterionAgentNumber(id),
          ],
        },
    ],
  };

  Map<String, dynamic> _transformTaskInput(
    Map<String, dynamic> value,
    String path, {
    String? createReference,
    Map<int, String>? milestoneRefsByPosition,
  }) {
    final allowed = {
      'task_id',
      'title',
      'objective',
      'acceptance',
      'dependency_task_ids',
      'milestone_id',
      'clear_milestone',
      'priority',
      'risk',
      'risk_reduction',
      'effort',
      'selection_rationale',
      'constraints',
      'read_paths',
      'write_paths',
      'out_of_scope',
      'context',
      'steps',
      'remove_step_refs',
      'replace_steps',
      'remove_acceptance_refs',
      'replace_acceptance',
      'disposition',
    };
    ProjectPlanningToolCommandService._keys(value, allowed);
    final acceptance = ProjectPlanningToolCommandService._maps(
      value['acceptance'],
      '$path.acceptance',
    );
    final transformed = <String, dynamic>{
      'ref': createReference ?? '',
      'title': value['title'],
      'objective': value['objective'],
      'acceptance': acceptance,
      'dependency_refs': [
        for (final id in ProjectPlanningToolCommandService._intList(
          value['dependency_task_ids'],
          '$path.dependency_task_ids',
        ))
          id.toString(),
      ],
      'milestone_ref': value['milestone_id'] == null
          ? null
          : _requestReferences(
              [
                ProjectPlanningToolCommandService._optionalInt(
                  value['milestone_id'],
                  '$path.milestone_id',
                )!,
              ],
              milestoneRefsByPosition,
              '$path.milestone_id',
            ).single,
      'priority': value['priority'],
      'risk': value['risk'],
      'risk_reduction': value['risk_reduction'],
      'effort': value['effort'],
      'selection_rationale': value['selection_rationale'],
      'constraints': value['constraints'],
      'read_paths': value['read_paths'],
      'write_paths': value['write_paths'],
      'out_of_scope': value['out_of_scope'],
      'context': value['context'],
      'steps': value['steps'],
    };
    return transformed;
  }

  List<String> _requestReferences(
    Iterable<int> numbers,
    Map<int, String>? mapping,
    String path,
  ) {
    final values = <String>[];
    for (final number in numbers) {
      final resolved = mapping?[number] ?? number.toString();
      if (mapping != null && !mapping.containsKey(number)) {
        throw ProjectPlanningToolCommandService._argument(
          'unknown_reference',
          path,
          'Reference $number does not exist in this submission.',
        );
      }
      if (!values.contains(resolved)) values.add(resolved);
    }
    return values;
  }
}
