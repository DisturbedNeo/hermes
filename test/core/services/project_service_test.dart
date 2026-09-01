import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

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
      final sandbox = WorkspaceSandbox();
      final taskService = TaskService(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      );
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

    test(
      'continues through successful intermediate steps without pausing',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the reporting screen',
          chatSessionId: 'chat_1',
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: jsonEncode({'task': _projectTaskJson()}),
          ),
          _finaliseTaskResponse(_multiStepTaskPlanJson()),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'First step complete.',
              'memoryUpdate': 'Prepared the reporting data.',
            }),
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Second step complete.',
              'memoryUpdate': 'Rendered the reporting screen.',
            }),
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'complete': true,
              'finalSummary': 'Reporting screen project is complete.',
              'remainingCriteria': [],
              'openQuestions': [],
            }),
          ),
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
        expect(result.activeTask?.status, TaskStatus.completed);
        expect(result.activeTask?.runs.map((run) => run.status), [
          TaskRunStatus.completed,
          TaskRunStatus.completed,
        ]);
      },
    );

    test(
      'pauses on transport failure and resumes the preserved task',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the reporting screen',
          chatSessionId: 'chat_1',
        );
        final client = _ObjectQueueClient([
          jsonEncode({'task': _projectTaskJson()}),
          _finaliseTaskResponse(_taskPlanJson()),
          _projectTransportFailure(),
          jsonEncode({
            'status': 'completed',
            'summary': 'Task complete after resume.',
            'memoryUpdate': 'Transport recovery succeeded.',
          }),
          jsonEncode({
            'complete': true,
            'finalSummary': 'Reporting screen project is complete.',
            'remainingCriteria': [],
            'openQuestions': [],
          }),
        ]);

        final pausedResult = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 0,
        );

        expect(pausedResult.project.status, ProjectStatus.paused);
        expect(pausedResult.project.currentTask, isNotNull);
        expect(pausedResult.project.activeTaskId, pausedResult.activeTask?.id);
        expect(pausedResult.project.failedTasks, isEmpty);
        expect(pausedResult.project.blocker, isNull);
        expect(pausedResult.project.iterationCount, 0);
        expect(pausedResult.activeTask?.status, TaskStatus.paused);
        expect(
          pausedResult.activeTask?.currentStep?.status,
          TaskStepStatus.pending,
        );

        final resumedResult = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: pausedResult.project,
          baseSystemPrompt: 'system',
          maxNewTasks: 0,
        );

        expect(
          resumedResult.project.status,
          ProjectStatus.completed,
          reason: resumedResult.project.blocker?.message,
        );
        expect(resumedResult.project.failedTasks, isEmpty);
        expect(resumedResult.project.iterationCount, 1);
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
      'zero per-run project task limit continues until completion',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
        );
        final client = _QueueChatClient([
          jsonEncode({
            'task': _projectTaskJson(objective: 'Implement the first slice'),
          }),
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'First task complete.',
            'memoryUpdate': 'One slice is done.',
          }),
          jsonEncode({
            'complete': false,
            'finalSummary': '',
            'remainingCriteria': ['Implement the second slice.'],
            'openQuestions': [],
          }),
          jsonEncode({
            'task': _projectTaskJson(
              objective: 'Implement the second slice',
              relevantSuccessCriteria: const ['Implement the second slice.'],
            ),
          }),
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Second task complete.',
            'memoryUpdate': 'The remaining slice is done.',
          }),
          jsonEncode({
            'complete': true,
            'finalSummary': 'Project is complete.',
            'remainingCriteria': [],
            'openQuestions': [],
          }),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 0,
        );

        expect(result.project.status, ProjectStatus.completed);
        expect(result.project.completedTasks, hasLength(2));
        expect(result.project.iterationCount, 2);
      },
    );

    test('zero total project iterations disables the total task cap', () async {
      final project = (await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      )).copyWith(maxIterations: 0, iterationCount: 100);
      final client = _QueueChatClient([
        jsonEncode({'task': _projectTaskJson()}),
        jsonEncode(_taskPlanJson()),
        jsonEncode({
          'status': 'completed',
          'summary': 'Task complete.',
          'memoryUpdate': 'Work is done.',
        }),
        jsonEncode({
          'complete': true,
          'finalSummary': 'Project is complete.',
          'remainingCriteria': [],
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

      expect(result.project.status, ProjectStatus.completed);
      expect(result.project.iterationCount, 101);
      expect(result.project.blocker, isNull);
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
      'downgrades low-risk initialization questions into known facts',
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
                {
                  'question': 'Which UI component should I prioritise?',
                  'reason': 'This only affects implementation order.',
                  'defaultIfUnanswered':
                      'prioritize the first reasonable component, then continue with the rest.',
                  'riskOfAssuming': 'Low; the choice is reversible.',
                  'kind': 'preference',
                },
              ],
              'backlog': [],
            }),
          ]),
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
          baseSystemPrompt: 'system',
          questionAutonomy: QuestionAutonomy.balanced,
        );

        expect(project.status, ProjectStatus.active);
        expect(project.openQuestions, isEmpty);
        expect(project.blocker, isNull);
        expect(project.knownFacts.join('\n'), contains('Assumed: prioritize'));
        expect(
          project.knownFacts.join('\n'),
          contains('Which UI component should I prioritise?'),
        );
      },
    );

    test('keeps credential initialization questions blocking', () async {
      final project = await service.createProject(
        client: _QueueChatClient([
          jsonEncode({
            'title': 'Build app',
            'refinedGoal': 'Build the app',
            'successCriteria': ['App works'],
            'constraints': ['Stay in workspace'],
            'knownFacts': [],
            'openQuestions': [
              {'question': 'What API key should I use?'},
            ],
            'backlog': [],
          }),
        ]),
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
        baseSystemPrompt: 'system',
        questionAutonomy: QuestionAutonomy.autonomous,
      );

      expect(project.status, ProjectStatus.waitingForUser);
      expect(project.pendingQuestion?.question, contains('API key'));
    });

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
        expect(project.backlog, isEmpty);
      },
    );

    test('records composer input as durable project context', () async {
      final created = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );

      final updated = await service.addUserContext(
        workspace: workspace,
        snapshot: created,
        text: 'Use SvelteKit for the web framework.',
      );

      expect(updated.id, created.id);
      expect(updated.knownFacts.join('\n'), contains('SvelteKit'));
      expect(updated.status, ProjectStatus.active);
    });

    test(
      'empty backlog asks for exactly one next task instead of refreshing backlog',
      () async {
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
            content: jsonEncode({
              'task': _projectTaskJson(
                relevantSuccessCriteria: const ['Finish'],
              ),
            }),
          ),
          _finaliseTaskResponse(_taskPlanJson()),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Task complete.',
              'memoryUpdate': 'Finished the selected slice.',
            }),
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'complete': true,
              'finalSummary': 'Done.',
              'remainingCriteria': [],
              'openQuestions': [],
            }),
          ),
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
        expect(result.project.backlog, isEmpty);
        expect(client.seenToolNames.first, isEmpty);
      },
    );

    test('runs queued task without invoking the selector', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final queuedTask = _projectTask(
        id: 'queued_task',
        objective: 'Implement the first slice',
      );
      final previous = project.copyWith(backlog: [queuedTask]);

      final client = _QueueChatClient([
        jsonEncode(_taskPlanJson()),
        jsonEncode({
          'status': 'completed',
          'summary': 'Queued task complete.',
          'memoryUpdate': 'Implemented the queued task.',
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
        snapshot: previous,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.blocker, isNull);
      expect(result.project.failedTasks, isEmpty);
      expect(result.project.completedTasks.single.id, queuedTask.id);
      expect(client.taskSelectorRequestCount, 0);
    });

    test(
      'clears legacy duplicate-task blocker and resumes queued work',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
        );
        final queuedTask = _projectTask(
          id: 'queued_task',
          objective: 'Implement the first slice',
        );
        final previous = project.copyWith(
          backlog: [queuedTask],
          status: ProjectStatus.blocked,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.duplicateTask,
            message: 'Project task repeated previous work.',
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        final result = await service.runProject(
          client: _QueueChatClient([
            jsonEncode(_taskPlanJson()),
            jsonEncode({
              'status': 'completed',
              'summary': 'Queued task complete.',
              'memoryUpdate': 'Resumed after legacy blocker.',
            }),
            jsonEncode({
              'complete': false,
              'finalSummary': '',
              'remainingCriteria': ['Complete the stated project goal.'],
              'openQuestions': [],
            }),
          ]),
          workspace: workspace,
          snapshot: previous,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.paused);
        expect(result.project.blocker, isNull);
        expect(result.project.completedTasks.single.id, queuedTask.id);
      },
    );

    test(
      'resumes a validation-blocked project with executable recovered work',
      () async {
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
        );
        final queuedTask = _projectTask(
          id: 'queued_task',
          objective: 'Implement the recovered slice',
        );
        final previous = project.copyWith(
          backlog: [queuedTask],
          currentTask: queuedTask,
          status: ProjectStatus.blocked,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.validation,
            message:
                'Project task selection produced 3 invalid candidates in a row.',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final client = _QueueChatClient([
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Recovered task complete.',
            'memoryUpdate': 'Resumed recovered project work.',
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
          snapshot: previous,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.paused);
        expect(result.project.blocker, isNull);
        expect(result.project.completedTasks.single.id, queuedTask.id);
        expect(client.taskSelectorRequestCount, 0);
      },
    );

    test('rejects completed duplicate proposals and continues', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final completedTask = _projectTask(
        id: 'completed_task',
        objective: 'Implement the first slice',
        status: ProjectTaskStatus.completed,
      );
      final previous = project.copyWith(completedTasks: [completedTask]);

      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'task': _projectTaskJson(objective: 'Implement the first slice'),
          }),
          jsonEncode({
            'task': _projectTaskJson(objective: 'Implement the second slice'),
          }),
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Second task complete.',
            'memoryUpdate': 'Implemented another slice.',
          }),
          jsonEncode({
            'complete': false,
            'finalSummary': '',
            'remainingCriteria': ['Complete the stated project goal.'],
            'openQuestions': [],
          }),
        ]),
        workspace: workspace,
        snapshot: previous,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.blocker, isNull);
      expect(
        result.project.failedTasks.single.status,
        ProjectTaskStatus.rejected,
      );
      expect(result.project.completedTasks, hasLength(2));
      expect(
        result.project.completedTasks.last.objective,
        'Implement the second slice',
      );
    });

    test('converts failed duplicate proposals into retry tasks', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final failedTask = _projectTask(
        id: 'failed_task',
        objective: 'Implement the first slice',
        status: ProjectTaskStatus.failed,
      ).copyWith(rejectionReason: 'Previous attempt failed tests.');
      final previous = project.copyWith(failedTasks: [failedTask]);

      final result = await service.runProject(
        client: _QueueChatClient([
          jsonEncode({
            'task': _projectTaskJson(objective: 'Implement the first slice'),
          }),
          jsonEncode(_taskPlanJson()),
          jsonEncode({
            'status': 'completed',
            'summary': 'Retry complete.',
            'memoryUpdate': 'Retried and completed the work.',
          }),
          jsonEncode({
            'complete': false,
            'finalSummary': '',
            'remainingCriteria': ['Complete the stated project goal.'],
            'openQuestions': [],
          }),
        ]),
        workspace: workspace,
        snapshot: previous,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.blocker, isNull);
      expect(result.project.failedTasks, hasLength(2));
      expect(
        result.project.failedTasks.last.status,
        ProjectTaskStatus.rejected,
      );
      expect(
        result.project.completedTasks.single.objective,
        startsWith('Retry'),
      );
    });

    test('does not execute one giant task for a broad project goal', () async {
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the entire product',
        chatSessionId: 'chat_1',
      );

      final client = _QueueChatClient([
        jsonEncode({
          'task': _projectTaskJson(
            objective: 'Complete the entire project end-to-end',
            relevantSuccessCriteria: ['Complete the stated project goal.'],
          ),
        }),
        jsonEncode({'tasks': []}),
        jsonEncode(_taskPlanJson()),
        jsonEncode({
          'status': 'completed',
          'summary': 'Split task complete.',
          'memoryUpdate': 'Completed focused progress instead.',
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
      expect(result.project.completedTasks, hasLength(1));
      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.blocker, isNull);
      expect(client.taskSelectorRequestCount, 1);
    });

    test(
      'creates recovery incident and recovery task for failed command gate',
      () async {
        workspace = workspace.copyWith(commandExecutionApproved: true);
        final project = await service.createProject(
          workspace: workspace,
          userPrompt: 'Build the app',
          chatSessionId: 'chat_1',
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: jsonEncode({'task': _projectTaskJson()}),
          ),
          _finaliseTaskResponse(_taskPlanWithCommandGate()),
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'run_command',
                arguments: jsonEncode({'command': 'test -f recovered.txt'}),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary':
                  'Implementation done; health check can be fixed later.',
              'memoryUpdate': 'Health check is still red.',
            }),
          ),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.paused);
        expect(result.project.recoveryIncidents, hasLength(1));
        final incident = result.project.recoveryIncidents.single;
        expect(incident.status, ProjectRecoveryIncidentStatus.active);
        expect(incident.failedGateId, 'command_passes');
        expect(incident.command, 'test -f recovered.txt');
        expect(incident.attemptCount, 0);
        expect(
          result.project.failedTasks.single.recoveryIncidentId,
          incident.id,
        );
        expect(result.project.backlog.first.recoveryIncidentId, incident.id);
        expect(result.project.backlog.first.objective, contains('Restore'));
      },
    );

    test('routes retryable tool errors into project recovery', () async {
      await File('${root.path}/source.txt').writeAsString('source');
      final project = await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: jsonEncode({'task': _projectTaskJson()}),
        ),
        _finaliseTaskResponse(_taskPlanJson()),
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'read_file',
              arguments: jsonEncode({
                'path': 'source.txt',
                'request': 'Summarize this file.',
              }),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'The bounded work is complete.',
            'memoryUpdate': 'Implementation finished.',
          }),
        ),
      ]);

      final result = await service.runProject(
        client: client,
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.paused);
      expect(result.project.recoveryIncidents, hasLength(1));
      expect(
        result.project.recoveryIncidents.single.failedGateId,
        'no_tool_errors',
      );
      expect(
        result.project.failedTasks.single.failure?.disposition,
        TaskGateFailureDisposition.repairable,
      );
      expect(
        result.project.failedTasks.single.failure?.errorCodes,
        contains('tool_dependency_unavailable'),
      );
    });

    test('maximum distinct failures block instead of failing', () async {
      final first =
          _projectTask(
            id: 'failed_1',
            objective: 'First failure',
            status: ProjectTaskStatus.failed,
          ).copyWith(
            failure: const ProjectTaskFailure(
              disposition: TaskGateFailureDisposition.blocking,
              failureKey: 'failure_1',
              summary: 'First failure.',
            ),
          );
      final second =
          _projectTask(
            id: 'failed_2',
            objective: 'Second failure',
            status: ProjectTaskStatus.failed,
          ).copyWith(
            failure: const ProjectTaskFailure(
              disposition: TaskGateFailureDisposition.blocking,
              failureKey: 'failure_2',
              summary: 'Second failure.',
            ),
          );
      final queued = _projectTask(id: 'third', objective: 'Third failure');
      final project = (await service.createProject(
        workspace: workspace,
        userPrompt: 'Build the app',
        chatSessionId: 'chat_1',
      )).copyWith(failedTasks: [first, second], backlog: [queued]);
      final client = _QueueCompletionClient([
        _finaliseTaskResponse(_taskPlanJson()),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'failed',
            'summary': 'Third distinct execution failure.',
            'memoryUpdate': '',
            'error': 'Third distinct execution failure.',
          }),
        ),
      ]);

      final result = await service.runProject(
        client: client,
        workspace: workspace,
        snapshot: project,
        baseSystemPrompt: 'system',
        maxNewTasks: 1,
      );

      expect(result.project.status, ProjectStatus.blocked);
      expect(result.project.blocker?.type, ProjectBlockerType.maxFailures);
      expect(result.project.isTerminal, isFalse);
    });

    test(
      'selects recovery task before normal backlog and resolves incident',
      () async {
        workspace = workspace.copyWith(commandExecutionApproved: true);
        final now = DateTime(2026, 1, 1);
        final incident = ProjectRecoveryIncident(
          id: 'recovery_1',
          status: ProjectRecoveryIncidentStatus.active,
          sourceTaskIds: const ['task_source'],
          sourceTaskTitles: const ['Source task'],
          failedGateId: 'command_passes',
          command: 'test -f recovered.txt',
          workingDirectory: '.',
          failureSummary: 'Verification command failed.',
          attemptCount: 0,
          recoveryTaskIds: const ['recovery_task'],
          createdAt: now,
          updatedAt: now,
        );
        final recoveryTask = _projectTask(
          id: 'recovery_task',
          objective:
              'Restore required project health gate: test -f recovered.txt',
          recoveryIncidentId: incident.id,
        );
        final normalTask = _projectTask(
          id: 'normal_task',
          objective: 'Implement a normal feature slice',
        );
        final project =
            (await service.createProject(
              workspace: workspace,
              userPrompt: 'Build the app',
              chatSessionId: 'chat_1',
            )).copyWith(
              backlog: [normalTask, recoveryTask],
              recoveryIncidents: [incident],
            );
        final client = _QueueCompletionClient([
          _finaliseTaskResponse(
            _taskPlanWithCommandGate(
              goal:
                  'Restore required project health gate: test -f recovered.txt',
              successCriteria: const ['The task is completed and summarized.'],
            ),
          ),
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'write_file',
                arguments: jsonEncode({
                  'path': 'recovered.txt',
                  'content': 'ok',
                }),
              ),
              ChatCompletionToolCall(
                name: 'run_command',
                arguments: jsonEncode({'command': 'test -f recovered.txt'}),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Recovered project health.',
              'memoryUpdate': 'The required gate is green.',
            }),
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'complete': false,
              'finalSummary': '',
              'remainingCriteria': ['Complete the stated project goal.'],
              'openQuestions': [],
            }),
          ),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.completedTasks.single.id, 'recovery_task');
        expect(result.project.backlog.single.id, 'normal_task');
        expect(
          result.project.recoveryIncidents.single.status,
          ProjectRecoveryIncidentStatus.resolved,
        );
      },
    );

    test(
      'exhausts one recovery incident without counting each task failure',
      () async {
        workspace = workspace.copyWith(commandExecutionApproved: true);
        final now = DateTime(2026, 1, 1);
        final incident = ProjectRecoveryIncident(
          id: 'recovery_1',
          status: ProjectRecoveryIncidentStatus.active,
          sourceTaskIds: const ['task_source'],
          sourceTaskTitles: const ['Source task'],
          failedGateId: 'command_passes',
          command: 'test -f recovered.txt',
          workingDirectory: '.',
          failureSummary: 'Verification command failed.',
          attemptCount: 2,
          recoveryTaskIds: const ['recovery_task'],
          createdAt: now,
          updatedAt: now,
        );
        final project =
            (await service.createProject(
              workspace: workspace,
              userPrompt: 'Build the app',
              chatSessionId: 'chat_1',
            )).copyWith(
              maxFailedTasks: 3,
              failedTasks: [
                _projectTask(
                  id: 'failed_source',
                  objective: 'Original source task',
                  recoveryIncidentId: incident.id,
                  status: ProjectTaskStatus.failed,
                ),
                _projectTask(
                  id: 'failed_recovery_1',
                  objective: 'First recovery attempt',
                  recoveryIncidentId: incident.id,
                  status: ProjectTaskStatus.failed,
                ),
              ],
              backlog: [
                _projectTask(
                  id: 'recovery_task',
                  objective:
                      'Restore required project health gate: test -f recovered.txt',
                  recoveryIncidentId: incident.id,
                ),
              ],
              recoveryIncidents: [incident],
            );
        final client = _QueueCompletionClient([
          _finaliseTaskResponse(
            _taskPlanWithCommandGate(
              goal:
                  'Restore required project health gate: test -f recovered.txt',
              successCriteria: const ['The task is completed and summarized.'],
            ),
          ),
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'run_command',
                arguments: jsonEncode({'command': 'test -f recovered.txt'}),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Still failing.',
              'memoryUpdate': 'The required gate is still red.',
            }),
          ),
        ]);

        final result = await service.runProject(
          client: client,
          workspace: workspace,
          snapshot: project,
          baseSystemPrompt: 'system',
          maxNewTasks: 1,
        );

        expect(result.project.status, ProjectStatus.blocked);
        expect(result.project.blocker?.type, ProjectBlockerType.recoveryFailed);
        expect(
          result.project.recoveryIncidents.single.status,
          ProjectRecoveryIncidentStatus.exhausted,
        );
        expect(result.project.recoveryIncidents.single.attemptCount, 3);
      },
    );

    test('manual recovery retry persists one additional attempt', () async {
      final now = DateTime(2026, 1, 1);
      final incident = ProjectRecoveryIncident(
        id: 'recovery_1',
        status: ProjectRecoveryIncidentStatus.exhausted,
        sourceTaskIds: const ['task_source'],
        sourceTaskTitles: const ['Source task'],
        failedGateId: 'no_tool_errors',
        failureSummary: 'A retryable tool error remains unresolved.',
        attemptCount: 3,
        recoveryTaskIds: const ['recovery_1', 'recovery_2', 'recovery_3'],
        createdAt: now,
        updatedAt: now,
        resolvedAt: now,
      );
      final failedSource = _projectTask(
        id: 'failed_source',
        objective: 'Original source task',
        recoveryIncidentId: incident.id,
        status: ProjectTaskStatus.failed,
      );
      final project =
          (await service.createProject(
            workspace: workspace,
            userPrompt: 'Build the app',
            chatSessionId: 'chat_1',
          )).copyWith(
            status: ProjectStatus.blocked,
            failedTasks: [failedSource],
            recoveryIncidents: [incident],
            blocker: ProjectBlocker(
              type: ProjectBlockerType.recoveryFailed,
              message: 'Recovery exhausted.',
              createdAt: now,
            ),
          );

      final updated = await service.retryRecoveryIncident(
        workspace: workspace,
        snapshot: project,
        incidentId: incident.id,
      );
      final persisted = await service.repository.loadProject(
        workspace.rootPath,
        project.id,
      );

      expect(updated.status, ProjectStatus.active);
      expect(updated.blocker, isNull);
      expect(
        updated.recoveryIncidents.single.status,
        ProjectRecoveryIncidentStatus.active,
      );
      expect(updated.recoveryIncidents.single.maxAttempts, 4);
      expect(updated.backlog.single.recoveryIncidentId, incident.id);
      expect(
        updated.decisions.last.decision,
        ProjectDecisionType.retryRecovery,
      );
      expect(persisted?.recoveryIncidents.single.maxAttempts, 4);
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

Map<String, dynamic> _multiStepTaskPlanJson() {
  return {
    'title': 'Implement slice',
    'goal': 'Implement the first reporting screen slice',
    'constraints': ['Stay inside workspace.'],
    'successCriteria': ['The slice is implemented and summarized.'],
    'steps': [
      {
        'id': 'prepare',
        'title': 'Prepare data',
        'objective': 'Prepare the reporting data.',
        'instructions': ['Do the first bounded step.'],
        'mayEditFiles': false,
      },
      {
        'id': 'render',
        'title': 'Render screen',
        'objective': 'Render the reporting screen.',
        'instructions': ['Do the second bounded step.'],
        'mayEditFiles': false,
      },
    ],
  };
}

Map<String, dynamic> _taskPlanWithCommandGate({
  String goal = 'Implement the first reporting screen slice',
  List<String> successCriteria = const [
    'The slice is implemented and summarized.',
  ],
}) {
  return {
    'title': 'Implement slice',
    'goal': goal,
    'constraints': ['Stay inside workspace.'],
    'successCriteria': successCriteria,
    'steps': [
      {
        'id': 'build',
        'title': 'Build slice',
        'objective': goal,
        'instructions': ['Do the bounded work.'],
        'mayEditFiles': true,
        'gates': [
          {
            'id': 'command_passes',
            'required': true,
            'scope': 'step',
            'params': {
              'command': 'test -f recovered.txt',
              'working_directory': '.',
            },
          },
        ],
      },
    ],
  };
}

ProjectTask _projectTask({
  required String id,
  required String objective,
  ProjectTaskStatus status = ProjectTaskStatus.queued,
  String? recoveryIncidentId,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectTask(
    id: id,
    title: objective,
    objective: objective,
    relevantSuccessCriteria: const ['Complete the stated project goal.'],
    doneCriteria: const ['The task is completed and summarized.'],
    outOfScope: const ['Do not implement unrelated project work.'],
    context: const [],
    expectedArtifacts: const [],
    status: status,
    taskDocumentId: null,
    recoveryIncidentId: recoveryIncidentId,
    fingerprint: projectTaskFingerprint(objective, const [
      'Complete the stated project goal.',
    ]),
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}

ChatCompletionResponse _finaliseTaskResponse(Map<String, dynamic> arguments) {
  return ChatCompletionResponse(
    content: '',
    toolCalls: [
      ChatCompletionToolCall(
        name: 'finaliseTaskCreation',
        arguments: jsonEncode(arguments),
      ),
    ],
  );
}

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> _responses;
  var _index = 0;
  final List<List<ChatMessage>> _requests = [];

  int get taskSelectorRequestCount => _requests
      .where(
        (messages) => messages.any(
          (message) =>
              message.content.contains('Propose exactly one next bounded task'),
        ),
      )
      .length;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    _requests.add(List<ChatMessage>.of(messages));
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
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
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

class _ObjectQueueClient extends ChatClient {
  _ObjectQueueClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<Object> _responses;
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final response = _responses[_index++];
    if (response is ChatTransportException) throw response;
    if (response is ChatCompletionResponse) return response;
    return ChatCompletionResponse(content: response as String);
  }

  @override
  void dispose() {}
}

ChatTransportException _projectTransportFailure() => ChatTransportException(
  kind: ChatTransportFailureKind.brokenPipe,
  uri: Uri.parse('http://localhost/v1/chat/completions'),
  attempts: 2,
  outputStarted: false,
  cause: const SocketException(
    'Write failed',
    osError: OSError('Broken pipe', 32),
  ),
  causeStackTrace: StackTrace.empty,
);
