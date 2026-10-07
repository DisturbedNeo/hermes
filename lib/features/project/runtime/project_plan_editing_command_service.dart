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
      'criterion_refs',
      'dependency_refs',
      'milestone_ref',
      'done_criteria',
      'out_of_scope',
      'checks',
    });
    final taskArguments = Map<String, dynamic>.from(arguments.toWire())
      ..remove('checks');
    final spec = ProjectPlanningToolCommandService._taskSpec(
      taskArguments,
      'task',
      requireObjective: true,
    );
    final checks = ProjectPlanningToolCommandService._checkSpecs(
      arguments['checks'],
      'checks',
    );
    final id = context.builder.addTaskWithChecks(
      spec,
      checks: checks,
      commandId: commandId,
    );
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
      'criterion_refs',
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
      'done_criteria',
      'out_of_scope',
      'context',
      'expected_artifacts',
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
      criterionRefs: ProjectPlanningToolCommandService._optionalStringList(
        arguments['criterion_refs'],
        'criterion_refs',
      ),
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
      doneCriteria: ProjectPlanningToolCommandService._optionalStringList(
        arguments['done_criteria'],
        'done_criteria',
      ),
      outOfScope: ProjectPlanningToolCommandService._optionalStringList(
        arguments['out_of_scope'],
        'out_of_scope',
      ),
      context: ProjectPlanningToolCommandService._optionalStringList(
        arguments['context'],
        'context',
      ),
      expectedArtifacts: ProjectPlanningToolCommandService._optionalArtifacts(
        arguments['expected_artifacts'],
        'expected_artifacts',
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

  Map<String, dynamic> addCheck(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'task',
      'kind',
      'command',
      'working_directory',
      'criterion_refs',
      'required',
      'description',
    });
    final kind = ProjectPlanningToolCommandService._requiredString(
      arguments['kind'],
      'kind',
    );
    if (kind != 'command') {
      throw ProjectPlanningToolCommandService._argument(
        'invalid_check',
        'kind',
        'Only command checks are supported by the project planning tools.',
      );
    }
    final task = ProjectPlanningToolCommandService._requiredString(
      arguments['task'],
      'task',
    );
    final command = ProjectPlanningToolCommandService._requiredString(
      arguments['command'],
      'command',
    );
    final id = context.builder.addCommandCheck(
      taskReference: task,
      command: command,
      workingDirectory:
          ProjectPlanningToolCommandService._optionalString(
            arguments['working_directory'],
            'working_directory',
          ) ??
          '.',
      criterionRefs: ProjectPlanningToolCommandService._optionalStringList(
        arguments['criterion_refs'],
        'criterion_refs',
      ),
      required:
          ProjectPlanningToolCommandService._optionalBool(
            arguments['required'],
            'required',
          ) ??
          true,
      description: ProjectPlanningToolCommandService._optionalString(
        arguments['description'],
        'description',
      ),
      commandId: commandId,
    );
    return {
      'task': task,
      'check': {'id': 'command_passes', 'expectation_id': id},
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
