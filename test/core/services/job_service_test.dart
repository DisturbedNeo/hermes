import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('JobService linear runner', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late JobService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_service_');
      workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      service = JobService(toolService: ToolService());
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('creates a persisted paused multi-step job', () async {
      final client = _QueueChatClient([
        jsonEncode(_planJson(title: 'Planned task')),
      ]);

      final job = await service.createJob(
        client: client,
        workspace: workspace,
        userPrompt: 'Build the reporting screen',
        selectedMode: ExecutionMode.plan,
        baseSystemPrompt: 'system',
        chatSessionId: 'chat_1',
      );

      expect(job.title, 'Planned task');
      expect(job.status, JobStatus.paused);
      expect(job.currentStepId, 'inspect');
      expect(job.steps, hasLength(2));
      expect(
        File(
          path.join(root.path, '.agent', 'jobs', job.id, 'job.json'),
        ).existsSync(),
        isTrue,
      );
    });

    test('runs one step and records structured memory and history', () async {
      final job = _job();
      await service.storage.saveSnapshot(root.path, job);
      final client = _QueueChatClient([
        jsonEncode({
          'status': 'completed',
          'summary': 'Inspected the workspace.',
          'memoryUpdate': 'Found a Flutter app.',
          'artifacts': [
            {'path': '.agent/jobs/job_test/notes.md'},
          ],
        }),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: job,
        baseSystemPrompt: 'system',
      );

      expect(updated.status, JobStatus.completed);
      expect(updated.steps.single.status, JobStepStatus.completed);
      expect(updated.runs.single.status, JobRunStatus.completed);
      expect(updated.memorySummary, contains('Found a Flutter app.'));
      expect(updated.runs.single.artifacts.single.path, contains('notes.md'));
    });

    test('pauses for phase approval before mutating steps', () async {
      final job = _job(
        step: const JobStep(
          id: 'edit',
          title: 'Edit files',
          objective: 'Edit files',
          instructions: ['Patch files'],
          mayEditFiles: true,
          artifacts: [],
          status: JobStepStatus.pending,
        ),
      );

      final blocked = await service.runNextStep(
        client: _QueueChatClient([
          jsonEncode({'status': 'completed'}),
        ]),
        workspace: workspace,
        snapshot: job,
        baseSystemPrompt: 'system',
        requirePhaseApproval: true,
      );

      expect(blocked.status, JobStatus.blocked);
      expect(blocked.pendingApproval?.stepId, 'edit');
      expect(blocked.steps.single.status, JobStepStatus.blocked);

      final approved = await service.approvePendingStep(
        workspace: workspace,
        snapshot: blocked,
      );

      expect(approved.status, JobStatus.paused);
      expect(approved.pendingApproval, isNull);
      expect(approved.steps.single.status, JobStepStatus.approved);
    });

    test('records blocked user questions and resumes after answer', () async {
      final job = _job();
      final blocked = await service.runNextStep(
        client: _QueueChatClient([
          jsonEncode({
            'status': 'blocked',
            'summary': 'Need a target platform.',
            'userQuestion': 'Which platform should this target?',
          }),
        ]),
        workspace: workspace,
        snapshot: job,
        baseSystemPrompt: 'system',
      );

      expect(blocked.status, JobStatus.blocked);
      expect(blocked.pendingQuestion?.question, contains('platform'));

      final answered = await service.answerOpenQuestion(
        workspace: workspace,
        snapshot: blocked,
        answer: 'Desktop first.',
      );

      expect(answered.status, JobStatus.paused);
      expect(answered.pendingQuestion, isNull);
      expect(answered.steps.single.status, JobStepStatus.pending);
      expect(answered.memorySummary, contains('Desktop first.'));
    });

    test('automatically replans unfinished work when requested', () async {
      final job = _job(
        steps: const [
          JobStep(
            id: 'done',
            title: 'Done',
            objective: 'Already done',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: JobStepStatus.completed,
          ),
          JobStep(
            id: 'next',
            title: 'Next',
            objective: 'Next work',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: JobStepStatus.pending,
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
        snapshot: job,
        baseSystemPrompt: 'system',
      );

      expect(updated.steps.map((step) => step.id), ['done', 'verify']);
      expect(updated.currentStepId, 'verify');
      expect(updated.runs.map((run) => run.status), [
        JobRunStatus.needsReplan,
        JobRunStatus.replanned,
      ]);
      expect(updated.memorySummary, contains('Add a verification step.'));
    });

    test('read-only steps reject writes outside the job folder', () async {
      final job = _job();
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
        snapshot: job,
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
        contains('job-owned artifact'),
      );
      expect(updated.status, JobStatus.completed);
    });

    test('read-only steps can create new job artifacts', () async {
      final job = _job(
        step: const JobStep(
          id: 'step_1',
          title: 'Step 1',
          objective: 'Write a report artifact',
          instructions: ['Write report'],
          mayEditFiles: false,
          artifacts: [
            JobArtifact(
              path: '.agent/jobs/job_test/report.md',
              description: 'Report',
            ),
          ],
          status: JobStepStatus.pending,
        ),
      );
      final client = _QueueCompletionClient([
        ChatCompletionResponse(
          content: '',
          toolCalls: [
            ChatCompletionToolCall(
              name: 'write_file',
              arguments: jsonEncode({
                'path': '.agent/jobs/job_test/report.md',
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
                'path': '.agent/jobs/job_test/report.md',
                'description': 'Report',
              },
            ],
          }),
        ),
      ]);

      final updated = await service.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: job,
        baseSystemPrompt: 'system',
      );

      final report = File(
        path.join(root.path, '.agent', 'jobs', 'job_test', 'report.md'),
      );
      expect(report.existsSync(), isTrue);
      expect(report.readAsStringSync(), '# Report\n');
      expect(updated.runs.single.toolCalls.single.error, isNull);
      expect(updated.status, JobStatus.completed);
    });

    test('finalizes instead of looping on repeated tool calls', () async {
      final job = _job();
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
        snapshot: job,
        baseSystemPrompt: 'system',
      );

      expect(client.requestCount, 4);
      expect(updated.status, JobStatus.completed);
      expect(updated.runs.single.status, JobRunStatus.completed);
      expect(updated.runs.single.summary, 'Stopped repeating and finalized.');
      expect(updated.runs.single.toolCalls, hasLength(3));
      expect(updated.runs.single.toolCalls.last.error, contains('skipped'));
    });
  });
}

JobDocument _job({JobStep? step, List<JobStep>? steps, String? currentStepId}) {
  final now = DateTime(2026, 1, 1);
  final resolvedSteps = steps ?? [step ?? _step()];
  return JobDocument(
    id: 'job_test',
    title: 'Test job',
    originalPrompt: 'Run the job',
    goal: 'Run the job',
    constraints: const ['Stay inside workspace.'],
    successCriteria: const ['Finish the job.'],
    steps: resolvedSteps,
    status: JobStatus.paused,
    currentStepId: currentStepId ?? resolvedSteps.first.id,
    memorySummary: '',
    runs: const [],
    createdAt: now,
    updatedAt: now,
  );
}

JobStep _step() {
  return const JobStep(
    id: 'step_1',
    title: 'Step 1',
    objective: 'Do the work',
    instructions: ['Work carefully'],
    mayEditFiles: false,
    artifacts: [],
    status: JobStepStatus.pending,
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
  var _index = 0;

  int get requestCount => _index;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
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
