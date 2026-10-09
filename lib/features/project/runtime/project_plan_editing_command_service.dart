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
}
