part of 'project_planning_tools.dart';

class ProjectPlanningToolCommandService {
  ProjectPlanningToolCommandService({
    required this.context,
    this.profile = ProjectPlanningToolProfile.maintenance,
  }) {
    _workspaceCommands = ProjectWorkspacePlanningCommandService(context);
    _planCommands = ProjectPlanEditingCommandService(context);
  }

  final ProjectPlanningContext context;
  final ProjectPlanningToolProfile profile;
  late final ProjectWorkspacePlanningCommandService _workspaceCommands;
  late final ProjectPlanEditingCommandService _planCommands;

  String get terminalToolId => 'plan_finalize';

  String get closedCode => 'planning_closed';

  String get closedMessage =>
      'This planning session has already been finalized.';

  List<ToolDefinition> get toolDefinitions {
    final core = <ToolDefinition>[
      _projectUpdateDefinition,
      _taskAddDefinition,
      _taskUpdateDefinition,
      _taskRemoveDefinition,
      _projectRequestDecisionDefinition,
      _projectFinalizeDefinition,
    ];
    if (profile == ProjectPlanningToolProfile.graphMaintenance) {
      return [
        _setWorkspaceOrientationDefinition,
        _addWorkspaceNodesDefinition,
        _updateWorkspaceNodeDefinition,
        _addWorkspaceEdgesDefinition,
        _updateWorkspaceEdgeDefinition,
        _removeWorkspaceItemDefinition,
        _projectFinalizeDefinition,
      ];
    }
    if (profile == ProjectPlanningToolProfile.split) {
      return [
        _taskAddDefinition,
        _taskRemoveDefinition,
        _projectFinalizeDefinition,
      ];
    }
    return core;
  }

  /// The planning registry has no route to workspace mutation.
  bool get allowsWorkspaceMutation => false;

  Future<PlanningResponse> dispatch(
    String toolId,
    PlanningArguments arguments, {
    String? commandId,
  }) async {
    if (!_allows(toolId)) {
      throw _argument(
        'tool_unavailable',
        'tool',
        'Project planning tool $toolId is not available in the '
            '${profile.name} planning profile.',
      );
    }
    final result = switch (toolId) {
      'project_update' => await _planCommands.updateProject(
        arguments,
        commandId,
      ),
      'task_add' => await _planCommands.addTask(arguments, commandId),
      'task_update' => await _planCommands.updateTask(arguments, commandId),
      'task_remove' => await _planCommands.removeTask(arguments, commandId),
      'project_request_user_decision' =>
        await _planCommands.requestUserDecision(arguments, commandId),
      'plan_set_workspace_orientation' =>
        _workspaceCommands.setWorkspaceOrientation(arguments, commandId),
      'plan_add_workspace_nodes' => _workspaceCommands.addWorkspaceNodes(
        arguments,
        commandId,
      ),
      'plan_update_workspace_node' => _workspaceCommands.updateWorkspaceNode(
        arguments,
        commandId,
      ),
      'plan_add_workspace_edges' => _workspaceCommands.addWorkspaceEdges(
        arguments,
        commandId,
      ),
      'plan_update_workspace_edge' => _workspaceCommands.updateWorkspaceEdge(
        arguments,
        commandId,
      ),
      'plan_remove_workspace_item' => _workspaceCommands.removeWorkspaceItem(
        arguments,
        commandId,
      ),
      'plan_finalize' => await _finalize(arguments),
      _ => throw _argument(
        'unknown_tool',
        'tool',
        'Unknown project planning tool $toolId.',
      ),
    };
    final response = <String, dynamic>{'ok': true, ...result};
    return PlanningResponse.fromWire(response);
  }

  bool _allows(String toolId) {
    if (toolId == 'plan_finalize') {
      return true;
    }
    if (const {
      'project_update',
      'task_add',
      'task_update',
      'task_remove',
      'project_request_user_decision',
    }.contains(toolId)) {
      return profile == ProjectPlanningToolProfile.bootstrap ||
          profile == ProjectPlanningToolProfile.maintenance;
    }
    return switch (profile) {
      ProjectPlanningToolProfile.bootstrap => false,
      ProjectPlanningToolProfile.maintenance => false,
      ProjectPlanningToolProfile.graphMaintenance => const {
        'plan_set_workspace_orientation',
        'plan_add_workspace_nodes',
        'plan_update_workspace_node',
        'plan_add_workspace_edges',
        'plan_update_workspace_edge',
        'plan_remove_workspace_item',
        'plan_finalize',
      }.contains(toolId),
      ProjectPlanningToolProfile.split => const {
        'task_add',
        'task_remove',
        'plan_finalize',
      }.contains(toolId),
    };
  }

  Map<String, dynamic> domainError(Object error) {
    if (error is ProjectPlanBuilderException) {
      return _error(
        code: error.code,
        path: _wirePath(error.path),
        message: error.message,
        extra: error.details.isEmpty ? const {} : {'details': error.details},
      );
    }
    return _error(
      code: 'planning_tool_failed',
      path: 'tool',
      message: 'The planning command could not be applied: $error',
    );
  }

  Future<Map<String, dynamic>> _finalize(PlanningArguments arguments) async {
    _ensureOpen();
    _keys(arguments, const {});
    if (context.currentProject.openQuestions.isNotEmpty) {
      throw _argument(
        'awaiting_user_input',
        'project',
        'Resolve all pending project questions before finalizing.',
      );
    }
    final preview = context.builder.preview(
      workspaceRoot: context.workspaceRoot,
      ensureBootstrapMilestone: false,
    );
    if (!preview.validation.valid) {
      final issue =
          preview.validation.errors.firstOrNull ??
          preview.validation.issues.first;
      throw ProjectPlanBuilderException(
        code: issue.code,
        path: issue.path,
        message: issue.message,
      );
    }
    final transitioned = context.currentProject.status == ProjectStatus.active
        ? context.currentProject
        : const ProjectLifecycleService()
              .transition(
                snapshot: context.currentProject,
                to: ProjectStatus.active,
                trigger: ProjectLifecycleTrigger.planRevision,
                reason: 'Project planning finalized.',
              )
              .project;
    final persisted = context.persistProject == null
        ? transitioned
        : await context.persistProject!(context.workspaceRoot, transitioned);
    context.currentProject = persisted;
    context.committedProject = persisted;
    context.rebase(persisted);
    context.closed = true;
    return {
      'finalized': true,
      'project': {
        'id': persisted.id,
        'revision': persisted.persistenceRevision,
        'status': persisted.status.wire,
      },
      'persistence_revision': persisted.persistenceRevision,
    };
  }

  static ProjectTaskSpec _taskSpec(
    Map<String, dynamic> value,
    String path, {
    bool requireObjective = false,
  }) {
    _rejectPersistentFields(value, path);
    _keys(value, const {
      'ref',
      'title',
      'objective',
      'acceptance',
      'dependency_refs',
      'milestone_ref',
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
    final ref = _optionalString(value['ref'], '$path.ref') ?? '';
    final title = _optionalString(value['title'], '$path.title') ?? '';
    final objective =
        _optionalString(value['objective'], '$path.objective') ?? '';
    final acceptance = _acceptance(value['acceptance'], '$path.acceptance');
    final outOfScope = _stringList(value['out_of_scope'], '$path.out_of_scope');
    final steps = _steps(value['steps'], '$path.steps');
    final missingFields = <String>[];
    if (requireObjective
        ? objective.isEmpty
        : title.isEmpty && objective.isEmpty) {
      missingFields.add(requireObjective ? 'objective' : 'objective_or_title');
    }
    if (acceptance.isEmpty) {
      missingFields.add('acceptance');
    }
    if (outOfScope.where((item) => item.isNotEmpty).isEmpty) {
      missingFields.add('out_of_scope');
    }
    if (steps.isEmpty) {
      missingFields.add('steps');
    }
    if (missingFields.isNotEmpty) {
      throw _argument(
        'invalid_task_spec',
        path,
        'Submit the complete task object in one call. Arguments from previous '
            'calls are not merged.',
        details: {
          'missing_fields': missingFields,
          'instruction':
              'Resubmit the complete task object; do not send only the missing fields.',
        },
      );
    }
    return ProjectTaskSpec(
      ref: ref,
      title: title,
      objective: objective,
      steps: steps,
      acceptance: acceptance,
      dependencyRefs: _stringList(
        value['dependency_refs'],
        '$path.dependency_refs',
      ),
      milestoneRef: _optionalString(
        value['milestone_ref'],
        '$path.milestone_ref',
      ),
      priority:
          _enumValue(
            TaskPriority.values,
            value['priority'],
            '$path.priority',
          ) ??
          TaskPriority.normal,
      risk:
          _enumValue(TaskRisk.values, value['risk'], '$path.risk') ??
          TaskRisk.unknown,
      riskReduction:
          _enumValue(
            ProjectRiskReduction.values,
            value['risk_reduction'],
            '$path.risk_reduction',
          ) ??
          ProjectRiskReduction.none,
      effort:
          _enumValue(TaskEffort.values, value['effort'], '$path.effort') ??
          TaskEffort.small,
      selectionRationale:
          _optionalString(
            value['selection_rationale'],
            '$path.selection_rationale',
          ) ??
          '',
      constraints: _stringList(value['constraints'], '$path.constraints'),
      readPaths: _stringList(value['read_paths'], '$path.read_paths'),
      writePaths: _stringList(value['write_paths'], '$path.write_paths'),
      outOfScope: outOfScope,
      context: _stringList(value['context'], '$path.context'),
    );
  }

  static List<AcceptanceItem> _acceptance(Object? value, String path) {
    if (value == null) return const [];
    final maps = _maps(value, path, required: true);
    final refs = <String>{};
    final items = <AcceptanceItem>[];
    for (var index = 0; index < maps.length; index++) {
      final item = maps[index];
      _rejectPersistentFields(item, '$path[$index]');
      _keys(item, const {'ref', 'statement', 'criterion_ids', 'verifiers'});
      final ref = _requiredString(item['ref'], '$path[$index].ref');
      if (!refs.add(ref)) {
        throw _argument(
          'duplicate_acceptance_ref',
          '$path[$index].ref',
          'Acceptance ref $ref is duplicated.',
        );
      }
      final statement = _requiredString(
        item['statement'],
        '$path[$index].statement',
      );
      final criterionIds = [
        for (final id in _intList(
          item['criterion_ids'],
          '$path[$index].criterion_ids',
        ))
          id.toString(),
      ];
      final verifierMaps = _maps(
        item['verifiers'],
        '$path[$index].verifiers',
        required: true,
      );
      final verifiers = <AcceptanceVerifier>[];
      var requiredVerifierCount = 0;
      for (
        var verifierIndex = 0;
        verifierIndex < verifierMaps.length;
        verifierIndex++
      ) {
        final verifier = verifierMaps[verifierIndex];
        _keys(verifier, const {
          'kind',
          'required',
          'command',
          'working_directory',
          'path',
          'artifact_kind',
          'description',
        });
        final kind = _enumValue(
          AcceptanceVerifierKind.values,
          verifier['kind'],
          '$path[$index].verifiers[$verifierIndex].kind',
        );
        final required =
            _optionalBool(
              verifier['required'],
              '$path[$index].verifiers[$verifierIndex].required',
            ) ??
            true;
        if (required) requiredVerifierCount++;
        final parsed = AcceptanceVerifier(
          kind: kind ?? AcceptanceVerifierKind.command,
          required: required,
          command: _optionalString(
            verifier['command'],
            '$path[$index].verifiers[$verifierIndex].command',
          ),
          workingDirectory:
              _optionalString(
                verifier['working_directory'],
                '$path[$index].verifiers[$verifierIndex].working_directory',
              ) ??
              '.',
          path: _optionalString(
            verifier['path'],
            '$path[$index].verifiers[$verifierIndex].path',
          ),
          artifactKind:
              _optionalString(
                verifier['artifact_kind'],
                '$path[$index].verifiers[$verifierIndex].artifact_kind',
              ) ??
              'file',
          description: _optionalString(
            verifier['description'],
            '$path[$index].verifiers[$verifierIndex].description',
          ),
        );
        if (!parsed.hasConfiguration) {
          throw _argument(
            'invalid_acceptance_verifier',
            '$path[$index].verifiers[$verifierIndex]',
            'The verifier does not contain the fields required for its kind.',
          );
        }
        verifiers.add(parsed);
      }
      if (requiredVerifierCount == 0) {
        throw _argument(
          'missing_required_verifier',
          '$path[$index].verifiers',
          'Each acceptance item needs at least one required verifier.',
        );
      }
      items.add(
        AcceptanceItem(
          ref: ref,
          statement: statement,
          criterionIds: criterionIds,
          verifiers: verifiers,
        ),
      );
    }
    return items;
  }

  static List<ProjectTaskStepSpec> _steps(Object? value, String path) {
    if (value == null) return const [];
    final maps = _maps(value, path, required: true);
    return [
      for (var index = 0; index < maps.length; index++)
        () {
          final item = maps[index];
          _rejectPersistentFields(item, '$path[$index]');
          _keys(item, const {
            'ref',
            'title',
            'objective',
            'instructions',
            'may_edit_files',
            'artifacts',
            'acceptance_refs',
          });
          final objective = _requiredString(
            item['objective'],
            '$path[$index].objective',
          );
          final artifacts = _maps(item['artifacts'], '$path[$index].artifacts');
          return ProjectTaskStepSpec(
            ref: _optionalString(item['ref'], '$path[$index].ref') ?? '',
            title: _optionalString(item['title'], '$path[$index].title') ?? '',
            objective: objective,
            instructions: _stringList(
              item['instructions'],
              '$path[$index].instructions',
            ),
            mayEditFiles:
                _optionalBool(
                  item['may_edit_files'],
                  '$path[$index].may_edit_files',
                ) ??
                false,
            artifacts: [
              for (
                var artifactIndex = 0;
                artifactIndex < artifacts.length;
                artifactIndex++
              )
                () {
                  _rejectPersistentFields(
                    artifacts[artifactIndex],
                    '$path[$index].artifacts[$artifactIndex]',
                  );
                  _keys(artifacts[artifactIndex], const {
                    'path',
                    'description',
                    'kind',
                  });
                  return ProjectTaskArtifactSpec(
                    path: _requiredString(
                      artifacts[artifactIndex]['path'],
                      '$path[$index].artifacts[$artifactIndex].path',
                    ),
                    description: _optionalString(
                      artifacts[artifactIndex]['description'],
                      '$path[$index].artifacts[$artifactIndex].description',
                    ),
                    kind:
                        _optionalString(
                          artifacts[artifactIndex]['kind'],
                          '$path[$index].artifacts[$artifactIndex].kind',
                        ) ??
                        'file',
                  );
                }(),
            ],
            acceptanceRefs: _stringList(
              item['acceptance_refs'],
              '$path[$index].acceptance_refs',
            ),
          );
        }(),
    ];
  }

  static void _rejectPersistentFields(Map<String, dynamic> value, String path) {
    const fields = {
      'id',
      'status',
      'created_at',
      'createdAt',
      'updated_at',
      'updatedAt',
      'runs',
      'failure',
      'gates',
      'completed_at',
      'completedAt',
      'task_id',
      'taskId',
      'revision',
      'fingerprint',
      'revisionIntroduced',
      'revisionUpdated',
      'evidence',
      'currentStepId',
    };
    for (final field in fields) {
      if (value.containsKey(field)) {
        throw _argument(
          'invalid_argument',
          '$path.$field',
          'Creation tools generate persistent fields; the field is not accepted.',
        );
      }
    }
  }

  void _ensureOpen() {
    if (context.closed) {
      throw _argument(
        'planning_closed',
        'tool',
        'This planning session has already been finalized.',
      );
    }
  }

  static void _keys(Object value, Set<String> allowed) {
    final keys = value is PlanningArguments
        ? value.keys
        : (value as Map<String, dynamic>).keys;
    for (final key in keys) {
      if (!allowed.contains(key)) {
        throw _argument(
          'invalid_argument',
          key,
          'Argument $key is not accepted by this planning tool.',
        );
      }
    }
  }

  static List<Map<String, dynamic>> _maps(
    Object? value,
    String path, {
    bool required = false,
  }) {
    if (value == null) {
      if (required) {
        throw _argument(
          'missing_argument',
          path,
          'A non-empty list is required.',
        );
      }
      return const [];
    }
    if (value is! List || value.isEmpty && required) {
      throw _argument('invalid_argument', path, 'Expected a non-empty list.');
    }
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! Map) {
        throw _argument(
          'invalid_argument',
          '$path[$index]',
          'Expected an object.',
        );
      }
      final map = <String, dynamic>{};
      for (final entry in item.entries) {
        if (entry.key is! String) {
          throw _argument(
            'invalid_argument',
            '$path[$index]',
            'Object field names must be strings.',
          );
        }
        map[entry.key as String] = entry.value;
      }
      result.add(map);
    }
    return result;
  }

  static String _requiredString(Object? value, String path) {
    if (value is! String || value.trim().isEmpty) {
      throw _argument(
        'invalid_argument',
        path,
        'A non-empty string is required.',
      );
    }
    return value.trim();
  }

  static String? _optionalString(Object? value, String path) {
    if (value == null) return null;
    if (value is! String) {
      throw _argument('invalid_argument', path, 'Expected a string.');
    }
    return value.trim();
  }

  static List<String> _stringList(Object? value, String path) {
    if (value == null) return const [];
    if (value is! List) {
      throw _argument('invalid_argument', path, 'Expected a list of strings.');
    }
    final result = <String>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! String) {
        throw _argument(
          'invalid_argument',
          '$path[$index]',
          'Expected a string.',
        );
      }
      result.add(item.trim());
    }
    return result;
  }

  static List<String>? _optionalStringList(Object? value, String path) {
    if (value == null) return null;
    return _stringList(value, path);
  }

  static List<int> _intList(Object? value, String path) {
    if (value == null) return const [];
    if (value is! List) {
      throw _argument('invalid_argument', path, 'Expected a list of integers.');
    }
    final result = <int>[];
    for (var index = 0; index < value.length; index++) {
      final item = value[index];
      if (item is! int || item < 1) {
        throw _argument(
          'invalid_argument',
          '$path[$index]',
          'Expected a positive integer.',
        );
      }
      result.add(item);
    }
    return result;
  }

  static bool? _optionalBool(Object? value, String path) {
    if (value == null) return null;
    if (value is! bool) {
      throw _argument('invalid_argument', path, 'Expected a boolean.');
    }
    return value;
  }

  static int? _optionalInt(Object? value, String path) {
    if (value == null) return null;
    if (value is! int) {
      throw _argument('invalid_argument', path, 'Expected an integer.');
    }
    return value;
  }

  static T? _enumValue<T extends Enum>(
    List<T> values,
    Object? value,
    String path,
  ) {
    if (value == null) return null;
    if (value is! String) {
      throw _argument('invalid_argument', path, 'Expected an enum string.');
    }
    final normalised = value.trim().toLowerCase().replaceAll('-', '_');
    for (final candidate in values) {
      if (candidate.name == normalised ||
          candidate.name.toLowerCase() == normalised ||
          candidate.name.toLowerCase() == normalised.replaceAll('_', '')) {
        return candidate;
      }
    }
    throw _argument(
      'invalid_argument',
      path,
      'Unsupported value $value. Expected one of ${values.map((item) => item.name).join(', ')}.',
    );
  }

  static String? _scopedCommandId(String? commandId, String scope) =>
      commandId == null ? null : '$commandId:$scope';

  static _PlanningArgumentException _argument(
    String code,
    String path,
    String message, {
    Map<String, dynamic> details = const {},
  }) => _PlanningArgumentException(code, path, message, details: details);

  static String _wirePath(String path) => path
      .replaceAll('dependencyRefs', 'dependency_refs')
      .replaceAll('milestoneRef', 'milestone_ref')
      .replaceAll('outOfScope', 'out_of_scope')
      .replaceAll('readPaths', 'read_paths')
      .replaceAll('writePaths', 'write_paths');

  static Map<String, dynamic> _error({
    required String code,
    required String path,
    required String message,
    Map<String, dynamic> extra = const {},
  }) => {'ok': false, 'code': code, 'path': path, 'message': message, ...extra};
}
