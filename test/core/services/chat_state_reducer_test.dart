import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/application/chat_panel_projection.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';

void main() {
  test('reducer updates task and project panel slices as projections', () {
    final now = DateTime(2026, 1, 1);
    final task = Task(
      id: 'task_slice',
      title: 'Slice task',
      originalPrompt: 'Show the task panel',
      objective: 'Render one task',
      constraints: const [],
      successCriteria: const [],
      createdAt: now,
      updatedAt: now,
    );
    final project = ProjectAggregate(
      id: 'project_slice',
      title: 'Slice project',
      originalGoal: 'Show the project panel',
      refinedGoal: 'Render one project',
      criteria: const [],
      constraints: const [],
      tasks: const [],
      status: ProjectStatus.active,
      activeTaskId: null,
      createdAt: now,
      updatedAt: now,
    );
    final state = ChatState.initial(
      'tab_slice',
      Bubble(
        id: 'system',
        role: MessageRole.system,
        text: 'system',
        reasoning: '',
        createdAt: now,
      ),
    );
    const reducer = ChatStateReducer();

    final next = reducer.reduce(
      reducer.reduce(
        state,
        ChatProjectChanged(ChatPanelProjection.project(project)),
      ),
      ChatTaskChanged(ChatPanelProjection.task(task)),
    );

    expect(next.activeProject?.id, 'project_slice');
    expect(next.activeTask?.id, 'task_slice');
    expect(next.activeProject, isA<ProjectPanelReadModel>());
    expect(next.activeTask, isA<TaskPanelReadModel>());
    expect(next.conversation.messages, same(next.messages));
    expect(next.projectPanel.activeProject, same(next.activeProject));
    expect(next.taskPanel.activeTask, same(next.activeTask));
    expect(next.modelSession, isNotNull);
    expect(next.persistence, isNotNull);
    expect(next.operationStatus, isNotNull);
  });
}
