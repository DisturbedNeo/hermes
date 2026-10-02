part of 'project_planning_tools.dart';

class ProjectWorkspacePlanningCommandService {
  ProjectWorkspacePlanningCommandService(this.context);

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

  Map<String, dynamic> setWorkspaceOrientation(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'orientation'});
    context.builder.setWorkspaceOrientation(
      ProjectPlanningToolCommandService._optionalString(
            arguments['orientation'],
            'orientation',
          ) ??
          '',
      commandId: commandId,
    );
    return {
      'orientation': context.builder
          .preview(workspaceRoot: context.workspaceRoot)
          .proposal
          .workspaceGraph
          .orientation,
    };
  }

  Map<String, dynamic> addWorkspaceNodes(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'nodes'});
    final values = ProjectPlanningToolCommandService._maps(
      arguments['nodes'],
      'nodes',
      required: true,
    );
    final specs = <ProjectWorkspaceNodeSpec>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      ProjectPlanningToolCommandService._rejectPersistentFields(
        value,
        'nodes[$index]',
      );
      ProjectPlanningToolCommandService._keys(value, const {
        'ref',
        'type',
        'title',
        'description',
        'aliases',
        'tags',
        'references',
      });
      specs.add(
        ProjectWorkspaceNodeSpec(
          ref:
              ProjectPlanningToolCommandService._optionalString(
                value['ref'],
                'nodes[$index].ref',
              ) ??
              '',
          type:
              ProjectPlanningToolCommandService._optionalString(
                value['type'],
                'nodes[$index].type',
              ) ??
              '',
          title:
              ProjectPlanningToolCommandService._optionalString(
                value['title'],
                'nodes[$index].title',
              ) ??
              '',
          description:
              ProjectPlanningToolCommandService._optionalString(
                value['description'],
                'nodes[$index].description',
              ) ??
              '',
          aliases: ProjectPlanningToolCommandService._stringList(
            value['aliases'],
            'nodes[$index].aliases',
          ),
          tags: ProjectPlanningToolCommandService._stringList(
            value['tags'],
            'nodes[$index].tags',
          ),
          references: ProjectPlanningToolCommandService._stringList(
            value['references'],
            'nodes[$index].references',
          ),
        ),
      );
    }
    final ids = context.builder.addWorkspaceNodes(specs, commandId: commandId);
    return {
      'nodes': [
        for (final id in ids) {'id': id},
      ],
    };
  }

  Map<String, dynamic> updateWorkspaceNode(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'node',
      'type',
      'title',
      'description',
      'aliases',
      'tags',
      'references',
    });
    final id = context.builder.updateWorkspaceNode(
      ProjectPlanningToolCommandService._requiredString(
        arguments['node'],
        'node',
      ),
      type: ProjectPlanningToolCommandService._optionalString(
        arguments['type'],
        'type',
      ),
      title: ProjectPlanningToolCommandService._optionalString(
        arguments['title'],
        'title',
      ),
      description: ProjectPlanningToolCommandService._optionalString(
        arguments['description'],
        'description',
      ),
      aliases: arguments.containsKey('aliases')
          ? ProjectPlanningToolCommandService._stringList(
              arguments['aliases'],
              'aliases',
            )
          : null,
      tags: arguments.containsKey('tags')
          ? ProjectPlanningToolCommandService._stringList(
              arguments['tags'],
              'tags',
            )
          : null,
      references: arguments.containsKey('references')
          ? ProjectPlanningToolCommandService._stringList(
              arguments['references'],
              'references',
            )
          : null,
      commandId: commandId,
    );
    return {
      'node': {'id': id},
    };
  }

  Map<String, dynamic> addWorkspaceEdges(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'edges'});
    final values = ProjectPlanningToolCommandService._maps(
      arguments['edges'],
      'edges',
      required: true,
    );
    final specs = <ProjectWorkspaceEdgeSpec>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      ProjectPlanningToolCommandService._rejectPersistentFields(
        value,
        'edges[$index]',
      );
      ProjectPlanningToolCommandService._keys(value, const {
        'ref',
        'source_ref',
        'target_ref',
        'label',
        'description',
      });
      specs.add(
        ProjectWorkspaceEdgeSpec(
          ref:
              ProjectPlanningToolCommandService._optionalString(
                value['ref'],
                'edges[$index].ref',
              ) ??
              '',
          sourceRef: ProjectPlanningToolCommandService._requiredString(
            value['source_ref'],
            'edges[$index].source_ref',
          ),
          targetRef: ProjectPlanningToolCommandService._requiredString(
            value['target_ref'],
            'edges[$index].target_ref',
          ),
          label: ProjectPlanningToolCommandService._requiredString(
            value['label'],
            'edges[$index].label',
          ),
          description:
              ProjectPlanningToolCommandService._optionalString(
                value['description'],
                'edges[$index].description',
              ) ??
              '',
        ),
      );
    }
    final ids = context.builder.addWorkspaceEdges(specs, commandId: commandId);
    return {
      'edges': [
        for (final id in ids) {'id': id},
      ],
    };
  }

  Map<String, dynamic> updateWorkspaceEdge(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {
      'edge',
      'source_ref',
      'target_ref',
      'label',
      'description',
    });
    final id = context.builder.updateWorkspaceEdge(
      ProjectPlanningToolCommandService._requiredString(
        arguments['edge'],
        'edge',
      ),
      sourceReference: ProjectPlanningToolCommandService._optionalString(
        arguments['source_ref'],
        'source_ref',
      ),
      targetReference: ProjectPlanningToolCommandService._optionalString(
        arguments['target_ref'],
        'target_ref',
      ),
      label: ProjectPlanningToolCommandService._optionalString(
        arguments['label'],
        'label',
      ),
      description: ProjectPlanningToolCommandService._optionalString(
        arguments['description'],
        'description',
      ),
      commandId: commandId,
    );
    return {
      'edge': {'id': id},
    };
  }

  Map<String, dynamic> removeWorkspaceItem(
    PlanningArguments arguments,
    String? commandId,
  ) {
    _ensureOpen();
    ProjectPlanningToolCommandService._keys(arguments, const {'kind', 'ref'});
    final kind = ProjectPlanningToolCommandService._requiredString(
      arguments['kind'],
      'kind',
    );
    final reference = ProjectPlanningToolCommandService._requiredString(
      arguments['ref'],
      'ref',
    );
    switch (kind) {
      case 'node':
        context.builder.removeWorkspaceNode(reference, commandId: commandId);
      case 'edge':
        context.builder.removeWorkspaceEdge(reference, commandId: commandId);
      default:
        throw ProjectPlanningToolCommandService._argument(
          'invalid_argument',
          'kind',
          'kind must be either node or edge.',
        );
    }
    return {
      'removed': {'kind': kind, 'ref': reference},
    };
  }
}
