import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/chat/application/chat_panel_projection.dart';
import 'package:hermes/features/chat/presentation/chat/project_panel_sections.dart';

void main() {
  testWidgets('renders workspace orientation, nodes, and relationships', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 1);
    final project = _project(
      ProjectWorkspaceGraph(
        orientation: 'The source drives the final report.',
        nodes: [
          ProjectWorkspaceNode(
            id: 'source',
            type: 'source',
            title: 'Interview transcript',
            description: 'Primary evidence.',
            createdAt: now,
            updatedAt: now,
          ),
          ProjectWorkspaceNode(
            id: 'report',
            type: 'artifact',
            title: 'Final report',
            description: 'Published output.',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        edges: [
          ProjectWorkspaceEdge(
            id: 'supports',
            sourceNodeId: 'source',
            targetNodeId: 'report',
            label: 'supports',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: ProjectWorkspaceContextSection(
            project: ChatPanelProjection.project(project),
          ),
        ),
      ),
    );

    expect(find.text('Workspace Context'), findsOneWidget);
    expect(find.text('The source drives the final report.'), findsOneWidget);
    expect(find.text('Graph: 2 nodes · 1 relationships'), findsOneWidget);
    expect(find.text('Interview transcript'), findsOneWidget);
    expect(
      find.textContaining('Interview transcript supports Final report'),
      findsOneWidget,
    );
  });

  testWidgets('renders an empty graph without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectWorkspaceContextSection(
          project: ChatPanelProjection.project(_project()),
        ),
      ),
    );

    expect(
      find.text('No durable workspace nodes have been recorded yet.'),
      findsOneWidget,
    );
  });

  testWidgets('renders a clear truncated state for large graphs', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 1);
    final graph = ProjectWorkspaceGraph(
      nodes: [
        for (var index = 0; index < 25; index++)
          ProjectWorkspaceNode(
            id: 'node_$index',
            type: 'concept',
            title: 'Concept $index',
            description: 'Durable concept.',
            createdAt: now,
            updatedAt: now,
          ),
      ],
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: ProjectWorkspaceContextSection(
            project: ChatPanelProjection.project(_project(graph)),
          ),
        ),
      ),
    );

    expect(find.text('Showing 24 of 25 workspace nodes.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Workspace node Concept 0')),
      findsOneWidget,
    );
  });
}

ProjectAggregate _project([ProjectWorkspaceGraph? graph]) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'workspace_ui_test',
    title: 'Workspace UI test',
    originalGoal: 'Show workspace context.',
    refinedGoal: 'Show workspace context.',
    criteria: const [],
    constraints: const [],
    workspaceGraph: graph,
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}
