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
  group('ProjectService orchestrator runner', () {
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

    test(
      'runs one bounded project task and completes after evaluation',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the reporting screen',
          chatSessionId: 'chat_1',
        );
        final client = _QueueChatClient([
          jsonEncode({'task': _projectTaskJson()}),
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Task complete.',
            'memoryUpdate': 'Implemented the first reporting screen slice.',
          }),
          jsonEncode({
            'complete': true,
            'finalSummary': 'Reporting screen project is complete.',
            'remainingCriteria': [],
            'openQuestions': [],
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
        expect(result.project.completedTasks, hasLength(1));
        expect(result.project.failedTasks, isEmpty);
        expect(result.project.completionSummary, contains('complete'));
        expect(result.activeTask?.status, TaskStatus.completed);
      },
    );

    test('pauses after the per-run project task limit', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final client = _QueueChatClient([
        jsonEncode({'task': _projectTaskJson()}),
        jsonEncode(_taskPlanJson()),
        jsonEncode({
          'status': 'completed',
          'summary': 'First task complete.',
          'memoryUpdate': 'One slice is done.',
        }),
        jsonEncode({
          'complete': false,
          'finalSummary': '',
          'remainingCriteria': ['Complete the stated project goal.'],
          'openQuestions': [],
        }),
      ]);

      final result = await service.runProject(
        client: client,
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.blocker, isNull);
      expect(result.project.completedTasks, hasLength(1));
    });

    test(
      'records project-level user questions and resumes after answer',
      () async {
        final project = await service.createProject(
          client: _QueueChatClient([
            jsonEncode({
              'title': 'Build app',
              'refinedGoal': 'Build the app',
              'successCriteria': ['App works'],
              'constraints': ['Stay in workspace'],
              'knownFacts': [],
              'openQuestions': [
                {'question': 'Which platform should this target?'},
              ],
              'backlog': [],
            }),
          ]),
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
          baseSystemPrompt: 'system',
        );

        expect(project.status, ProjectStatus.waitingForUser);
        expect(project.pendingQuestion?.question, contains('platform'));

        final answered = await service.answerOpenQuestion(
          workspace: workspace,
          snapshot: project,
          answer: 'Desktop first.',
        );

        expect(answered.status, ProjectStatus.active);
        expect(answered.pendingQuestion, isNull);
        expect(answered.blocker, isNull);
        expect(answered.knownFacts.join('\n'), contains('Desktop first.'));
      },
    );

    test(
      'initialization can inspect files before finalising project',
      () async {
        await File(
          '${root.path}/design.md',
        ).writeAsString('# Design\nBuild a reporting dashboard.\n');
        final project = await service.createProject(
          client: _QueueCompletionClient([
            ChatCompletionResponse(
              content: '',
              toolCalls: [
                ChatCompletionToolCall(
                  name: 'read_file',
                  arguments: jsonEncode({'path': 'design.md'}),
                ),
              ],
            ),
            ChatCompletionResponse(
              content: '',
              toolCalls: [
                ChatCompletionToolCall(
                  name: 'finaliseProjectCreation',
                  arguments: jsonEncode({
                    'title': 'Reporting dashboard',
                    'refinedGoal': 'Build a reporting dashboard',
                    'successCriteria': ['Dashboard matches the design'],
                    'constraints': ['Stay in workspace'],
                    'knownFacts': ['Design requests a reporting dashboard.'],
                    'openQuestions': [],
                    'backlog': [_projectTaskJson()],
                  }),
                ),
              ],
            ),
          ]),
          workspace: workspace,
          userPrompt: 'Build from the design doc',
          chatSessionId: 'chat_1',
          baseSystemPrompt: 'system',
        );

        expect(project.title, 'Reporting dashboard');
        expect(
          project.knownFacts,
          contains('Design requests a reporting dashboard.'),
        );
      },
    );

    test('stops when backlog refresh raises an open question', () async {
      final created = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final project = created.copyWith(
        backlog: const [],
        successCriteria: const ['Finish'],
      );

      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'backlog': [],
            'knownFacts': ['The API choice is unknown.'],
            'openQuestions': [
              {'question': 'Which API should the app use?'},
            ],
          }),
        ]),
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 5,
      );

      expect(result.project.status, ProjectStatus.waitingForUser);
      expect(result.project.pendingQuestion?.question, contains('API'));
      expect(result.project.knownFacts, contains('The API choice is unknown.'));
      expect(result.activeTask, isNull);
      expect(result.project.completedTasks, isEmpty);
    });

    test(
      'backlog refresh can inspect files before finalising project',
      () async {
        await File(
          '${root.path}/design.md',
        ).writeAsString('# Design\nUse the analytics endpoint.\n');
        final created = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
        );
        final project = created.copyWith(
          backlog: const [],
          successCriteria: const ['Finish'],
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'read_file',
                arguments: jsonEncode({'path': 'design.md'}),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'finaliseProjectCreation',
                arguments: jsonEncode({
                  'backlog': [_projectTaskJson()],
                  'knownFacts': ['Design mentions the analytics endpoint.'],
                  'openQuestions': [
                    {'question': 'Which analytics endpoint should be used?'},
                  ],
                }),
              ),
            ],
          ),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 5,
        );

        expect(result.project.status, ProjectStatus.waitingForUser);
        expect(
          result.project.knownFacts,
          contains('Design mentions the analytics endpoint.'),
        );
        expect(client.seenToolNames.first, contains('read_file'));
        expect(client.seenToolNames.first, contains('finaliseProjectCreation'));
        expect(client.seenToolNames.first, isNot(contains('write_file')));
        expect(client.seenToolNames.first, isNot(contains('run_command')));
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
          jsonEncode({
            'task': _projectTaskJson(objective: 'Implement the first slice'),
          }),
        ]),
        workspace: workspace,
        snapshot: previous,
        baseSystemPrompt: 'system',
        maxNewTasks: 5,
      );

      expect(result.project.status, ProjectStatus.blocked);
      expect(result.project.blocker?.type, ProjectBlockerType.duplicateTask);
      expect(result.project.blocker?.message, contains('repeated'));
    });

    test('does not execute one giant task for a broad project goal', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the entire product',
        chatSessionId: 'chat_1',
      );

      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'task': _projectTaskJson(
              objective: 'Complete the entire project end-to-end',
              relevantSuccessCriteria: ['Complete the stated project goal.'],
            ),
          }),
          jsonEncode({'tasks': []}),
        ]),
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 5,
      );

      expect(
        result.project.failedTasks.any(
          (task) => task.objective.contains('entire project'),
        ),
        isTrue,
      );
      expect(
        result.project.completedTasks.any(
          (task) => task.objective.contains('entire project'),
        ),
        isFalse,
      );
      expect(
        result.project.currentTask?.objective.contains('entire project') ??
            false,
        isFalse,
      );
    });
  });
}

Map<String, dynamic> _projectTaskJson({
  String objective = 'Implement the first reporting screen slice',
  List<String> relevantSuccessCriteria = const [
    'Complete the stated project goal.',
  ],
}) {
  return {
    'title': 'Implement slice',
    'objective': objective,
    'relevantSuccessCriteria': relevantSuccessCriteria,
    'doneCriteria': ['The slice is implemented and summarized.'],
    'outOfScope': ['Do not implement unrelated project work.'],
    'context': ['Use the attached workspace.'],
    'expectedArtifacts': [],
  };
}

Map<String, dynamic> _taskPlanJson() {
  return {
    'title': 'Implement slice',
    'goal': 'Implement the first reporting screen slice',
    'constraints': ['Stay inside workspace.'],
    'successCriteria': ['The slice is implemented and summarized.'],
    'steps': [
      {
        'id': 'build',
        'title': 'Build slice',
        'objective': 'Build the first slice.',
        'instructions': ['Do the bounded work.'],
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

class _QueueCompletionClient extends ChatClient {
  _QueueCompletionClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionResponse> _responses;
  final List<Set<String>> seenToolNames = [];
  final List<List<ChatMessage>> seenMessages = [];
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    seenMessages.add(List<ChatMessage>.of(messages));
    seenToolNames.add(_toolNames(extraParams));
    final index = _index >= _responses.length ? _responses.length - 1 : _index;
    _index++;
    return _responses[index];
  }

  Set<String> _toolNames(Map<String, dynamic>? extraParams) {
    final tools = extraParams?['tools'];
    if (tools is! List) return const {};
    return {
      for (final tool in tools.whereType<Map>())
        if (tool['function'] is Map)
          ((tool['function'] as Map)['name'] ?? '').toString(),
    }..remove('');
  }

  @override
  void dispose() {}
}
