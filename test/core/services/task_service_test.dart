import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

void main() {
  group('TaskService linear runner', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late TaskService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_task_service_');
      workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final sandbox = WorkspaceSandbox();
      service = TaskService(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      );
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('creates a persisted paused multi-step task', () async {
      final client = _QueueChatClient([
        jsonEncode(_planJson(title: 'Planned task')),
      ]);

      final task = await service.createTask(
        client: client,
        workspace: workspace,
        userPrompt: 'Build the reporting screen',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      expect(task.title, 'Planned task');
      expect(task.status, TaskStatus.paused);
      expect(task.currentStepId, 'inspect');
      expect(task.steps, hasLength(2));
      expect(
        File(
          path.join(root.path, '.agent', 'tasks', task.id, 'task.json'),
        ).existsSync(),
        isTrue,
      );
    });

    test('planner can inspect files before finalising task creation', () async {
      await File(
        path.join(root.path, 'design.md'),
      ).writeAsString('# Design\nBuild the analytics screen.\n');
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
              name: 'finaliseTaskCreation',
              arguments: jsonEncode(_planJson(title: 'Design-informed task')),
            ),
          ],
        ),
      ]);

      final task = await service.createTask(
        client: client,
        workspace: workspace,
        userPrompt: 'Plan from the design document',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      expect(task.title, 'Design-informed task');
      expect(client.requestCount, 2);
      expect(client.seenToolNames.first, contains('read_file'));
      expect(client.seenToolNames.first, contains('search_files'));
      expect(client.seenToolNames.first, contains('finaliseTaskCreation'));
      expect(client.seenToolNames.first, isNot(contains('write_file')));
      expect(client.seenToolNames.first, isNot(contains('patch_file')));
      expect(client.seenToolNames.first, isNot(contains('run_command')));
      expect(
        client.seenMessages.last.any((message) {
          return message.role == 'tool' &&
              message.content.contains('Build the analytics screen');
        }),
        isTrue,
      );
    });

    test('task creation accepts planner-selected gates', () async {
      final plan = _planJson(title: 'Gated task')
        ..['gates'] = [
          {'id': 'no_tool_errors', 'required': true, 'scope': 'task'},
        ]
        ..['steps'] = [
          {
            'id': 'write_report',
            'title': 'Write report',
            'objective': 'Write the report artifact.',
            'instructions': ['Write report.'],
            'mayEditFiles': false,
            'artifacts': [
              {'path': '.agent/tasks/{{task_id}}/report.md'},
            ],
            'gates': [
              {
                'id': 'artifact_exists',
                'required': true,
                'scope': 'step',
                'params': {
                  'paths': ['.agent/tasks/{{task_id}}/report.md'],
                },
              },
            ],
          },
        ];
      final client = _QueueChatClient([jsonEncode(plan)]);

      final task = await service.createTask(
        client: client,
        workspace: workspace,
        userPrompt: 'Write a report',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      expect(task.gates.single.id, 'no_tool_errors');
      expect(task.steps.single.gates, isNotEmpty);
      expect(task.steps.single.gates.first.id, 'artifact_exists');
      expect(
        task.steps.single.gates.first.params.toString(),
        contains(task.id),
      );
    });

    test('planner retries once when finalizer is missing', () async {
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: jsonEncode(_planJson(title: 'Plain JSON task')),
        ),
        ChatCompletionResponse(
          content: jsonEncode(_planJson(title: 'Repaired JSON task')),
        ),
      ]);

      final task = await service.createTask(
        client: client,
        workspace: workspace,
        userPrompt: 'Build the reporting screen',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      expect(task.title, 'Repaired JSON task');
      expect(client.requestCount, 2);
      expect(client.seenToolNames.first, contains('finaliseTaskCreation'));
      expect(client.seenToolNames.last, isEmpty);
    });

    test('passes terminal approval into task planner metadata', () async {
      workspace = workspace.copyWith(commandExecutionApproved: true);
      final client = _QueueChatClient([
        jsonEncode(_planJson(title: 'Planned task')),
      ]);

      await service.createTask(
        client: client,
        workspace: workspace,
        userPrompt: 'Inspect the design document',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      final plannerRequest = client.seenMessages.first.last.content;
      expect(plannerRequest, contains('"commandExecutionApproved": true'));
    });

    test(
      'passes bounded project planning context into planner prompt',
      () async {
        final client = _QueueChatClient([
          jsonEncode(_projectBoundedPlanJson(title: 'Bounded task')),
        ]);

        await service.createTask(
          client: client,
          workspace: workspace,
          userPrompt: 'Implement the settings toggle',
          selectedMode: ExecutionMode.task,
          baseSystemPrompt: 'system',
          chatSessionId: 'chat_1',
          projectId: 'project_1',
          planningContext: const TaskPlanningContext(
            projectGoal: 'Build the whole app',
            projectTaskObjective: 'Implement the settings toggle',
            doneCriteria: ['The settings toggle works.'],
            outOfScope: ['Do not build the whole app.'],
            maxSteps: 3,
          ),
        );

        final plannerRequest = client.seenMessages.first.last.content;
        expect(plannerRequest, contains('Bounded Project task context'));
        expect(
          plannerRequest,
          contains('Do not plan or perform the whole project'),
        );
        expect(plannerRequest, contains('Implement the settings toggle'));
        expect(plannerRequest, contains('Do not build the whole app.'));
      },
    );

    test(
      'falls back when project task planner expands to whole project',
      () async {
        final broadPlan = jsonEncode(_wholeProjectPlanJson());
        final client = _QueueChatClient([broadPlan, broadPlan]);

        final task = await service.createTask(
          client: client,
          workspace: workspace,
          userPrompt: 'Implement the settings toggle',
          selectedMode: ExecutionMode.task,
          baseSystemPrompt: 'system',
          chatSessionId: 'chat_1',
          projectId: 'project_1',
          planningContext: const TaskPlanningContext(
            projectGoal: 'Build the whole app',
            projectTaskObjective: 'Implement the settings toggle',
            doneCriteria: ['The settings toggle works.'],
            outOfScope: ['Do not build the whole app.'],
            maxSteps: 3,
          ),
        );

        expect(task.goal, 'Implement the settings toggle');
        expect(task.steps, hasLength(1));
        expect(task.steps.single.id, 'execute_project_task');
        expect(task.successCriteria, contains('The settings toggle works.'));
      },
    );

    test('fallback task adds conservative default gates', () async {
      final client = _QueueChatClient(['not json']);

      final task = await service.createTask(
        client: client,
        workspace: workspace,
        userPrompt: 'Implement a code fix',
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      expect(task.gates.map((gate) => gate.id), contains('no_tool_errors'));
      expect(task.gates.map((gate) => gate.id), contains('no_failed_commands'));
      expect(
        task.steps.single.gates.map((gate) => gate.id),
        contains('artifact_exists'),
      );
    });

    test('runs one step and records structured memory and history', () async {
      final task = _task(
        step: const TaskStep(
          id: 'step_1',
          title: 'Step 1',
          objective: 'Do the work',
          instructions: ['Work carefully'],
          mayEditFiles: false,
          artifacts: [TaskArtifact(path: '.agent/tasks/task_test/notes.md')],
          status: TaskStepStatus.pending,
        ),
      );
      await service.repository.saveSnapshot(root.path, task);
      final client = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'Inspected the workspace.',
          'memoryUpdate': 'Found a Flutter app.',
          'artifacts': [
            {'path': '.agent/tasks/task_test/notes.md'},
          ],
        }),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(updated.status, TaskStatus.completed);
      expect(updated.steps.single.status, TaskStepStatus.completed);
      expect(updated.runs.single.status, TaskRunStatus.completed);
      expect(updated.memorySummary, contains('Found a Flutter app.'));
      expect(updated.runs.single.artifacts.single.path, contains('notes.md'));
    });

    test('runs one step from finish task step tool call', () async {
      final task = _task();
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'finish_task_step',
              arguments: jsonEncode({
                'status': 'completed',
                'summary': 'Inspected the workspace.',
                'memoryUpdate': 'Found a Flutter app.',
              }),
            ),
          ],
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(client.requestCount, 1);
      expect(client.seenToolNames.single, contains('finish_task_step'));
      expect(
        client.seenMessages.single.where((message) => message.role == 'system'),
        hasLength(1),
      );
      expect(
        client.seenMessages.single.first.content,
        contains('You execute one step of a larger linear task.'),
      );
      expect(updated.status, TaskStatus.completed);
      expect(updated.runs.single.status, TaskRunStatus.completed);
      expect(updated.runs.single.summary, 'Inspected the workspace.');
      expect(updated.memorySummary, contains('Found a Flutter app.'));
      expect(updated.runs.single.toolCalls.single.toolName, 'finish_task_step');
    });

    test(
      'finish task step tool call skips sibling workspace tool calls',
      () async {
        final task = _task();
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'read_file',
                arguments: jsonEncode({'path': 'missing.txt'}),
              ),
              ChatCompletionToolCall(
                name: 'finish_task_step',
                arguments: jsonEncode({
                  'status': 'completed',
                  'summary': 'Finished without more reads.',
                  'memoryUpdate': 'Existing context was sufficient.',
                }),
              ),
            ],
          ),
        ]);

        final updated = await service.runNextStep(
          client: client,
          workspace: workspace,
          snapshot: task,
          baseSystemPrompt: 'system',
        );

        expect(client.requestCount, 1);
        expect(updated.status, TaskStatus.completed);
        expect(updated.runs.single.summary, 'Finished without more reads.');
        expect(updated.runs.single.toolCalls, hasLength(1));
        expect(
          updated.runs.single.toolCalls.single.toolName,
          'finish_task_step',
        );
        expect(updated.runs.single.toolCalls.single.error, isNull);
      },
    );

    test('pauses for phase approval before mutating steps', () async {
      final task = _task(
        step: const TaskStep(
          id: 'edit',
          title: 'Edit files',
          objective: 'Edit files',
          instructions: ['Patch files'],
          mayEditFiles: true,
          artifacts: [],
          status: TaskStepStatus.pending,
        ),
      );

      final blocked = await service.runNextStep(
        client: _QueueChatClient([
          jsonEncode({'status': 'completed'}),
        ]),
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
        requirePhaseApproval: true,
      );

      expect(blocked.status, TaskStatus.blocked);
      expect(blocked.pendingApproval?.stepId, 'edit');
      expect(blocked.steps.single.status, TaskStepStatus.blocked);

      final approved = await service.approvePendingStep(
        workspace: workspace,
        snapshot: blocked,
      );

      expect(approved.status, TaskStatus.paused);
      expect(approved.pendingApproval, isNull);
      expect(approved.steps.single.status, TaskStepStatus.approved);
    });

    test('records blocked user questions and resumes after answer', () async {
      final task = _task();
      final blocked = await service.runNextStep(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'blocked',
            'summary': 'Need a target platform.',
            'userQuestion': 'Which platform should this target?',
          }),
        ]),
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(blocked.status, TaskStatus.blocked);
      expect(blocked.pendingQuestion?.question, contains('platform'));

      final answered = await service.answerOpenQuestion(
        workspace: workspace,
        snapshot: blocked,
        answer: 'Desktop first.',
      );

      expect(answered.status, TaskStatus.paused);
      expect(answered.pendingQuestion, isNull);
      expect(answered.steps.single.status, TaskStepStatus.pending);
      expect(answered.memorySummary, contains('Desktop first.'));
    });

    test(
      'downgrades low-risk priority questions under balanced autonomy',
      () async {
        final task = _task();
        final updated = await service.runNextStep(
          client: _QueueChatClient([
            jsonEncode({
              'status': 'blocked',
              'summary': 'Need a UI priority.',
              'userQuestion': {
                'question': 'Which UI component should I prioritise?',
                'reason': 'This only affects implementation order.',
                'defaultIfUnanswered':
                    'prioritize the first reasonable component, then continue with the rest.',
                'riskOfAssuming': 'Low; the choice is reversible.',
                'kind': 'preference',
              },
            }),
          ]),
          workspace: workspace,
          snapshot: task,
          baseSystemPrompt: 'system',
          questionAutonomy: QuestionAutonomy.balanced,
        );

        expect(updated.status, TaskStatus.completed);
        expect(updated.pendingQuestion, isNull);
        expect(updated.runs.single.status, TaskRunStatus.completed);
        expect(updated.runs.single.summary, contains('Question policy'));
        expect(updated.memorySummary, contains('Assumed: prioritize'));
      },
    );

    test('still blocks credential questions under autonomous mode', () async {
      final task = _task();
      final blocked = await service.runNextStep(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'blocked',
            'summary': 'Need credentials.',
            'userQuestion': 'What API key should I use?',
          }),
        ]),
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
        questionAutonomy: QuestionAutonomy.autonomous,
      );

      expect(blocked.status, TaskStatus.blocked);
      expect(blocked.pendingQuestion?.question, contains('API key'));
    });

    test('automatically replans unfinished work when requested', () async {
      final task = _task(
        steps: const [
          TaskStep(
            id: 'done',
            title: 'Done',
            objective: 'Already done',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.completed,
          ),
          TaskStep(
            id: 'next',
            title: 'Next',
            objective: 'Next work',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.pending,
          ),
        ],
        currentStepId: 'next',
      );
      final client = _QueueChatClient([
        jsonEncode({
          'status': 'needs_replan',
          'summary': 'Plan is stale.',
          'replanRequest': 'Add a verification step.',
        }),
        jsonEncode({
          'steps': [
            {
              'id': 'verify',
              'title': 'Verify',
              'objective': 'Verify the result',
              'instructions': ['Run checks'],
              'mayEditFiles': false,
            },
          ],
        }),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(updated.steps.map((step) => step.id), ['done', 'verify']);
      expect(updated.currentStepId, 'verify');
      expect(updated.runs.map((run) => run.status), [
        TaskRunStatus.needsReplan,
        TaskRunStatus.replanned,
      ]);
      expect(updated.memorySummary, contains('Add a verification step.'));
    });

    test('read-only steps reject writes outside the task folder', () async {
      final task = _task();
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'write_file',
              arguments: jsonEncode({
                'path': 'should-not-exist.txt',
                'content': 'bad',
              }),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Stayed read-only.',
            'memoryUpdate': 'No files were changed.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(
        File(path.join(root.path, 'should-not-exist.txt')).existsSync(),
        isFalse,
      );
      expect(client.seenToolNames.first, contains('write_file'));
      expect(client.seenToolNames.first, isNot(contains('run_command')));
      expect(client.seenToolNames.first, isNot(contains('patch_file')));
      expect(updated.runs.single.toolCalls.single.toolName, 'write_file');
      expect(
        updated.runs.single.toolCalls.single.error,
        contains('task-owned artifact'),
      );
      expect(updated.status, TaskStatus.completed);
    });

    test(
      'required gate prevents completion after unresolved tool error',
      () async {
        final task = _task(
          step: const TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Do the work',
            instructions: ['Work carefully'],
            mayEditFiles: false,
            artifacts: [],
            gates: [TaskGate(id: 'no_tool_errors')],
            status: TaskStepStatus.pending,
          ),
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'read_file',
                arguments: jsonEncode({
                  'path': 'README.md',
                  'request': 'Summarize this file.',
                }),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Stayed read-only.',
              'memoryUpdate': 'No files were changed.',
            }),
          ),
        ]);

        final updated = await service.runNextStep(
          client: client,
          workspace: workspace,
          snapshot: task,
          baseSystemPrompt: 'system',
        );

        expect(updated.status, TaskStatus.failed);
        expect(updated.runs.single.status, TaskRunStatus.failed);
        expect(updated.runs.single.gateResults.single.gateId, 'no_tool_errors');
        expect(
          updated.runs.single.gateResults.single.status,
          TaskGateStatus.failed,
        );
      },
    );

    test('command_passes gate accepts matching successful command', () async {
      workspace = workspace.copyWith(commandExecutionApproved: true);
      final task = _task(
        step: const TaskStep(
          id: 'step_1',
          title: 'Step 1',
          objective: 'Verify toolchain',
          instructions: ['Run dart --version.'],
          mayEditFiles: true,
          artifacts: [],
          gates: [
            TaskGate(
              id: 'command_passes',
              params: {'command': 'dart --version', 'working_directory': '.'},
            ),
          ],
          status: TaskStepStatus.pending,
        ),
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'run_command',
              arguments: jsonEncode({'command': 'dart --version'}),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Verified dart.',
            'memoryUpdate': 'dart is available.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(updated.status, TaskStatus.completed);
      expect(
        updated.runs.single.gateResults.single.status,
        TaskGateStatus.passed,
      );
      expect(updated.runs.single.toolCalls.single.result, {
        'command': 'dart --version',
        'working_directory': '.',
        'exit_code': 0,
      });
    });

    test(
      'read-only command_passes gate exposes only the required command',
      () async {
        workspace = workspace.copyWith(commandExecutionApproved: true);
        final task = _task(
          step: const TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Verify toolchain',
            instructions: ['Run dart --version.'],
            mayEditFiles: false,
            artifacts: [],
            gates: [
              TaskGate(
                id: 'command_passes',
                params: {'command': 'dart --version', 'working_directory': '.'},
              ),
            ],
            status: TaskStepStatus.pending,
          ),
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'run_command',
                arguments: jsonEncode({'command': 'dart --version'}),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Verified dart.',
              'memoryUpdate': 'dart is available.',
            }),
          ),
        ]);

        final updated = await service.runNextStep(
          client: client,
          workspace: workspace,
          snapshot: task,
          baseSystemPrompt: 'system',
        );

        final executorPrompt = client.seenMessages.first.last.content;
        expect(client.seenToolNames.first, contains('run_command'));
        expect(executorPrompt, contains('Whitelisted terminal commands'));
        expect(updated.status, TaskStatus.completed);
        expect(updated.runs.single.toolCalls.single.error, isNull);
        expect(
          updated.runs.single.gateResults.single.status,
          TaskGateStatus.passed,
        );
      },
    );

    test(
      'read-only command_passes gate rejects non-whitelisted command variants',
      () async {
        workspace = workspace.copyWith(commandExecutionApproved: true);
        final task = _task(
          step: const TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Verify toolchain',
            instructions: ['Run dart --version.'],
            mayEditFiles: false,
            artifacts: [],
            gates: [
              TaskGate(
                id: 'command_passes',
                params: {'command': 'dart --version', 'working_directory': '.'},
              ),
              TaskGate(id: 'no_tool_errors'),
            ],
            status: TaskStepStatus.pending,
          ),
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'run_command',
                arguments: jsonEncode({
                  'command': 'dart --version > version.txt',
                }),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Tried a redirected command.',
              'memoryUpdate': '',
            }),
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'steps': [
                {
                  'id': 'verify_command',
                  'title': 'Verify command',
                  'objective': 'Run the exact required command.',
                  'instructions': ['Run dart --version exactly.'],
                  'mayEditFiles': false,
                },
              ],
            }),
          ),
        ]);

        final updated = await service.runNextStep(
          client: client,
          workspace: workspace,
          snapshot: task,
          baseSystemPrompt: 'system',
        );

        expect(updated.status, TaskStatus.paused);
        expect(updated.currentStepId, 'verify_command');
        expect(updated.runs.map((run) => run.status), [
          TaskRunStatus.needsReplan,
          TaskRunStatus.replanned,
        ]);
        expect(
          updated.runs.first.toolCalls.single.error,
          contains('not whitelisted'),
        );
        expect(
          updated.runs.first.gateResults
              .singleWhere((result) => result.gateId == 'command_passes')
              .status,
          TaskGateStatus.pending,
        );
        expect(
          updated.runs.first.gateResults
              .singleWhere((result) => result.gateId == 'no_tool_errors')
              .status,
          TaskGateStatus.passed,
        );
        expect(File(path.join(root.path, 'version.txt')).existsSync(), isFalse);
      },
    );

    test(
      'read-only task-level command gate exposes required command',
      () async {
        workspace = workspace.copyWith(commandExecutionApproved: true);
        final task = _task(
          gates: const [
            TaskGate(
              id: 'command_passes',
              scope: 'task',
              params: {'command': 'dart --version', 'working_directory': '.'},
            ),
          ],
          step: const TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Verify toolchain',
            instructions: ['Run dart --version.'],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.pending,
          ),
        );
        final client = _QueueCompletionClient([
          ChatCompletionResponse(
            content: '',
            toolCalls: [
              ChatCompletionToolCall(
                name: 'run_command',
                arguments: jsonEncode({'command': 'dart --version'}),
              ),
            ],
          ),
          ChatCompletionResponse(
            content: jsonEncode({
              'status': 'completed',
              'summary': 'Verified dart.',
              'memoryUpdate': 'dart is available.',
            }),
          ),
        ]);

        final updated = await service.runNextStep(
          client: client,
          workspace: workspace,
          snapshot: task,
          baseSystemPrompt: 'system',
        );

        expect(client.seenToolNames.first, contains('run_command'));
        expect(updated.status, TaskStatus.completed);
        expect(
          updated.runs.single.gateResults.single.status,
          TaskGateStatus.passed,
        );
      },
    );

    test('mutating steps expose approved terminal state to executor', () async {
      workspace = workspace.copyWith(commandExecutionApproved: true);
      final task = _task(
        step: const TaskStep(
          id: 'inspect_binary',
          title: 'Inspect binary document',
          objective: 'Extract readable text from a binary document.',
          instructions: ['Use terminal extraction if needed.'],
          mayEditFiles: true,
          artifacts: [],
          status: TaskStepStatus.pending,
        ),
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Inspected the document.',
            'memoryUpdate': 'Document text was available.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      final executorPrompt = client.seenMessages.single.last.content;
      expect(client.seenToolNames.single, contains('run_command'));
      expect(executorPrompt, contains('Terminal commands are enabled'));
      expect(executorPrompt, contains('Tools exposed to this step'));
      expect(executorPrompt, contains('run_command'));
      expect(updated.status, TaskStatus.completed);
    });

    test('read-only steps can create new task artifacts', () async {
      final task = _task(
        step: const TaskStep(
          id: 'step_1',
          title: 'Step 1',
          objective: 'Write a report artifact',
          instructions: ['Write report'],
          mayEditFiles: false,
          artifacts: [
            TaskArtifact(
              path: '.agent/tasks/task_test/report.md',
              description: 'Report',
            ),
          ],
          status: TaskStepStatus.pending,
        ),
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'write_file',
              arguments: jsonEncode({
                'path': '.agent/tasks/task_test/report.md',
                'content': '# Report\n',
              }),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Report written.',
            'memoryUpdate': 'Created the report artifact.',
            'artifacts': [
              {
                'path': '.agent/tasks/task_test/report.md',
                'description': 'Report',
              },
            ],
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      final report = File(
        path.join(root.path, '.agent', 'tasks', 'task_test', 'report.md'),
      );
      expect(report.existsSync(), isTrue);
      expect(report.readAsStringSync(), '# Report\n');
      expect(updated.runs.single.toolCalls.single.error, isNull);
      expect(updated.status, TaskStatus.completed);
    });

    test('read-only steps reject future step artifact writes', () async {
      final task = _task(
        steps: const [
          TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Write overview',
            instructions: ['Write overview'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/overview.md'),
            ],
            status: TaskStepStatus.pending,
          ),
          TaskStep(
            id: 'step_2',
            title: 'Step 2',
            objective: 'Write final report',
            instructions: ['Write final report'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/final_report.md'),
            ],
            status: TaskStepStatus.pending,
          ),
        ],
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'write_file',
              arguments: jsonEncode({
                'path': '.agent/tasks/task_test/final_report.md',
                'content': '# Final\n',
              }),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Stayed on current step.',
            'memoryUpdate': 'No future artifacts were written.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(
        File(
          path.join(
            root.path,
            '.agent',
            'tasks',
            'task_test',
            'final_report.md',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        updated.runs.single.toolCalls.single.error,
        contains('current step'),
      );
      expect(updated.runs.single.artifacts, isEmpty);
      expect(updated.status, TaskStatus.paused);
      expect(updated.currentStepId, 'step_2');
    });

    test('mutating steps reject future step artifact writes', () async {
      final task = _task(
        steps: const [
          TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Edit files',
            instructions: ['Edit files'],
            mayEditFiles: true,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/edit_summary.md'),
            ],
            status: TaskStepStatus.pending,
          ),
          TaskStep(
            id: 'step_2',
            title: 'Step 2',
            objective: 'Write final report',
            instructions: ['Write final report'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/final_report.md'),
            ],
            status: TaskStepStatus.pending,
          ),
        ],
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'write_file',
              arguments: jsonEncode({
                'path': '.agent/tasks/task_test/final_report.md',
                'content': '# Final\n',
              }),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Did not write a future artifact.',
            'memoryUpdate': 'Future artifact write was rejected.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(
        File(
          path.join(
            root.path,
            '.agent',
            'tasks',
            'task_test',
            'final_report.md',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        updated.runs.single.toolCalls.single.error,
        contains('current step'),
      );
      expect(updated.status, TaskStatus.paused);
      expect(updated.currentStepId, 'step_2');
    });

    test('step output filters artifacts to the current step', () async {
      final task = _task(
        steps: const [
          TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Write overview',
            instructions: ['Write overview'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/overview.md'),
            ],
            status: TaskStepStatus.pending,
          ),
          TaskStep(
            id: 'step_2',
            title: 'Step 2',
            objective: 'Write final report',
            instructions: ['Write final report'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/final_report.md'),
            ],
            status: TaskStepStatus.pending,
          ),
        ],
      );
      final client = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'Overview complete.',
          'memoryUpdate': 'Created overview only.',
          'artifacts': [
            {'path': '.agent/tasks/task_test/overview.md'},
            {'path': '.agent/tasks/task_test/final_report.md'},
          ],
        }),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(updated.runs.single.artifacts, hasLength(1));
      expect(
        updated.runs.single.artifacts.single.path,
        contains('overview.md'),
      );
      expect(updated.steps.first.artifacts, hasLength(1));
      expect(
        updated.steps.first.artifacts.single.path,
        contains('overview.md'),
      );
      expect(
        updated.steps.last.artifacts.single.path,
        contains('final_report'),
      );
    });

    test('later steps can read artifacts from earlier steps', () async {
      final artifact = File(
        path.join(root.path, '.agent', 'tasks', 'task_test', 'overview.md'),
      );
      await artifact.create(recursive: true);
      await artifact.writeAsString('Prior analysis');

      final task = _task(
        steps: const [
          TaskStep(
            id: 'step_1',
            title: 'Step 1',
            objective: 'Write overview',
            instructions: ['Write overview'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/overview.md'),
            ],
            status: TaskStepStatus.completed,
          ),
          TaskStep(
            id: 'step_2',
            title: 'Step 2',
            objective: 'Use overview',
            instructions: ['Read overview'],
            mayEditFiles: false,
            artifacts: [
              TaskArtifact(path: '.agent/tasks/task_test/final_report.md'),
            ],
            status: TaskStepStatus.pending,
          ),
        ],
        currentStepId: 'step_2',
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'read_file',
              arguments: jsonEncode({
                'path': '.agent/tasks/task_test/overview.md',
              }),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Read prior artifact.',
            'memoryUpdate': 'Used prior analysis.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(updated.runs.single.toolCalls.single.error, isNull);
      expect(
        updated.runs.single.toolCalls.single.resultSummary,
        contains('Prior analysis'),
      );
      expect(updated.status, TaskStatus.completed);
    });

    test('planned artifacts are not marked produced when omitted', () async {
      final task = _task(
        step: const TaskStep(
          id: 'step_1',
          title: 'Step 1',
          objective: 'Write report',
          instructions: ['Write report'],
          mayEditFiles: false,
          artifacts: [TaskArtifact(path: '.agent/tasks/task_test/report.md')],
          status: TaskStepStatus.pending,
        ),
      );
      final client = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'No artifact was produced.',
          'memoryUpdate': 'Finished without writing report.',
        }),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(updated.runs.single.artifacts, isEmpty);
      expect(updated.steps.single.artifacts.single.path, contains('report.md'));
    });

    test('compacts long step executor context before continuing', () async {
      final largeFile = File(path.join(root.path, 'large.txt'));
      await largeFile.writeAsString(List.filled(1200, 'old context').join(' '));

      final task = _task();
      final statuses = <String>[];
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'read_file',
              arguments: jsonEncode({'path': 'large.txt'}),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'read_file',
              arguments: jsonEncode({'path': 'missing_2.txt'}),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'read_file',
              arguments: jsonEncode({'path': 'missing_3.txt'}),
            ),
          ],
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'schema_version': 1,
            'task': 'Continue the task step.',
            'current_state': 'A large file was inspected earlier.',
          }),
        ),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Finished after compacting older context.',
            'memoryUpdate': 'Large file context was summarized.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
        compactionSettings: const CompactionSettings(
          triggerThreshold: 0.60,
          hardLimitThreshold: 0.95,
          recentWindowUnits: 2,
        ),
        contextLimitTokens: 256,
        onCompactionStatus: statuses.add,
      );

      final finalRequest = jsonEncode(
        client.seenMessages.last.map(ModelJson.encode).toList(),
      );

      expect(updated.status, TaskStatus.completed);
      expect(client.requestCount, 5);
      expect(
        statuses.any((status) => status.contains('Compacting context')),
        isTrue,
      );
      expect(finalRequest, contains('Context Summary'));
      expect(finalRequest, contains('missing_2.txt'));
      expect(finalRequest, contains('missing_3.txt'));
      expect(finalRequest, isNot(contains('old context old context')));
    });

    test('finalizes instead of looping on repeated tool calls', () async {
      final task = _task();
      final repeatedCall = ChatCompletionToolCall(
        name: 'read_file',
        arguments: jsonEncode({'path': 'missing.txt'}),
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(content: '', toolCalls: [repeatedCall]),
        ChatCompletionResponse(content: '', toolCalls: [repeatedCall]),
        ChatCompletionResponse(content: '', toolCalls: [repeatedCall]),
        ChatCompletionResponse(
          content: jsonEncode({
            'status': 'completed',
            'summary': 'Stopped repeating and finalized.',
            'memoryUpdate': 'Loop guard fired.',
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: task,
        baseSystemPrompt: 'system',
      );

      expect(client.requestCount, 4);
      expect(updated.status, TaskStatus.completed);
      expect(updated.runs.single.status, TaskRunStatus.completed);
      expect(updated.runs.single.summary, 'Stopped repeating and finalized.');
      expect(updated.runs.single.toolCalls, hasLength(3));
      expect(updated.runs.single.toolCalls.last.error, contains('skipped'));
    });

    test(
      'pauses and preserves a step after transport retry is exhausted',
      () async {
        final updated = await service.runNextStep(
          client: _TransportFailureClient(),
          workspace: workspace,
          snapshot: _task(),
          baseSystemPrompt: 'system',
        );

        expect(updated.status, TaskStatus.paused);
        expect(updated.currentStep?.status, TaskStepStatus.pending);
        expect(updated.runs.single.status, TaskRunStatus.failed);
        expect(updated.runs.single.error, contains('Model transport failed'));
        expect(updated.runs.single.summary, contains('Resume the task'));
      },
    );
  });
}

TaskDocument _task({
  TaskStep? step,
  List<TaskStep>? steps,
  String? currentStepId,
  List<TaskGate> gates = const [],
}) {
  final now = DateTime(2026, 1, 1);
  final resolvedSteps = steps ?? [step ?? _step()];
  return TaskDocument(
    id: 'task_test',
    title: 'Test task',
    originalPrompt: 'Run the task',
    goal: 'Run the task',
    constraints: const ['Stay inside workspace.'],
    successCriteria: const ['Finish the task.'],
    gates: gates,
    steps: resolvedSteps,
    status: TaskStatus.paused,
    currentStepId: currentStepId ?? resolvedSteps.first.id,
    memorySummary: '',
    runs: const [],
    createdAt: now,
    updatedAt: now,
  );
}

TaskStep _step() {
  return const TaskStep(
    id: 'step_1',
    title: 'Step 1',
    objective: 'Do the work',
    instructions: ['Work carefully'],
    mayEditFiles: false,
    artifacts: [],
    status: TaskStepStatus.pending,
  );
}

Map<String, dynamic> _planJson({required String title}) {
  return {
    'title': title,
    'goal': 'Build the reporting screen',
    'constraints': ['Stay inside workspace.'],
    'successCriteria': ['The reporting screen is planned.'],
    'steps': [
      {
        'id': 'inspect',
        'title': 'Inspect',
        'objective': 'Inspect the existing app.',
        'instructions': ['Read relevant files.'],
        'mayEditFiles': false,
      },
      {
        'id': 'implement',
        'title': 'Implement',
        'objective': 'Implement the screen.',
        'instructions': ['Patch the UI.'],
        'mayEditFiles': true,
      },
    ],
  };
}

Map<String, dynamic> _projectBoundedPlanJson({required String title}) {
  return {
    'title': title,
    'goal': 'Implement the settings toggle',
    'constraints': ['Do not build the whole app.'],
    'successCriteria': ['The settings toggle works.'],
    'steps': [
      {
        'id': 'implement_toggle',
        'title': 'Implement toggle',
        'objective': 'Implement the settings toggle.',
        'instructions': ['Make only the bounded change.'],
        'mayEditFiles': true,
      },
    ],
  };
}

Map<String, dynamic> _wholeProjectPlanJson() {
  return {
    'title': 'Whole app',
    'goal': 'Build the whole app',
    'constraints': ['Stay inside workspace.'],
    'successCriteria': ['The whole app is complete.'],
    'steps': [
      for (var i = 1; i <= 4; i++)
        {
          'id': 'step_$i',
          'title': 'Whole project step $i',
          'objective': 'Complete the project end-to-end.',
          'instructions': ['Do everything.'],
          'mayEditFiles': true,
        },
    ],
  };
}

class _QueueChatClient extends ChatClient {
  _QueueChatClient(this._responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<String> _responses;
  final List<List<ChatMessage>> seenMessages = [];
  var _index = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
  }) async {
    seenMessages.add(List<ChatMessage>.of(messages));
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

  int get requestCount => _index;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
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

class _TransportFailureClient extends ChatClient {
  _TransportFailureClient() : super(baseUrl: 'http://localhost', model: 'test');

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
  }) {
    throw _transportFailure();
  }

  @override
  void dispose() {}
}

ChatTransportException _transportFailure() => ChatTransportException(
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
