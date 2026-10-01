import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/runtime/project_decision_engine.dart';

void main() {
  final engine = const ProjectDecisionEngine();

  test('selects user input before execution', () {
    final now = DateTime(2026, 1, 1);
    final question = PendingProjectQuestion(
      id: 'question_1',
      question: 'Which account should be used?',
      createdAt: now,
    );
    final decision = engine.decide(
      ProjectDecisionInput(
        project: _project(
          status: ProjectStatus.waitingForUser,
          openQuestions: [question],
        ),
        candidate: _task(),
      ),
    );

    expect(decision.action, ProjectExecutionAction.awaitUserInput);
  });

  test('selects plan revision for explicit triggers', () {
    final decision = engine.decide(
      ProjectDecisionInput(
        project: _project(),
        replanTriggers: const [ProjectPlanRevisionTrigger.taskFailed],
      ),
    );

    expect(decision.action, ProjectExecutionAction.revisePlan);
  });

  test('selects bounded execution for a ready candidate', () {
    final task = _task();
    final decision = engine.decide(
      ProjectDecisionInput(project: _project(), candidate: task),
    );

    expect(decision.action, ProjectExecutionAction.executeTask);
    expect(decision.task, same(task));
  });

  test('selects pause when the command budget is exhausted', () {
    final decision = engine.decide(
      ProjectDecisionInput(
        project: _project(),
        runIterations: 1,
        allowedIterations: 1,
      ),
    );

    expect(decision.action, ProjectExecutionAction.pause);
  });
}

ProjectAggregate _project({
  ProjectStatus status = ProjectStatus.active,
  List<PendingProjectQuestion> openQuestions = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Build it',
    refinedGoal: 'Build it safely',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'It works',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    tasks: [_task()],
    status: status,
    activeTaskId: null,
    openQuestions: openQuestions,
    blocker: openQuestions.isEmpty
        ? null
        : ProjectBlocker(
            type: ProjectBlockerType.question,
            message: openQuestions.first.question,
            createdAt: now,
          ),
    createdAt: now,
    updatedAt: now,
  );
}

ProjectTaskNode _task() {
  final now = DateTime(2026, 1, 1);
  return ProjectTaskNode(
    id: 'task_1',
    title: 'Task',
    objective: 'Do the task',
    criterionIds: const ['criterion_1'],
    status: TaskStatus.queued,
    createdAt: now,
    updatedAt: now,
  );
}
