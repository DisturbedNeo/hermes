import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';

void main() {
  group('ProjectDocument JSON', () {
    test(
      'round-trips status, blockers, questions, decisions, and task refs',
      () {
        final now = DateTime(2026, 1, 1);
        final project = ProjectDocument(
          id: 'project_test',
          title: 'Project',
          originalPrompt: 'Build the app',
          goal: 'Build the app',
          constraints: const ['Stay in workspace'],
          successCriteria: const ['App works'],
          status: ProjectStatus.blocked,
          activeTaskId: 'task_1',
          memorySummary: 'Memory',
          completionSummary: '',
          tasks: [
            ProjectTaskRef(
              taskId: 'task_1',
              title: 'Task 1',
              status: TaskStatus.blocked,
              summary: 'Blocked',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          decisions: [
            ProjectDecisionRecord(
              id: 'decision_1',
              decision: ProjectDecisionType.createTask,
              summary: 'Create task',
              memoryUpdate: 'Need implementation',
              taskId: 'task_1',
              taskTitle: 'Task 1',
              taskPrompt: 'Implement feature',
              createdAt: now,
            ),
          ],
          pendingQuestion: PendingProjectQuestion(
            id: 'question_1',
            question: 'Which platform?',
            createdAt: now,
          ),
          blocker: ProjectBlocker(
            type: ProjectBlockerType.taskApproval,
            message: 'Approval required',
            taskId: 'task_1',
            createdAt: now,
          ),
          chatSessionId: 'chat_1',
          createdAt: now,
          updatedAt: now,
        );

        final loaded = ProjectDocument.fromJson(
          jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
        );

        expect(loaded.schemaVersion, ProjectDocument.currentSchemaVersion);
        expect(loaded.status, ProjectStatus.blocked);
        expect(loaded.blocker?.type, ProjectBlockerType.taskApproval);
        expect(loaded.pendingQuestion?.question, 'Which platform?');
        expect(loaded.tasks.single.taskId, 'task_1');
        expect(
          loaded.decisions.single.decision,
          ProjectDecisionType.createTask,
        );
        expect(loaded.chatSessionId, 'chat_1');
      },
    );

    test('parses snake case blocker and decision aliases', () {
      final loaded = ProjectDocument.fromJson({
        'schema_version': 1,
        'id': 'project_test',
        'title': 'Project',
        'original_prompt': 'Build',
        'goal': 'Build',
        'status': 'blocked',
        'active_task_id': 'task_1',
        'memory_summary': '',
        'completion_summary': '',
        'tasks': const [],
        'decisions': [
          {
            'id': 'decision_1',
            'decision': 'create_task',
            'summary': 'Next',
            'memory_update': '',
            'created_at': DateTime(2026, 1, 1).toIso8601String(),
          },
        ],
        'blocker': {
          'type': 'task_failed',
          'message': 'Task failed',
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
        },
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      });

      expect(loaded.activeTaskId, 'task_1');
      expect(loaded.blocker?.type, ProjectBlockerType.taskFailed);
      expect(loaded.decisions.single.decision, ProjectDecisionType.createTask);
    });
  });
}
