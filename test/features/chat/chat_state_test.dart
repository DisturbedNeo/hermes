import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/application/chat_panel_projection.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';

void main() {
  final systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: 'system',
    reasoning: '',
    createdAt: DateTime(2026),
  );

  test('state snapshots defensively copy user-visible collections', () {
    final input = <Bubble>[systemPrompt];
    final state = ChatState.initial('tab-1', systemPrompt);
    final copied = state.copyWith(messages: input);

    input.clear();
    expect(copied.messages, hasLength(1));
    expect(() => copied.messages.add(systemPrompt), throwsUnsupportedError);
  });

  test('reducer prevents cancellation and busy/error contradictions', () {
    const reducer = ChatStateReducer();
    final idle = ChatState.initial('tab-1', systemPrompt);
    final cancelledWhileIdle = reducer.requestTaskCancellation(idle);
    expect(cancelledWhileIdle.taskCancellationRequested, isFalse);

    final running = reducer.dispatchTaskBusy(idle, true);
    final cancelled = reducer.requestTaskCancellation(running);
    expect(cancelled.taskBusy, isTrue);
    expect(cancelled.taskCancellationRequested, isTrue);

    final failed = reducer.dispatchTaskError(cancelled, StateError('failed'));
    expect(failed.taskBusy, isFalse);
    expect(failed.taskCancellationRequested, isFalse);
    expect(failed.taskError, isA<StateError>());
  });

  test('panel projections detach aggregate collections', () {
    final taskSteps = <TaskStep>[];
    final taskConstraints = <String>['keep this'];
    final task = Task(
      id: 'task-1',
      title: 'Task',
      objective: 'Do the task',
      steps: taskSteps,
      constraints: taskConstraints,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final taskPanel = ChatPanelProjection.task(task);

    taskSteps.add(
      const TaskStep(
        id: 'step-1',
        title: 'Step',
        objective: 'Do one step',
        instructions: [],
        mayEditFiles: false,
        artifacts: [],
        status: TaskStepStatus.pending,
      ),
    );
    taskConstraints.add('mutated later');

    expect(taskPanel.steps, isEmpty);
    expect(taskPanel.doneCriteria, isEmpty);
    expect(() => taskPanel.steps.clear(), throwsUnsupportedError);

    final criteria = <ProjectCriterion>[
      ProjectCriterion(
        id: 'criterion-1',
        statement: 'The criterion',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
    final project = ProjectAggregate(
      id: 'project-1',
      title: 'Project',
      originalGoal: 'Deliver it',
      refinedGoal: 'Deliver it',
      criteria: criteria,
      constraints: const [],
      activeTaskId: null,
      status: ProjectStatus.active,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final projectPanel = ChatPanelProjection.project(project);

    criteria.clear();

    expect(projectPanel.criteria, hasLength(1));
    expect(() => projectPanel.criteria.clear(), throwsUnsupportedError);
  });
}
