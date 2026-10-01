import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/app/modules/persistence_module.dart';
import 'package:hermes/features/persistence/infrastructure/dto/project_persistence_adapter.dart';
import 'package:hermes/features/persistence/infrastructure/dto/task_persistence_adapter.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';

void main() {
  test('all persistence repositories share the module coordinator', () {
    final module = PersistenceModule.create();

    expect(
      identical(module.tasks.coordinator, module.projects.coordinator),
      isTrue,
    );
    expect(
      identical(
        module.projects.coordinator,
        module.projectAggregates.coordinator,
      ),
      isTrue,
    );
  });

  test(
    'project and task persistence DTO adapters round-trip domain values',
    () {
      final now = DateTime(2026, 1, 1);
      final task = Task(
        id: 'task_dto',
        title: 'DTO task',
        originalPrompt: 'Preserve this task',
        objective: 'Round-trip the task',
        constraints: const [],
        successCriteria: const ['It survives'],
        createdAt: now,
        updatedAt: now,
      );
      final project = ProjectAggregate(
        id: 'project_dto',
        title: 'DTO project',
        originalGoal: 'Preserve this project',
        refinedGoal: 'Round-trip the project',
        criteria: const [],
        constraints: const [],
        tasks: const [],
        status: ProjectStatus.active,
        activeTaskId: null,
        createdAt: now,
        updatedAt: now,
      );

      final taskAdapter = const TaskPersistenceAdapter();
      final projectAdapter = const ProjectPersistenceAdapter();
      final taskDto = taskAdapter.toDto(task);
      final projectDto = projectAdapter.toDto(project);

      expect(taskAdapter.fromDto(taskDto).id, task.id);
      expect(projectAdapter.fromDto(projectDto).id, project.id);
      expect(taskDto.document, isNotEmpty);
      expect(projectDto.document, isNotEmpty);
    },
  );
}
