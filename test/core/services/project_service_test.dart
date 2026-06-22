import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';

void main() {
  group('ProjectService supervised runner', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late ProjectService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_project_service_');
      workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final taskService = TaskService(toolService: ToolService());
      service = ProjectService(taskService: taskService);
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('creates a project, runs a task, and evaluates completion', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the reporting screen',
        chatSessionId: 'chat_1',
      );
      final client = _QueueChatClient([
        jsonEncode(_projectDecisionCreateTask()),
        jsonEncode(_taskPlanJson()),
        jsonEncode({
          'status': 'completed',
          'summary': 'Task complete.',
          'memoryUpdate': 'Implemented the screen.',
        }),
        jsonEncode({
          'decision': 'complete',
          'projectSummary': 'Project complete.',
          'memoryUpdate': 'All work is done.',
          'completionSummary': 'Reporting screen is complete.',
        }),
      ]);

      final result = await service.runProject(
        client: client,
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 5,
      );

      expect(result.project.status, ProjectStatus.completed);
      expect(result.project.tasks, hasLength(1));
      expect(result.project.tasks.single.status, TaskStatus.completed);
      expect(result.project.completionSummary, contains('complete'));
      expect(result.activeTask, isNull);
    });

    test('pauses with budget blocker after max new tasks', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final client = _QueueChatClient([
        jsonEncode(_projectDecisionCreateTask()),
        jsonEncode(_taskPlanJson()),
        jsonEncode({
          'status': 'completed',
          'summary': 'First task complete.',
          'memoryUpdate': 'One slice is done.',
        }),
      ]);

      final result = await service.runProject(
        client: client,
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.blocked);
      expect(result.project.blocker?.type, ProjectBlockerType.budget);
      expect(result.project.activeTaskId, isNull);
    });

    test(
      'records project-level user questions and resumes after answer',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
        );
        final blocked = await service.runProject(
          client: _QueueChatClient([
            jsonEncode({
              'decision': 'blocked',
              'projectSummary': 'Need target platform.',
              'memoryUpdate': '',
              'userQuestion': 'Which platform should this target?',
            }),
          ]),
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 5,
        );

        expect(blocked.project.status, ProjectStatus.blocked);
        expect(blocked.project.pendingQuestion?.question, contains('platform'));

        final answered = await service.answerOpenQuestion(
          workspace: workspace,
          snapshot: blocked.project,
          answer: 'Desktop first.',
        );

        expect(answered.status, ProjectStatus.paused);
        expect(answered.pendingQuestion, isNull);
        expect(answered.blocker, isNull);
        expect(answered.memorySummary, contains('Desktop first.'));
      },
    );

    test('blocks repeated next task proposals', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final previous = project.copyWith(
        decisions: [
          ProjectDecisionRecord(
            id: 'decision_previous',
            decision: ProjectDecisionType.createTask,
            summary: 'Create task',
            memoryUpdate: '',
            taskPrompt: 'Implement the first slice',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode(
            _projectDecisionCreateTask(prompt: 'Implement the first slice'),
          ),
        ]),
        workspace: workspace,
        snapshot: previous,
        baseSystemPrompt: 'system',
        maxNewTasks: 5,
      );

      expect(result.project.status, ProjectStatus.blocked);
      expect(result.project.blocker?.type, ProjectBlockerType.error);
      expect(result.project.blocker?.message, contains('repeated'));
    });
  });
}

Map<String, dynamic> _projectDecisionCreateTask({
  String prompt = 'Implement the first slice',
}) {
  return {
    'decision': 'create_task',
    'projectSummary': 'More work is needed.',
    'memoryUpdate': 'Start with implementation.',
    'nextTask': {
      'title': 'Implement slice',
      'prompt': prompt,
      'successCriteria': ['Slice is implemented.'],
    },
  };
}

Map<String, dynamic> _taskPlanJson() {
  return {
    'title': 'Implement slice',
    'goal': 'Implement the first slice',
    'constraints': ['Stay inside workspace.'],
    'successCriteria': ['Slice is implemented.'],
    'steps': [
      {
        'id': 'build',
        'title': 'Build slice',
        'objective': 'Build the first slice.',
        'instructions': ['Do the work.'],
        'mayEditFiles': false,
      },
    ],
  };
}

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> _responses;
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    final index = _index >= _responses.length ? _responses.length - 1 : _index;
    _index++;
    return ChatCompletionResponse(content: _responses[index]);
  }

  @override
  void dispose() {}
}
