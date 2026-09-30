import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/shared_kernel/model_json.dart';
import 'package:hermes/features/project/runtime/project_plan_builder.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_plan_validator.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/project/runtime/project_workspace_graph_service.dart';
import 'package:hermes/features/project/runtime/project_view_service.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  test('round trips non-code workspace nodes and relationships', () {
    final project = _project(
      workspaceGraph: ProjectWorkspaceGraph(
        orientation: 'The story moves from the archive to the final hearing.',
        nodes: [
          ProjectWorkspaceNode(
            id: 'archive',
            type: 'location',
            title: 'The archive',
            description: 'Where the missing ledger is discovered.',
            references: const ['chapter:3', 'https://example.test/archive'],
            sourceType: ProjectWorkspaceSourceType.user,
            confidence: ProjectWorkspaceConfidence.confirmed,
            protected: true,
            createdAt: now,
            updatedAt: now,
          ),
          ProjectWorkspaceNode(
            id: 'hearing',
            type: 'event',
            title: 'Final hearing',
            description: 'The project resolves the central accusation.',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        edges: [
          ProjectWorkspaceEdge(
            id: 'leads_to',
            sourceNodeId: 'archive',
            targetNodeId: 'hearing',
            label: 'reveals evidence for',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        updatedAt: now,
      ),
    );

    final decoded = ModelJson.decode<ProjectDocument>(
      ModelJson.encode(project),
    );

    expect(decoded.workspaceGraph.orientation, contains('archive'));
    expect(decoded.workspaceGraph.nodes.first.title, 'The archive');
    expect(decoded.workspaceGraph.nodes.first.protected, isTrue);
    expect(decoded.workspaceGraph.edges.single.label, 'reveals evidence for');
  });

  test('legacy project snapshots decode with an empty workspace graph', () {
    final legacy = Map<String, dynamic>.from(ModelJson.encode(_project()));
    legacy.remove('workspaceGraph');

    final decoded = ModelJson.decode<ProjectDocument>(legacy);

    expect(decoded.workspaceGraph.orientation, isEmpty);
    expect(decoded.workspaceGraph.nodes, isEmpty);
    expect(decoded.workspaceGraph.edges, isEmpty);
  });

  test('selects relevant graph context within a deterministic budget', () {
    final project = _project(
      workspaceGraph: ProjectWorkspaceGraph(
        orientation: 'Characters connect through a chain of evidence.',
        nodes: [
          _node('alice', 'character', 'Alice', 'Witness in the report.'),
          _node(
            'report',
            'artifact',
            'Evidence report',
            'Contains the key finding.',
          ),
          _node(
            'unrelated',
            'character',
            'Unrelated character',
            'Not connected.',
          ),
        ],
        edges: [
          ProjectWorkspaceEdge(
            id: 'evidence',
            sourceNodeId: 'alice',
            targetNodeId: 'report',
            label: 'authored',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        updatedAt: now,
      ),
    );

    final selection = const ProjectWorkspaceContextService().selectContext(
      project: project,
      task: project.tasks.single,
      maxCharacters: 500,
    );

    expect(selection.orientation, isNotEmpty);
    expect(selection.usedCharacters, lessThanOrEqualTo(500));
    expect(selection.nodes.map((node) => node.id), contains('report'));
    expect(selection.edges.single.label, 'authored');
  });

  test(
    'uses node IDs as deterministic tie-breakers and exposes relationships',
    () {
      final project = _project(
        includeTask: false,
        workspaceGraph: ProjectWorkspaceGraph(
          nodes: [
            _node('b', 'concept', 'B', 'A concept.'),
            _node('a', 'concept', 'A', 'A concept.'),
          ],
          edges: [
            ProjectWorkspaceEdge(
              id: 'a_to_b',
              sourceNodeId: 'a',
              targetNodeId: 'b',
              label: 'relates to',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          updatedAt: now,
        ),
      );

      final selection = const ProjectWorkspaceContextService().selectContext(
        project: project,
        maxCharacters: 500,
      );
      final view = const ProjectViewService().query(
        project,
        workspaceQuery: 'A',
      );

      expect(selection.nodes.map((node) => node.id).take(2), ['a', 'b']);
      expect(view['workspaceGraph'], isA<Map>());
      expect((view['workspaceGraph'] as Map)['node_count'], 2);
      expect((view['workspaceGraph'] as Map)['edge_count'], 1);
      final details = view['workspace_detail'] as List;
      expect(details, isNotEmpty);
      expect((details.first as Map)['relationships'], isNotEmpty);
    },
  );

  test('context selection never exceeds the hard node and edge caps', () {
    final nodes = [
      for (var index = 0; index < 30; index++)
        _node('node_$index', 'concept', 'Concept $index', 'Durable concept.'),
    ];
    final edges = [
      for (var index = 0; index < 60; index++)
        ProjectWorkspaceEdge(
          id: 'edge_$index',
          sourceNodeId: nodes[index % nodes.length].id,
          targetNodeId: nodes[(index + 1) % nodes.length].id,
          label: 'relates to',
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final selection = const ProjectWorkspaceContextService().selectContext(
      project: _project(
        includeTask: false,
        workspaceGraph: ProjectWorkspaceGraph(nodes: nodes, edges: edges),
      ),
      maxCharacters: 100000,
      maxSelectedNodes: 100,
      maxSelectedEdges: 100,
    );

    expect(selection.nodes, hasLength(24));
    expect(selection.edges.length, lessThanOrEqualTo(48));
    expect(selection.truncated, isTrue);
  });

  test('workspace context and details retain provenance identifiers', () {
    final graph = ProjectWorkspaceGraph(
      nodes: [
        ProjectWorkspaceNode(
          id: 'source',
          type: 'source',
          title: 'Interview',
          description: 'Primary evidence.',
          aliases: const ['transcript'],
          sourceType: ProjectWorkspaceSourceType.user,
          sourceId: 'user:brief',
          createdAt: now,
          updatedAt: now,
        ),
        _node('report', 'artifact', 'Report', 'Published output.'),
      ],
      edges: [
        ProjectWorkspaceEdge(
          id: 'supports',
          sourceNodeId: 'source',
          targetNodeId: 'report',
          label: 'supports',
          sourceType: ProjectWorkspaceSourceType.user,
          sourceId: 'user:brief',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final project = _project(includeTask: false, workspaceGraph: graph);
    final selection = const ProjectWorkspaceContextService().selectContext(
      project: project,
      maxCharacters: 1000,
    );
    final view = const ProjectViewService().query(
      project,
      workspaceQuery: 'source',
    );

    expect(selection.lines.join('\n'), contains('transcript'));
    expect(selection.lines.join('\n'), contains('user/user:brief'));
    final detail = (view['workspace_detail'] as List).first as Map;
    expect(detail['source_id'], 'user:brief');
    expect((detail['relationships'] as List).single['source_id'], 'user:brief');
  });

  test('planner builder creates graph IDs and commits graph changes', () async {
    final builder = ProjectPlanBuilder(project: _project(includeTask: false));
    builder.setWorkspaceOrientation(
      'The workflow moves from intake to review.',
    );
    final ids = builder.addWorkspaceNodes(const [
      ProjectWorkspaceNodeSpec(
        ref: 'intake',
        type: 'workflow_stage',
        title: 'Intake',
        description: 'Collect the initial request.',
        references: ['process:intake'],
      ),
      ProjectWorkspaceNodeSpec(
        ref: 'review',
        type: 'workflow_stage',
        title: 'Review',
        description: 'Assess the request.',
      ),
    ]);
    final edges = builder.addWorkspaceEdges(const [
      ProjectWorkspaceEdgeSpec(
        ref: 'intake_to_review',
        sourceRef: 'intake',
        targetRef: 'review',
        label: 'flows into',
      ),
    ]);

    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(
      committed.validation.valid,
      isTrue,
      reason: committed.validation.issues
          .map((issue) => issue.toMap())
          .toList()
          .toString(),
    );
    expect(ids, hasLength(2));
    expect(edges, hasLength(1));
    expect(committed.project.workspaceGraph.nodes, hasLength(2));
    expect(committed.project.workspaceGraph.edges.single.sourceNodeId, ids[0]);
  });

  test(
    'pending approval preserves the proposed graph until approval',
    () async {
      final builder = ProjectPlanBuilder(
        project: _project(includeTask: false),
        requiresApproval: true,
        approvalReason: 'Review the durable workspace structure.',
      );
      builder.addWorkspaceNodes(const [
        ProjectWorkspaceNodeSpec(
          ref: 'source',
          type: 'source',
          title: 'Interview transcript',
        ),
      ]);

      final pending = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.everyRevision,
      );
      expect(pending.result.awaitingApproval, isTrue);
      expect(
        pending.project.pendingPlanApproval?.desiredPlan?.workspaceGraph.nodes,
        hasLength(1),
      );
      expect(pending.project.workspaceGraph.nodes, isEmpty);

      final approved = const ProjectPlanRevisionService().approvePending(
        project: pending.project,
        workspaceRoot: '/workspace',
      );
      expect(
        approved.project.workspaceGraph.nodes.single.title,
        'Interview transcript',
      );
    },
  );

  test('planner cannot mutate a user-protected node', () {
    final project = _project(
      workspaceGraph: ProjectWorkspaceGraph(
        nodes: [
          ProjectWorkspaceNode(
            id: 'user_node',
            type: 'requirement',
            title: 'Never publish automatically',
            description: '',
            sourceType: ProjectWorkspaceSourceType.user,
            confidence: ProjectWorkspaceConfidence.confirmed,
            protected: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        updatedAt: now,
      ),
    );
    final builder = ProjectPlanBuilder(project: project);

    expect(
      () => builder.updateWorkspaceNode(
        'user_node',
        title: 'Publish automatically',
      ),
      throwsA(isA<ProjectPlanBuilderException>()),
    );
  });

  test('planner cannot promote inferred graph entries to protected', () {
    final node = _node('inferred', 'concept', 'Inferred concept', 'Durable.');
    final project = _project(
      workspaceGraph: ProjectWorkspaceGraph(nodes: [node]),
    );
    final proposal = ProjectDesiredPlan(
      revision: project.nextRevision,
      summary: 'Keep the plan current.',
      rationale: 'Preserve inferred workspace structure.',
      criteria: project.criteria,
      tasks: project.tasks,
      workspaceGraph: ProjectWorkspaceGraph(
        nodes: [node.copyWith(protected: true)],
      ),
      createdAt: now,
    );

    final validation = const ProjectPlanValidator().validate(
      project: project,
      proposal: proposal,
      workspaceRoot: '/workspace',
    );

    expect(
      validation.errors.map((issue) => issue.code),
      contains('planner_protected_workspace_node'),
    );
  });

  test(
    'workspace commands are idempotent, including orientation and removal',
    () {
      final builder = ProjectPlanBuilder(project: _project(includeTask: false));
      builder.setWorkspaceOrientation(
        'The workflow moves from intake to review.',
        commandId: 'orientation-1',
      );
      builder.setWorkspaceOrientation(
        'The workflow moves from intake to review.',
        commandId: 'orientation-1',
      );
      builder.addWorkspaceNodes(const [
        ProjectWorkspaceNodeSpec(ref: 'one', type: 'concept', title: 'One'),
        ProjectWorkspaceNodeSpec(ref: 'two', type: 'concept', title: 'Two'),
      ]);
      builder.addWorkspaceEdges(const [
        ProjectWorkspaceEdgeSpec(
          ref: 'relation',
          sourceRef: 'one',
          targetRef: 'two',
          label: 'relates to',
        ),
      ]);

      builder.removeWorkspaceNode('one', commandId: 'remove-1');
      builder.removeWorkspaceNode('one', commandId: 'remove-1');

      final preview = builder.preview(workspaceRoot: '/workspace');
      expect(preview.proposal.workspaceGraph.nodes, hasLength(1));
      expect(preview.proposal.workspaceGraph.edges, isEmpty);
      expect(preview.proposal.workspaceGraph.orientation, contains('intake'));
    },
  );

  test(
    'planner graph reference batches are atomic and reject invalid edges',
    () {
      final builder = ProjectPlanBuilder(project: _project(includeTask: false));

      expect(
        () => builder.addWorkspaceNodes(const [
          ProjectWorkspaceNodeSpec(
            ref: 'duplicate',
            type: 'concept',
            title: 'First',
          ),
          ProjectWorkspaceNodeSpec(
            ref: 'duplicate',
            type: 'concept',
            title: 'Second',
          ),
        ]),
        throwsA(isA<ProjectPlanBuilderException>()),
      );
      expect(
        builder
            .preview(workspaceRoot: '/workspace')
            .proposal
            .workspaceGraph
            .nodes,
        isEmpty,
      );
      builder.addWorkspaceNodes(const [
        ProjectWorkspaceNodeSpec(ref: 'one', type: 'concept', title: 'One'),
      ]);
      expect(
        () => builder.addWorkspaceEdges(const [
          ProjectWorkspaceEdgeSpec(
            sourceRef: 'one',
            targetRef: 'missing',
            label: 'points to',
          ),
        ]),
        throwsA(isA<ProjectPlanBuilderException>()),
      );
      expect(
        () => builder.addWorkspaceEdges(const [
          ProjectWorkspaceEdgeSpec(
            sourceRef: 'one',
            targetRef: 'one',
            label: 'self',
          ),
        ]),
        throwsA(isA<ProjectPlanBuilderException>()),
      );
    },
  );

  test('user graph upserts create confirmed protected entries', () {
    const service = ProjectWorkspaceGraphService();
    final project = _project();
    final withNode = service.upsertUserNode(
      project: project,
      type: 'source',
      title: 'Interview transcript',
      references: const ['source:interview-1'],
      timestamp: now,
    );
    final node = withNode.workspaceGraph.nodes.single;
    expect(node.sourceType, ProjectWorkspaceSourceType.user);
    expect(node.confidence, ProjectWorkspaceConfidence.confirmed);
    expect(node.protected, isTrue);

    final withTarget = service.upsertUserNode(
      project: withNode,
      id: 'target',
      type: 'artifact',
      title: 'Final report',
      timestamp: now,
    );
    final withEdge = service.upsertUserEdge(
      project: withTarget,
      sourceNodeId: node.id,
      targetNodeId: 'target',
      label: 'supports',
      timestamp: now,
    );
    expect(withEdge.workspaceGraph.edges.single.protected, isTrue);
    expect(
      () => service.upsertUserNode(
        project: project,
        type: 'concept',
        title: 'x' * 201,
      ),
      throwsArgumentError,
    );
  });
}

ProjectState _project({
  ProjectWorkspaceGraph? workspaceGraph,
  bool includeTask = true,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
    id: 'project_workspace_test',
    title: 'Workspace graph test',
    originalGoal: 'Map the project.',
    refinedGoal: 'Map the project.',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'The project is mapped.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    tasks: includeTask
        ? [
            ProjectTaskNode(
              id: 'task_1',
              title: 'Map report evidence',
              objective: 'Map the report evidence.',
              criterionIds: const ['criterion_1'],
              status: TaskStatus.queued,
              createdAt: now,
              updatedAt: now,
            ),
          ]
        : const [],
    workspaceGraph: workspaceGraph,
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectWorkspaceNode _node(
  String id,
  String type,
  String title,
  String description,
) => ProjectWorkspaceNode(
  id: id,
  type: type,
  title: title,
  description: description,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);
