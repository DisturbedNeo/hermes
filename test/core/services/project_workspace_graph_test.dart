import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/project/runtime/project_plan_builder.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_plan_validator.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/project/runtime/project_workspace_graph_service.dart';
import 'package:hermes/features/project/runtime/project_workspace_graph_reconciler.dart';
import 'package:hermes/features/project/runtime/project_view_service.dart';
import 'package:hermes/features/workspace/application/workspace_change_discovery.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';

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

    final decoded = ModelJson.decode<ProjectAggregate>(
      ModelJson.encode(project),
    );

    expect(decoded.workspaceGraph.orientation, contains('archive'));
    expect(decoded.workspaceGraph.nodes.first.title, 'The archive');
    expect(decoded.workspaceGraph.nodes.first.protected, isTrue);
    expect(decoded.workspaceGraph.edges.single.label, 'reveals evidence for');
  });

  test('round trips managed keys and the discovery fingerprint', () {
    final project = _project(
      includeTask: false,
      workspaceGraph: ProjectWorkspaceGraph(
        discoveryFingerprint: 'fingerprint-1',
        nodes: [
          _node(
            'workspace',
            'workspace',
            'Workspace',
            'Discovered workspace',
          ).copyWith(managedKey: 'system:workspace'),
        ],
        edges: [
          ProjectWorkspaceEdge(
            id: 'managed-edge',
            sourceNodeId: 'workspace',
            targetNodeId: 'workspace-2',
            label: 'contains',
            managedKey: 'system:edge:workspace:package:demo',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );

    final decoded = ModelJson.decode<ProjectAggregate>(
      ModelJson.encode(project),
    );

    expect(decoded.workspaceGraph.discoveryFingerprint, 'fingerprint-1');
    expect(decoded.workspaceGraph.nodes.single.managedKey, 'system:workspace');
    expect(
      decoded.workspaceGraph.edges.single.managedKey,
      'system:edge:workspace:package:demo',
    );
  });

  test(
    'reconciles bounded structural facts idempotently and removes stale facts',
    () {
      final timestamp = DateTime(2026, 1, 2);
      const profile = WorkspaceDiscoveryProfile(
        workspaceName: 'Hermes',
        packageName: 'hermes',
        treePaths: ['pubspec.yaml', 'lib/', 'lib/main.dart'],
        dependencies: ['flutter'],
        languages: ['Dart'],
        frameworks: ['Flutter'],
        highSignalFiles: [
          WorkspaceFileExcerpt(path: 'pubspec.yaml', content: 'name: hermes'),
        ],
      );
      final project = _project(includeTask: false);
      const changes = WorkspaceChangeSet(
        isRepository: true,
        changedFiles: ['lib/main.dart'],
      );
      const reconciler = ProjectWorkspaceGraphReconciler();

      final first = reconciler.reconcile(
        project: project,
        workspaceProfile: profile,
        changeSet: changes,
        timestamp: timestamp,
      );
      final managedKeys = first.graph.nodes
          .map((node) => node.managedKey)
          .whereType<String>()
          .toSet();
      expect(
        managedKeys,
        containsAll([
          'system:workspace',
          'system:package:hermes',
          'system:file:lib/main.dart',
          'system:dependency:flutter',
        ]),
      );
      expect(
        first.graph.edges.map((edge) => edge.label),
        containsAll(['contains', 'uses', 'depends_on', 'declares']),
      );
      expect(first.plannerMaintenanceRecommended, isTrue);

      final second = reconciler.reconcile(
        project: project.copyWith(workspaceGraph: first.graph),
        workspaceProfile: profile,
        changeSet: changes,
        timestamp: timestamp.add(const Duration(days: 1)),
      );
      expect(second.addedManagedKeys, isEmpty);
      expect(second.updatedManagedKeys, isEmpty);
      expect(second.removedManagedKeys, isEmpty);
      expect(
        second.graph.nodes
            .singleWhere((node) => node.managedKey == 'system:workspace')
            .createdAt,
        timestamp,
      );
      expect(
        second.graph.nodes
            .singleWhere((node) => node.managedKey == 'system:workspace')
            .updatedAt,
        timestamp,
      );

      final stale = reconciler.reconcile(
        project: project.copyWith(workspaceGraph: first.graph),
        workspaceProfile: const WorkspaceDiscoveryProfile(
          workspaceName: 'Hermes',
          treePaths: ['pubspec.yaml'],
        ),
        changeSet: changes,
        timestamp: timestamp,
      );
      expect(stale.removedManagedKeys, contains('system:file:lib/main.dart'));
      expect(
        stale.graph.nodes.any(
          (node) => node.managedKey == 'system:file:lib/main.dart',
        ),
        isFalse,
      );
    },
  );

  test(
    'reconciliation preserves authored entries while planner cannot mutate managed entries',
    () {
      final authored = ProjectWorkspaceNode(
        id: 'authored',
        type: 'requirement',
        title: 'Keep this',
        description: '',
        sourceType: ProjectWorkspaceSourceType.planner,
        createdAt: now,
        updatedAt: now,
      );
      final project = _project(
        includeTask: false,
        workspaceGraph: ProjectWorkspaceGraph(nodes: [authored]),
      );
      final reconciled = const ProjectWorkspaceGraphReconciler().reconcile(
        project: project,
        workspaceProfile: const WorkspaceDiscoveryProfile(
          workspaceName: 'Workspace',
        ),
        changeSet: const WorkspaceChangeSet(isRepository: false),
        timestamp: now,
      );
      expect(
        reconciled.graph.nodes.map((node) => node.id),
        contains('authored'),
      );

      final managed = reconciled.graph.nodes.singleWhere(
        (node) => node.managedKey == 'system:workspace',
      );
      final builder = ProjectPlanBuilder(
        project: reconciled.graph == project.workspaceGraph
            ? project
            : project.copyWith(workspaceGraph: reconciled.graph),
      );
      expect(
        () => builder.updateWorkspaceNode(managed.id, title: 'Changed'),
        throwsA(isA<ProjectPlanBuilderException>()),
      );
      expect(
        () => builder.removeWorkspaceNode(managed.id),
        throwsA(isA<ProjectPlanBuilderException>()),
      );
    },
  );

  test(
    'graph-only planner commits preserve managed facts and create history',
    () async {
      final project = _project(
        includeTask: false,
        workspaceGraph: ProjectWorkspaceGraph(
          discoveryFingerprint: 'fingerprint-1',
          nodes: [
            _node(
              'managed',
              'workspace',
              'Workspace',
              'Derived',
            ).copyWith(managedKey: 'system:workspace'),
          ],
        ),
      );
      final builder = ProjectPlanBuilder(
        project: project,
        triggers: const [ProjectPlanRevisionTrigger.workspaceGraphMaintenance],
        planningLimits: ProjectPlanningLimits.graphMaintenance,
      );
      builder.addWorkspaceNodes(const [
        ProjectWorkspaceNodeSpec(
          ref: 'concept',
          type: 'concept',
          title: 'Durable concept',
          references: ['workspace:README.md'],
        ),
      ]);

      final committed = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(
        committed.result.changed,
        isTrue,
        reason: committed.validation.issues
            .map((issue) => issue.toMap())
            .toList()
            .toString(),
      );
      expect(committed.project.tasks, hasLength(project.tasks.length));
      expect(
        committed.project.planHistory,
        hasLength(project.planHistory.length + 1),
      );
      expect(
        committed.project.workspaceGraph.nodes
            .singleWhere((node) => node.managedKey == 'system:workspace')
            .title,
        'Workspace',
      );
      final preservedManaged = committed.project.workspaceGraph.nodes
          .singleWhere((node) => node.managedKey == 'system:workspace');
      expect(preservedManaged.createdAt, now);
      expect(preservedManaged.updatedAt, now);
      expect(
        committed.project.workspaceGraph.nodes
            .singleWhere((node) => node.title == 'Durable concept')
            .sourceType,
        ProjectWorkspaceSourceType.planner,
      );
    },
  );

  test(
    'graph-only commits preserve lifecycle state and non-graph triggers',
    () async {
      final graphTrigger = ProjectPlanRevisionTrigger.workspaceGraphMaintenance;
      final project = _project(includeTask: false).copyWith(
        status: ProjectStatus.blocked,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.taskFailed,
          message: 'Keep this blocker.',
          createdAt: now,
        ),
        pendingReplanTriggers: [
          graphTrigger,
          ProjectPlanRevisionTrigger.taskFailed,
        ],
      );
      final builder = ProjectPlanBuilder(
        project: project,
        triggers: [graphTrigger],
        planningLimits: ProjectPlanningLimits.graphMaintenance,
      );
      builder.addWorkspaceNodes(const [
        ProjectWorkspaceNodeSpec(
          ref: 'concept',
          type: 'concept',
          title: 'Durable concept',
        ),
      ]);

      final committed = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(committed.project.status, ProjectStatus.blocked);
      expect(committed.project.blocker?.message, 'Keep this blocker.');
      expect(
        committed.project.pendingReplanTriggers,
        contains(ProjectPlanRevisionTrigger.taskFailed),
      );
      expect(
        committed.project.pendingReplanTriggers,
        isNot(contains(graphTrigger)),
      );
    },
  );

  test(
    'invalid revisions retain a pending graph-maintenance retry trigger',
    () async {
      final graphTrigger = ProjectPlanRevisionTrigger.workspaceGraphMaintenance;
      final project = _project(
        includeTask: false,
      ).copyWith(pendingReplanTriggers: [graphTrigger]);
      final result = await const ProjectPlanRevisionService().prepareAndApply(
        project: project,
        proposal: ProjectDesiredPlan(
          revision: 999,
          summary: 'Invalid revision',
          rationale: 'Exercise retry preservation.',
          createdAt: now,
        ),
        workspaceRoot: '/workspace',
      );

      expect(result.validation.valid, isFalse);
      expect(result.project.pendingReplanTriggers, contains(graphTrigger));
    },
  );

  test('projects declared and durable task outputs into produces edges', () {
    final task = _project().tasks.single.copyWith(
      writePaths: const ['dist/report.md'],
      expectedArtifacts: const [
        TaskArtifact(path: 'dist/report.md', description: 'Report output'),
      ],
    );
    final project = _project().copyWith(tasks: [task]);
    final result = const ProjectWorkspaceGraphReconciler().reconcile(
      project: project,
      workspaceProfile: const WorkspaceDiscoveryProfile(
        workspaceName: 'Workspace',
      ),
      changeSet: const WorkspaceChangeSet(isRepository: false),
      timestamp: now,
    );

    expect(
      result.graph.nodes.map((node) => node.managedKey),
      contains('task:artifact:task_1:dist/report.md'),
    );
    expect(
      result.graph.edges.where((edge) => edge.label == 'produces'),
      hasLength(1),
    );
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

ProjectAggregate _project({
  ProjectWorkspaceGraph? workspaceGraph,
  bool includeTask = true,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
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
