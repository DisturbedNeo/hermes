import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/chat_panel_projection.dart';
import 'package:hermes/features/chat/runtime/chat_presentation_message_builder.dart';
import 'package:hermes/features/project/domain/project.dart';

void main() {
  test('presents the saved planning failure instead of an active status', () {
    final project = _project();
    final message = const ChatPresentationMessageBuilder().projectStatus(
      project,
    );
    final panel = ChatPanelProjection.project(project);

    expect(message, contains('Planning interrupted'));
    expect(message, contains('The planner could not prepare its prompt.'));
    expect(message, contains('Continue the project to retry planning.'));
    expect(message, isNot(contains('Status: `active`')));
    expect(panel.boundary?.message, project.boundary?.message);
    expect(panel.statusLabel, 'Planning interrupted');
  });

  test('clears the failure presentation after a successful retry', () {
    final project = _project().copyWith(boundary: null);
    final message = const ChatPresentationMessageBuilder().projectStatus(
      project,
    );
    final panel = ChatPanelProjection.project(project);

    expect(message, contains('Status: `active`'));
    expect(message, isNot(contains('Planning interrupted')));
    expect(panel.planningInterrupted, isFalse);
    expect(panel.statusLabel, 'active');
  });
}

ProjectAggregate _project() {
  final now = DateTime(2026, 11, 4);
  return ProjectAggregate(
    id: 'project_planning_failed',
    title: 'Saved project',
    originalGoal: 'Deliver the project.',
    refinedGoal: 'Deliver the project.',
    criteria: const [],
    constraints: const [],
    tasks: const [],
    milestones: const [],
    planHistory: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    boundary: ProjectBoundary(
      outcome: ProjectControlOutcome.degradedPlanning,
      message: 'The planner could not prepare its prompt.',
      action: 'retry_planning',
      reasonCode: 'planning_failed',
      occurredAt: now,
    ),
    createdAt: now,
    updatedAt: now,
  );
}
