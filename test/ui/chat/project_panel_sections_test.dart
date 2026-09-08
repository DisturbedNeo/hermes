import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/ui/chat/project_panel_sections.dart';

void main() {
  testWidgets('does not render the active task in other planned work', (
    tester,
  ) async {
    final now = DateTime(2026, 1, 1);
    final active = _task(
      id: 'active',
      title: 'Active bounded task',
      status: ProjectTaskStatus.running,
      taskDocumentId: 'document_active',
    );
    final project = ProjectState(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Deliver the outcome.',
      refinedGoal: 'Deliver the bounded outcome.',
      criteria: [
        ProjectCriterion(
          id: 'criterion_1',
          statement: 'The outcome is verified.',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      constraints: const [],
      tasks: [active],
      status: ProjectStatus.runningTask,
      activeTaskId: active.id,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectRoadmapSection(project: project)),
      ),
    );

    expect(find.text('Active Task'), findsOneWidget);
    expect(find.text('Active bounded task'), findsOneWidget);
    expect(find.text('Other Planned Work'), findsNothing);
  });

  testWidgets('does not render terminal history as planned work', (
    tester,
  ) async {
    final completed = _task(
      id: 'completed',
      title: 'Completed bounded task',
      status: ProjectTaskStatus.completed,
      taskDocumentId: 'document_completed',
    );
    final now = DateTime(2026, 1, 1);
    final project = ProjectState(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Deliver the outcome.',
      refinedGoal: 'Deliver the bounded outcome.',
      criteria: [
        ProjectCriterion(
          id: 'criterion_1',
          statement: 'The outcome is verified.',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      constraints: const [],
      tasks: [completed],
      status: ProjectStatus.active,
      activeTaskId: null,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectRoadmapSection(project: project)),
      ),
    );

    expect(find.text('Other Planned Work'), findsNothing);
    expect(find.text('Completed bounded task'), findsNothing);
  });
}

ProjectTask _task({
  required String id,
  required String title,
  required ProjectTaskStatus status,
  required String taskDocumentId,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectTask(
    id: id,
    title: title,
    objective: 'Complete the bounded task.',
    criterionIds: const ['criterion_1'],
    doneCriteria: const ['The bounded task is complete.'],
    outOfScope: const ['Unrelated work.'],
    context: const [],
    expectedArtifacts: const [],
    status: status,
    taskDocumentId: taskDocumentId,
    fingerprint: id,
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
