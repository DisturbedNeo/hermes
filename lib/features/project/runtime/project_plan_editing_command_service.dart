part of 'project_planning_tools.dart';

class ProjectPlanEditingCommandService {
  ProjectPlanEditingCommandService(this.context);

  final ProjectPlanningContext context;

  void _ensureOpen() {
    if (context.closed) {
      throw ProjectPlanningToolCommandService._argument(
        'planning_closed',
        'tool',
        'The planning draft has already been committed.',
      );
    }
  }

  Map<String, dynamic> submitPlan(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    if (context.project.tasks.isNotEmpty ||
        context.project.criteria.isNotEmpty) {
      throw ProjectPlanningToolCommandService._argument(
        'initial_plan_only',
        'tool',
        'project_submit_plan is only available for an empty project draft.',
      );
    }
    ProjectPlanningToolCommandService._keys(arguments, const {
      'title',
      'refined_goal',
      'constraints',
      'criteria',
      'milestones',
      'tasks',
    });
    final title = ProjectPlanningToolCommandService._requiredString(
      arguments['title'],
      'title',
    );
    final refinedGoal = ProjectPlanningToolCommandService._requiredString(
      arguments['refined_goal'],
      'refined_goal',
    );
    final constraints = arguments.containsKey('constraints')
        ? ProjectPlanningToolCommandService._stringList(
            arguments['constraints'],
            'constraints',
          )
        : null;
    final criteria = ProjectPlanningToolCommandService._maps(
      arguments['criteria'],
      'criteria',
    );
    final milestones = ProjectPlanningToolCommandService._maps(
      arguments['milestones'],
      'milestones',
    );
    final tasks = ProjectPlanningToolCommandService._maps(
      arguments['tasks'],
      'tasks',
      required: true,
    );

    final createdTasks = <Map<String, dynamic>>[];
    context.builder.transaction(() {
      context.setProjectDetails(
        title: title,
        refinedGoal: refinedGoal,
        constraints: constraints,
      );
      final criterionRefsByPosition = <int, String>{};
      for (var index = 0; index < criteria.length; index++) {
        final value = criteria[index];
        ProjectPlanningToolCommandService._keys(value, const {
          'statement',
          'required',
          'verification_mode',
        });
        final id = context.builder.addCriterion(
          statement: ProjectPlanningToolCommandService._requiredString(
            value['statement'],
            'criteria[$index].statement',
          ),
          required:
              ProjectPlanningToolCommandService._optionalBool(
                value['required'],
                'criteria[$index].required',
              ) ??
              true,
          verificationMode:
              ProjectPlanningToolCommandService._enumValue(
                ProjectVerificationMode.values,
                value['verification_mode'],
                'criteria[$index].verification_mode',
              ) ??
              ProjectVerificationMode.mixed,
          commandId: ProjectPlanningToolCommandService._scopedCommandId(
            commandId,
            'criterion:$index',
          ),
        );
        // Root criteria are addressable by their assigned numeric ID. The
        // task parser below can therefore use the same IDs after creation.
        final agentNumber = context.builder.criterionAgentNumberFor(id);
        if (agentNumber == null) {
          throw ProjectPlanningToolCommandService._argument(
            'reference_allocation_failed',
            'criteria[$index]',
            'The criterion could not be assigned an agent reference.',
          );
        }
        criterionRefsByPosition[index + 1] = agentNumber.toString();
      }
      final milestoneRefsByPosition = <int, String>{};
      for (var index = 0; index < milestones.length; index++) {
        final value = milestones[index];
        ProjectPlanningToolCommandService._keys(value, const {
          'title',
          'objective',
          'criterion_ids',
          'exit_conditions',
          'order',
        });
        final id = context.builder.addMilestone(
          title: ProjectPlanningToolCommandService._requiredString(
            value['title'],
            'milestones[$index].title',
          ),
          objective: ProjectPlanningToolCommandService._requiredString(
            value['objective'],
            'milestones[$index].objective',
          ),
          criterionRefs: _requestReferences(
            ProjectPlanningToolCommandService._intList(
              value['criterion_ids'],
              'milestones[$index].criterion_ids',
            ),
            criterionRefsByPosition,
            'milestones[$index].criterion_ids',
          ),
          exitConditions: ProjectPlanningToolCommandService._stringList(
            value['exit_conditions'],
            'milestones[$index].exit_conditions',
          ),
          order: ProjectPlanningToolCommandService._optionalInt(
            value['order'],
            'milestones[$index].order',
          ),
          commandId: ProjectPlanningToolCommandService._scopedCommandId(
            commandId,
            'milestone:$index',
          ),
        );
        milestoneRefsByPosition[index + 1] = context.builder
            .milestoneAgentNumberFor(id)!
            .toString();
      }

      final specs = <ProjectTaskSpec>[];
      for (var index = 0; index < tasks.length; index++) {
        final transformed = _transformTaskInput(
          tasks[index],
          'tasks[$index]',
          createReference: (index + 1).toString(),
          criterionRefsByPosition: criterionRefsByPosition,
          milestoneRefsByPosition: milestoneRefsByPosition,
        );
        final taskInput = Map<String, dynamic>.from(transformed)
          ..remove('inline_criterion_refs');
        specs.add(
          ProjectPlanningToolCommandService._taskSpec(
            taskInput,
            'tasks[$index]',
            requireObjective: true,
          ),
        );
      }
      context.builder.addTasks(
        specs,
        commandId: ProjectPlanningToolCommandService._scopedCommandId(
          commandId,
          'tasks',
        ),
      );
      _throwIfInvalidDraft();
      for (var index = 0; index < specs.length; index++) {
        final id = context.builder.taskIdFor((index + 1).toString());
        createdTasks.add({
          'task_id': context.builder.taskAgentNumberFor(id),
          'position': index + 1,
        });
      }
    });
    return {'tasks': createdTasks};
  }

  Map<String, dynamic> updateProject(
    PlanningArguments arguments,
    String? commandId,
  ) {
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
    return {'updated': true};
  }

  Map<String, dynamic> upsertTask(
    PlanningArguments arguments,
    String? commandId,
  ) {
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
      'disposition',
    });
    final taskNumber = ProjectPlanningToolCommandService._optionalInt(
      arguments['task_id'],
      'task_id',
    );
    late Map<String, dynamic> transformed;
    late String taskId;
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
      } else {
        final existingTaskId = context.builder.taskIdFor(taskNumber.toString());
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
          acceptance: arguments.containsKey('acceptance')
              ? ProjectPlanningToolCommandService._acceptance(
                  transformed['acceptance'],
                  'acceptance',
                )
              : null,
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
          selectionRationale: ProjectPlanningToolCommandService._optionalString(
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
    return {
      'task_id': context.builder.taskAgentNumberFor(taskId),
      'created': taskNumber == null,
    };
  }

  void _throwIfInvalidDraft() {
    final preview = context.builder.preview(
      workspaceRoot: context.workspaceRoot,
    );
    if (preview.validation.valid) return;
    final issues = preview.validation.errors;
    final first = issues.firstOrNull ?? preview.validation.issues.firstOrNull;
    throw ProjectPlanBuilderException(
      code: first?.code ?? 'invalid_plan',
      path: first?.path ?? 'plan',
      message: first?.message ?? 'The plan did not pass validation.',
      details: {
        'errors': [for (final issue in issues) issue.toMap()],
      },
    );
  }

  Map<String, dynamic> _transformTaskInput(
    Map<String, dynamic> value,
    String path, {
    String? createReference,
    Map<int, String>? criterionRefsByPosition,
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

  Map<String, dynamic> addCriteria(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'criteria'});
    final values = ProjectPlanningToolCommandService._maps(
      arguments['criteria'],
      'criteria',
      required: true,
    );
    final added = <Map<String, dynamic>>[];
    context.builder.transaction(() {
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        ProjectPlanningToolCommandService._rejectPersistentFields(
          value,
          'criteria[$index]',
        );
        ProjectPlanningToolCommandService._keys(value, const {
          'ref',
          'statement',
          'required',
          'verification_mode',
        });
        final statement = ProjectPlanningToolCommandService._requiredString(
          value['statement'],
          'criteria[$index].statement',
        );
        final ref =
            ProjectPlanningToolCommandService._optionalString(
              value['ref'],
              'criteria[$index].ref',
            ) ??
            '';
        final required =
            ProjectPlanningToolCommandService._optionalBool(
              value['required'],
              'criteria[$index].required',
            ) ??
            true;
        final verificationMode =
            ProjectPlanningToolCommandService._enumValue(
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
          commandId: ProjectPlanningToolCommandService._partCommandId(
            commandId,
            index,
          ),
        );
        added.add({'id': id, 'ref': ref.isEmpty ? id : ref});
      }
    });
    return {'criteria': added};
  }

  Map<String, dynamic> addMilestones(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'milestones'});
    final values = ProjectPlanningToolCommandService._maps(
      arguments['milestones'],
      'milestones',
      required: true,
    );
    final added = <Map<String, dynamic>>[];
    context.builder.transaction(() {
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        ProjectPlanningToolCommandService._rejectPersistentFields(
          value,
          'milestones[$index]',
        );
        ProjectPlanningToolCommandService._keys(value, const {
          'ref',
          'title',
          'objective',
          'criterion_refs',
          'exit_conditions',
          'order',
        });
        final title = ProjectPlanningToolCommandService._requiredString(
          value['title'],
          'milestones[$index].title',
        );
        final objective = ProjectPlanningToolCommandService._requiredString(
          value['objective'],
          'milestones[$index].objective',
        );
        final ref =
            ProjectPlanningToolCommandService._optionalString(
              value['ref'],
              'milestones[$index].ref',
            ) ??
            '';
        final id = context.builder.addMilestone(
          title: title,
          objective: objective,
          criterionRefs: ProjectPlanningToolCommandService._stringList(
            value['criterion_refs'],
            'milestones[$index].criterion_refs',
          ),
          exitConditions: ProjectPlanningToolCommandService._stringList(
            value['exit_conditions'],
            'milestones[$index].exit_conditions',
          ),
          ref: ref,
          order: ProjectPlanningToolCommandService._optionalInt(
            value['order'],
            'milestones[$index].order',
          ),
          commandId: ProjectPlanningToolCommandService._partCommandId(
            commandId,
            index,
          ),
        );
        added.add({'id': id, 'ref': ref.isEmpty ? id : ref});
      }
    });
    return {'milestones': added};
  }

  Map<String, dynamic> addTask(PlanningArguments arguments, String? commandId) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'ref',
      'title',
      'objective',
      'acceptance',
      'dependency_refs',
      'milestone_ref',
      'out_of_scope',
    });
    final taskArguments = Map<String, dynamic>.from(arguments.toWire());
    final spec = ProjectPlanningToolCommandService._taskSpec(
      taskArguments,
      'task',
      requireObjective: true,
    );
    final id = context.builder.addTask(spec, commandId: commandId);
    return {
      'task': {'id': id, 'ref': spec.ref.trim().isEmpty ? id : spec.ref.trim()},
    };
  }

  Map<String, dynamic> updateTask(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task',
      'title',
      'objective',
      'acceptance',
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
      'out_of_scope',
      'context',
    });
    final task = ProjectPlanningToolCommandService._requiredString(
      arguments['task'],
      'task',
    );
    final updated = context.builder.updateTask(
      task,
      title: ProjectPlanningToolCommandService._optionalString(
        arguments['title'],
        'title',
      ),
      objective: ProjectPlanningToolCommandService._optionalString(
        arguments['objective'],
        'objective',
      ),
      acceptance: arguments.containsKey('acceptance')
          ? ProjectPlanningToolCommandService._acceptance(
              arguments['acceptance'],
              'acceptance',
            )
          : null,
      dependencyRefs: ProjectPlanningToolCommandService._optionalStringList(
        arguments['dependency_refs'],
        'dependency_refs',
      ),
      milestoneRef: ProjectPlanningToolCommandService._optionalString(
        arguments['milestone_ref'],
        'milestone_ref',
      ),
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
      selectionRationale: ProjectPlanningToolCommandService._optionalString(
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
      commandId: commandId,
    );
    return {
      'task': {'id': updated.id, 'ref': task},
    };
  }

  Map<String, dynamic> setDependency(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task',
      'dependency',
      'enabled',
    });
    final task = ProjectPlanningToolCommandService._requiredString(
      arguments['task'],
      'task',
    );
    final dependency = ProjectPlanningToolCommandService._requiredString(
      arguments['dependency'],
      'dependency',
    );
    final enabled =
        ProjectPlanningToolCommandService._optionalBool(
          arguments['enabled'],
          'enabled',
        ) ??
        true;
    context.builder.setDependency(
      taskReference: task,
      dependencyReference: dependency,
      enabled: enabled,
      commandId: commandId,
    );
    return {'task': task, 'dependency': dependency, 'enabled': enabled};
  }

  Map<String, dynamic> setDisposition(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task',
      'disposition',
    });
    final task = ProjectPlanningToolCommandService._requiredString(
      arguments['task'],
      'task',
    );
    final disposition =
        ProjectPlanningToolCommandService._enumValue(
          ProjectPlanTaskDisposition.values,
          arguments['disposition'],
          'disposition',
        ) ??
        (throw ProjectPlanningToolCommandService._argument(
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

  Map<String, dynamic> splitTask(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task',
      'children',
    });
    final task = ProjectPlanningToolCommandService._requiredString(
      arguments['task'],
      'task',
    );
    final values = ProjectPlanningToolCommandService._maps(
      arguments['children'],
      'children',
      required: true,
    );
    final children = [
      for (var index = 0; index < values.length; index++)
        ProjectPlanningToolCommandService._taskSpec(
          values[index],
          'children[$index]',
        ),
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

  Map<String, dynamic> retryTask(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task',
      'ref',
      'title',
      'objective',
    });
    final task = ProjectPlanningToolCommandService._requiredString(
      arguments['task'],
      'task',
    );
    final ref =
        ProjectPlanningToolCommandService._optionalString(
          arguments['ref'],
          'ref',
        ) ??
        '';
    final id = context.builder.retryTask(
      taskReference: task,
      ref: ref,
      title: ProjectPlanningToolCommandService._optionalString(
        arguments['title'],
        'title',
      ),
      objective: ProjectPlanningToolCommandService._optionalString(
        arguments['objective'],
        'objective',
      ),
      commandId: commandId,
    );
    return {
      'source_task': task,
      'task': {'id': id, 'ref': ref.isEmpty ? id : ref},
    };
  }

  Map<String, dynamic> addNote(PlanningArguments arguments, String? commandId) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'kind',
      'content',
      'source_id',
    });
    final kind =
        ProjectPlanningToolCommandService._enumValue(
          ProjectMemoryKind.values,
          arguments['kind'],
          'kind',
        ) ??
        (throw ProjectPlanningToolCommandService._argument(
          'missing_argument',
          'kind',
          'A note kind is required.',
        ));
    final id = context.builder.addNote(
      kind: kind,
      content: ProjectPlanningToolCommandService._requiredString(
        arguments['content'],
        'content',
      ),
      sourceId: ProjectPlanningToolCommandService._optionalString(
        arguments['source_id'],
        'source_id',
      ),
      commandId: commandId,
    );
    return {
      'note': {'id': id, 'kind': kind.name},
    };
  }

  Map<String, dynamic> requestDecision(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'question'});
    final id = context.builder.requestUserDecision(
      question: ProjectPlanningToolCommandService._requiredString(
        arguments['question'],
        'question',
      ),
      commandId: commandId,
    );
    return {
      'question': {'id': id},
    };
  }
}
