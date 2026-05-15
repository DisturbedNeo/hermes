import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/job_system/job_phase_validator.dart';
import 'package:hermes/core/services/job_system/job_service.dart';
import 'package:hermes/core/services/job_system/job_storage_service.dart';
import 'package:hermes/core/services/job_system/job_template_registry.dart';
import 'package:hermes/core/services/prompt_library_seed_data.dart';
import 'package:hermes/core/services/tool_service.dart';

void main() {
  group('JobService lifecycle controls', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_service_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('blocks execution while required questions are open', () async {
      final snapshot = _snapshot(
        openQuestions: const [
          OpenQuestion(
            id: 'q1',
            question: 'May files be modified?',
            required: true,
            status: OpenQuestionStatus.open,
          ),
        ],
      );
      final client = ChatClient(baseUrl: 'http://127.0.0.1:1', model: 'none');
      addTearDown(client.dispose);

      final updated = await service.runNextPhase(
        client: client,
        workspace: workspace,
        snapshot: snapshot,
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      expect(updated.state.phaseRuns, isEmpty);
      expect(updated.state.latestSummary, contains('required question'));
    });

    test('answers a required question and unblocks the job', () async {
      final snapshot = _snapshot(
        status: JobStatus.blocked,
        openQuestions: const [
          OpenQuestion(
            id: 'q1',
            question: 'May files be modified?',
            required: true,
            status: OpenQuestionStatus.open,
          ),
        ],
      );

      final updated = await service.answerOpenQuestion(
        workspace: workspace,
        snapshot: snapshot,
        questionId: 'q1',
        answer: 'Only modify files under lib.',
      );

      expect(updated.state.status, JobStatus.paused);
      expect(
        updated.state.openQuestions.single.status,
        OpenQuestionStatus.answered,
      );
      expect(
        updated.state.openQuestions.single.answer,
        'Only modify files under lib.',
      );
    });

    test('dismisses optional questions using default assumptions', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(
        now,
        clarifyingQuestions: const [
          ClarifyingQuestion(
            id: 'q_optional',
            question: 'Include performance issues?',
            required: false,
            defaultAssumption: 'Include only high-impact performance issues.',
          ),
        ],
      );
      final snapshot = JobSnapshot(
        taskBrief: brief,
        spec: _spec(now: now, brief: brief, phases: [_phase()]),
        state: JobState(
          jobId: 'job_test',
          status: JobStatus.planned,
          currentPhaseId: 'phase_1',
          updatedAt: now,
          completedPhases: const [],
          failedPhases: const [],
          skippedPhases: const [],
          artifacts: const [],
          openQuestions: const [
            OpenQuestion(
              id: 'q_optional',
              question: 'Include performance issues?',
              required: false,
              status: OpenQuestionStatus.open,
            ),
          ],
          assumptions: const [],
          risks: const [],
          phaseRuns: const [],
          latestSummary: 'Planned',
        ),
      );

      final updated = await service.dismissOptionalQuestions(
        workspace: workspace,
        snapshot: snapshot,
      );

      expect(updated.state.status, JobStatus.planned);
      expect(
        updated.state.openQuestions.single.status,
        OpenQuestionStatus.dismissed,
      );
      expect(
        updated.state.assumptions,
        contains('Include only high-impact performance issues.'),
      );
    });

    test('retry queues the current blocked phase', () async {
      final snapshot = _snapshot(
        status: JobStatus.blocked,
        phaseStatus: PhaseStatus.blocked,
      );

      final updated = await service.retryCurrentPhase(
        workspace: workspace,
        snapshot: snapshot,
      );

      expect(updated.state.status, JobStatus.paused);
      expect(updated.spec.phases.single.status, PhaseStatus.pending);
    });

    test(
      'skip marks the current phase skipped and completes a one-phase job',
      () async {
        final snapshot = _snapshot(
          status: JobStatus.blocked,
          phaseStatus: PhaseStatus.blocked,
        );

        final updated = await service.skipCurrentPhase(
          workspace: workspace,
          snapshot: snapshot,
        );

        expect(updated.state.status, JobStatus.completed);
        expect(updated.spec.phases.single.status, PhaseStatus.skipped);
        expect(updated.state.skippedPhases, ['phase_1']);
      },
    );

    test('pauseAtCheckpoint records the checkpoint phase', () async {
      final snapshot = _snapshot();
      final phase = snapshot.spec.phases.single;

      final updated = await service.pauseAtCheckpoint(
        workspace: workspace,
        snapshot: snapshot,
        phase: phase,
      );

      expect(updated.state.status, JobStatus.paused);
      expect(updated.state.currentPhaseId, phase.id);
      expect(updated.state.latestSummary, contains('Paused at checkpoint'));
    });
  });

  group('JobService terminal policy', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_terminal_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(
        root.path,
        commandExecutionApproved: true,
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('rejects mutating terminal commands before the tool runs', () async {
      final target = File('${root.path}/victim.txt')
        ..writeAsStringSync('keep me');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': requests == 1
                      ? {
                          'content': '',
                          'tool_calls': [
                            {
                              'id': 'call_1',
                              'type': 'function',
                              'function': {
                                'name': 'run_command',
                                'arguments': {
                                  'command': 'rm',
                                  'args': ['victim.txt'],
                                },
                              },
                            },
                          ],
                        }
                      : {'content': 'I could not run the command.'},
                },
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final client = ChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test-model',
      );
      addTearDown(client.dispose);

      final updated = await service.runNextPhase(
        client: client,
        workspace: workspace,
        snapshot: _terminalSnapshot(),
        baseSystemPrompt: 'System',
      );

      expect(target.existsSync(), isTrue);
      expect(updated.state.status, JobStatus.blocked);
      expect(
        updated.state.phaseRuns.single.toolCalls.single.error,
        contains('Readonly phase rejected mutating_workspace terminal command'),
      );
    });

    test('detects unreported readonly terminal workspace mutations', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': requests == 1
                      ? {
                          'content': '',
                          'tool_calls': [
                            {
                              'id': 'call_1',
                              'type': 'function',
                              'function': {
                                'name': 'run_command',
                                'arguments': {
                                  'command': 'bash',
                                  'args': [
                                    '-lc',
                                    'printf changed | dd of=sneaky.txt status=none',
                                  ],
                                },
                              },
                            },
                          ],
                        }
                      : {'content': 'Final output.'},
                },
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final client = ChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test-model',
      );
      addTearDown(client.dispose);

      final updated = await service.runNextPhase(
        client: client,
        workspace: workspace,
        snapshot: _terminalSnapshot(),
        baseSystemPrompt: 'System',
      );

      expect(File('${root.path}/sneaky.txt').existsSync(), isTrue);
      expect(updated.state.status, JobStatus.blocked);
      expect(
        updated.state.phaseRuns.single.filesPatched,
        contains('sneaky.txt'),
      );
      final review = updated.state.phaseRuns.single.reviewResult!;
      expect(
        review.deterministicChecks
            .singleWhere((check) => check.id == 'no_unexpected_source_mutation')
            .passed,
        isFalse,
      );
    });

    test(
      'applies job-level readonly terminal policy to mutating phases',
      () async {
        final target = File('${root.path}/victim.txt')
          ..writeAsStringSync('keep me');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        final subscription = server.listen((request) async {
          requests++;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': requests == 1
                        ? {
                            'content': '',
                            'tool_calls': [
                              {
                                'id': 'call_1',
                                'type': 'function',
                                'function': {
                                  'name': 'run_command',
                                  'arguments': {
                                    'command': 'rm',
                                    'args': ['victim.txt'],
                                  },
                                },
                              },
                            ],
                          }
                        : {'content': 'Final output.'},
                  },
                ],
              }),
            );
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });
        final client = ChatClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          model: 'test-model',
        );
        addTearDown(client.dispose);
        final now = DateTime(2026, 1, 1);
        final brief = _brief(now);
        final snapshot = JobSnapshot(
          taskBrief: brief,
          spec: _spec(
            now: now,
            brief: brief,
            phases: [
              _phase(
                terminalPolicy: TerminalPolicy.workspaceMutating,
                allowedTools: const ['run_command'],
                review: const ReviewPolicy(
                  required: true,
                  reviewer: ReviewerType.deterministic,
                ),
                retryPolicy: null,
              ),
            ],
            toolPolicy: const ToolPolicy(
              defaultAllowed: ['run_command'],
              terminal: TerminalToolPolicy(
                allowed: true,
                policy: TerminalPolicy.readonly,
              ),
            ),
          ),
          state: JobState(
            jobId: 'job_test',
            status: JobStatus.planned,
            updatedAt: now,
            completedPhases: const [],
            failedPhases: const [],
            skippedPhases: const [],
            artifacts: const [],
            openQuestions: const [],
            assumptions: const [],
            risks: const [],
            phaseRuns: const [],
            latestSummary: 'Planned',
          ),
        );

        final updated = await service.runNextPhase(
          client: client,
          workspace: workspace,
          snapshot: snapshot,
          baseSystemPrompt: 'System',
        );

        expect(target.existsSync(), isTrue);
        expect(updated.state.status, JobStatus.blocked);
        expect(
          updated.state.phaseRuns.single.toolCalls.single.error,
          contains(
            'Readonly phase rejected mutating_workspace terminal command',
          ),
        );
      },
    );

    test('turns ask_user model review into a required open question', () async {
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        requestCount++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': requestCount == 1
                        ? 'Phase output that needs a user decision.'
                        : jsonEncode({
                            'passed': false,
                            'confidence': 'medium',
                            'summary': 'A user decision is needed.',
                            'criteriaResults': [
                              {
                                'criterion': 'User decision',
                                'passed': false,
                                'comment': 'The phase cannot continue safely.',
                              },
                            ],
                            'issues': [
                              {
                                'severity': 'blocking',
                                'message': 'Scope is unclear.',
                                'suggestedAction':
                                    'Should this phase modify source files?',
                              },
                            ],
                            'recommendation': 'ask_user',
                          }),
                  },
                },
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final client = ChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test-model',
      );
      addTearDown(client.dispose);

      final phase = _phase(
        id: 'decision_phase',
        title: 'Decision phase',
        review: const ReviewPolicy(
          required: true,
          reviewer: ReviewerType.model,
        ),
        retryPolicy: null,
      );

      final updated = await service.runNextPhase(
        client: client,
        workspace: workspace,
        snapshot: _snapshot(phase: phase),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      expect(updated.spec.phases.single.status, PhaseStatus.blocked);
      expect(updated.state.phaseRuns.single.status, PhaseRunStatus.blocked);
      expect(updated.state.openQuestions, hasLength(1));
      final question = updated.state.openQuestions.single;
      expect(question.phaseId, 'decision_phase');
      expect(question.required, isTrue);
      expect(question.status, OpenQuestionStatus.open);
      expect(question.question, 'Should this phase modify source files?');
      expect(question.reason, contains('A user decision is needed.'));
      expect(updated.state.latestSummary, contains('requested user input'));
    });
  });

  group('JobService tool policy', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_tools_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('does not expose globally disallowed phase tools', () async {
      final exposedTools = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final body = jsonDecode(
          await request.cast<List<int>>().transform(utf8.decoder).join(),
        );
        final tools = body['tools'];
        if (tools is List) {
          exposedTools.addAll(
            tools
                .whereType<Map>()
                .map((tool) => tool['function'])
                .whereType<Map>()
                .map((function) => function['name']?.toString())
                .whereType<String>(),
          );
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Final output.'},
                },
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final client = ChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test-model',
      );
      addTearDown(client.dispose);
      final now = DateTime(2026, 1, 1);
      final brief = _brief(now);
      final snapshot = JobSnapshot(
        taskBrief: brief,
        spec: _spec(
          now: now,
          brief: brief,
          phases: [
            _phase(
              allowedTools: const ['read_file', 'write_file'],
              review: const ReviewPolicy(
                required: true,
                reviewer: ReviewerType.deterministic,
              ),
              retryPolicy: null,
            ),
          ],
          toolPolicy: const ToolPolicy(
            defaultAllowed: ['read_file', 'write_file'],
            defaultDisallowed: ['write_file'],
          ),
        ),
        state: JobState(
          jobId: 'job_test',
          status: JobStatus.planned,
          updatedAt: now,
          completedPhases: const [],
          failedPhases: const [],
          skippedPhases: const [],
          artifacts: const [],
          openQuestions: const [],
          assumptions: const [],
          risks: const [],
          phaseRuns: const [],
          latestSummary: 'Planned',
        ),
      );

      final updated = await service.runNextPhase(
        client: client,
        workspace: workspace,
        snapshot: snapshot,
        baseSystemPrompt: 'System',
      );

      expect(exposedTools, contains('read_file'));
      expect(exposedTools, isNot(contains('write_file')));
      expect(updated.state.status, JobStatus.completed);
    });
  });

  group('JobService spec validation', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_validation_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('rejects edited job specs with unsafe artifact paths', () async {
      final snapshot = _snapshot();
      final edited = snapshot.spec.copyWith(
        phases: [
          _phase(
            expectedOutputs: const [
              PhaseOutput(path: '../escape.md', required: true),
            ],
          ),
        ],
      );

      expect(
        service.updateJobSpec(
          workspace: workspace,
          snapshot: snapshot,
          rawJson: jsonEncode(edited.toJson()),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('output path is unsafe'),
          ),
        ),
      );
    });

    test('repairs invalid planner output before saving a new job', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(now);
      final invalidSpec = _spec(
        now: now,
        brief: brief,
        phases: [
          _phase(
            expectedOutputs: const [
              PhaseOutput(path: '../escape.md', required: true),
            ],
          ),
        ],
      );
      final repairedSpec = _spec(
        now: now,
        brief: brief,
        phases: [
          _phase(
            expectedOutputs: const [
              PhaseOutput(path: 'output.md', required: true),
            ],
          ),
        ],
      );
      final server = await _completionServer([
        {'content': jsonEncode(brief.toJson())},
        {'content': jsonEncode(invalidSpec.toJson())},
        {'content': jsonEncode(repairedSpec.toJson())},
      ]);
      addTearDown(server.close);

      final snapshot = await service.createJob(
        client: server.client,
        workspace: workspace,
        userPrompt: 'Make a validated job',
        selectedMode: ExecutionMode.job,
        baseSystemPrompt: 'System',
      );

      expect(
        snapshot.spec.phases.single.expectedOutputs.single.path,
        'output.md',
      );
      expect(snapshot.state.status, JobStatus.planned);
    });

    test('applies configured max phase retries to new jobs', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(now);
      final plannedSpec = _spec(
        now: now,
        brief: brief,
        stopPolicy: const StopPolicy(maxPhaseRetries: 1),
        phases: [
          _phase(
            retryPolicy: const RetryPolicy(
              maxRetries: 1,
              retryOnReviewFailure: false,
              retryOnMissingOutput: true,
            ),
          ),
        ],
      );
      final server = await _completionServer([
        {'content': jsonEncode(brief.toJson())},
        {'content': jsonEncode(plannedSpec.toJson())},
      ]);
      addTearDown(server.close);

      final snapshot = await service.createJob(
        client: server.client,
        workspace: workspace,
        userPrompt: 'Make a job with configured retries',
        selectedMode: ExecutionMode.job,
        baseSystemPrompt: 'System',
        maxPhaseRetries: 3,
      );

      expect(snapshot.spec.stopPolicy.maxPhaseRetries, 3);
      expect(snapshot.spec.phases.single.retryPolicy!.maxRetries, 3);
      expect(
        snapshot.spec.phases.single.retryPolicy!.retryOnReviewFailure,
        isFalse,
      );
    });

    test(
      'falls back to the codebase audit template through the registry',
      () async {
        final now = DateTime(2026, 1, 1);
        final brief = _brief(now).copyWith(
          originalPrompt: 'Analyse this codebase and find major issues.',
          objective:
              'Analyse this codebase for reliability, security, and maintainability issues.',
          domain: JobDomain.development,
        );
        final server = await _completionServer([
          {'content': jsonEncode(brief.toJson())},
          {'content': 'not json'},
          {'content': 'still not json'},
        ]);
        addTearDown(server.close);

        final snapshot = await service.createJob(
          client: server.client,
          workspace: workspace,
          userPrompt: 'Analyse this codebase and find major issues.',
          selectedMode: ExecutionMode.job,
          baseSystemPrompt: 'System',
        );

        expect(snapshot.spec.phases.map((phase) => phase.id), [
          'repo_map',
          'risk_scan',
          'final_report',
        ]);
        expect(
          snapshot.spec.phases.first.expectedOutputs.single.path,
          '.agent/jobs/${snapshot.spec.id}/repo-map.md',
        );
        expect(
          snapshot.spec.globalConstraints,
          contains('Do not modify source files.'),
        );
        expect(
          snapshot.spec.promptModules,
          contains(PromptLibrarySeedIds.codingSecurityReview),
        );
        expect(
          const JobTemplateRegistry().byId(BuiltInJobTemplateIds.codebaseAudit),
          isNotNull,
        );
      },
    );

    test(
      'creates a draft instead of planning when required questions exist',
      () async {
        final now = DateTime(2026, 1, 1);
        final brief = _brief(
          now,
          clarifyingQuestions: const [
            ClarifyingQuestion(
              id: 'q_required',
              question: 'Should files be modified?',
              required: true,
              impactIfUnanswered: 'The plan may choose the wrong tool policy.',
            ),
          ],
        );
        var requestCount = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          requestCount++;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': jsonEncode(brief.toJson())},
                  },
                ],
              }),
            );
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });
        final client = ChatClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          model: 'test-model',
        );
        addTearDown(client.dispose);

        final snapshot = await service.createJob(
          client: client,
          workspace: workspace,
          userPrompt: 'Plan a risky edit',
          selectedMode: ExecutionMode.job,
          baseSystemPrompt: 'System',
        );

        expect(requestCount, 1);
        expect(snapshot.spec.status, JobStatus.draft);
        expect(snapshot.spec.phases, isEmpty);
        expect(snapshot.state.status, JobStatus.blocked);
        expect(snapshot.state.openQuestions.single.id, 'q_required');
      },
    );

    test('plans a saved draft after required questions are answered', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(
        now,
        clarifyingQuestions: const [
          ClarifyingQuestion(
            id: 'q_required',
            question: 'Should files be modified?',
            required: true,
          ),
        ],
      );
      final plannedSpec = _spec(now: now, brief: brief, phases: [_phase()]);
      final server = await _completionServer([
        {'content': jsonEncode(brief.toJson())},
        {'content': jsonEncode(plannedSpec.toJson())},
      ]);
      addTearDown(server.close);

      final draft = await service.createJob(
        client: server.client,
        workspace: workspace,
        userPrompt: 'Plan a risky edit',
        selectedMode: ExecutionMode.job,
        baseSystemPrompt: 'System',
      );
      final answered = await service.answerOpenQuestion(
        workspace: workspace,
        snapshot: draft,
        questionId: 'q_required',
        answer: 'Produce a report only.',
      );
      final planned = await service.planDraftJob(
        client: server.client,
        workspace: workspace,
        snapshot: answered,
        baseSystemPrompt: 'System',
      );

      expect(answered.spec.status, JobStatus.draft);
      expect(answered.state.status, JobStatus.draft);
      expect(planned.spec.status, JobStatus.planned);
      expect(planned.state.status, JobStatus.planned);
      expect(planned.spec.phases.single.id, 'phase_1');
      expect(planned.state.currentPhaseId, 'phase_1');
      expect(planned.taskBrief.clarifyingQuestions.single.answer, isNotNull);
    });
  });

  group('JobService retry feedback', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_retry_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('includes previous review issues in the retry prompt', () async {
      var sawFeedback = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final body = jsonDecode(
          await request.cast<List<int>>().transform(utf8.decoder).join(),
        );
        final messages = body['messages'] as List;
        sawFeedback = messages.any(
          (message) =>
              message is Map &&
              message['content'].toString().contains(
                'The previous attempt failed review',
              ) &&
              message['content'].toString().contains('Missing evidence'),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Final output with evidence.'},
                },
              ],
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final client = ChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test-model',
      );
      addTearDown(client.dispose);

      final updated = await service.runNextPhase(
        client: client,
        workspace: workspace,
        snapshot: _snapshot(
          review: const ReviewPolicy(
            required: true,
            reviewer: ReviewerType.deterministic,
          ),
          phaseRuns: [
            PhaseRun(
              phaseId: 'phase_1',
              runId: 'previous',
              status: PhaseRunStatus.reviewFailed,
              startedAt: DateTime(2026, 1, 1),
              completedAt: DateTime(2026, 1, 1),
              toolCalls: const [],
              filesRead: const [],
              filesWritten: const [],
              filesPatched: const [],
              terminalCommands: const [],
              summary: 'Bad output',
              reviewResult: const ReviewResult(
                phaseId: 'phase_1',
                status: ReviewStatus.failed,
                deterministicChecks: [],
                summary: 'Review failed.',
                issues: [
                  ReviewIssue(severity: 'error', message: 'Missing evidence'),
                ],
                recommendation: ReviewRecommendation.retryPhase,
              ),
            ),
          ],
        ),
        baseSystemPrompt: 'System',
      );

      expect(sawFeedback, isTrue);
      expect(updated.state.status, JobStatus.completed);
      expect(
        File('${root.path}/output.md').readAsStringSync(),
        contains('evidence'),
      );
    });
  });

  group('JobService model reviewers', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_reviewers_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'uses audit evidence review profile for development finding phases',
      () async {
        var requestCount = 0;
        var sawAuditProfile = false;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          requestCount++;
          final body = jsonDecode(
            await request.cast<List<int>>().transform(utf8.decoder).join(),
          );
          if (requestCount == 2) {
            final messages = body['messages'] as List;
            final promptText = messages
                .map((message) => (message as Map)['content'].toString())
                .join('\n');
            sawAuditProfile =
                promptText.contains('AuditEvidenceReview') &&
                promptText.contains('SeverityCalibrationReview') &&
                promptText.contains('Critical severity is used only');
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': requestCount == 1
                          ? '## Findings\n- High: evidence-backed issue.'
                          : jsonEncode({
                              'passed': true,
                              'confidence': 'high',
                              'summary': 'Evidence is calibrated.',
                              'criteriaResults': [
                                {
                                  'criterion': 'Evidence',
                                  'passed': true,
                                  'evidence': 'Finding includes evidence.',
                                },
                              ],
                              'issues': [],
                              'recommendation': 'continue',
                            }),
                    },
                  },
                ],
              }),
            );
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });
        final client = ChatClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          model: 'test-model',
        );
        addTearDown(client.dispose);

        final phase = _phase(
          id: 'risk_scan',
          title: 'Scan findings',
          review: const ReviewPolicy(
            required: true,
            reviewer: ReviewerType.model,
          ),
        );
        final base = _snapshot(phase: phase);
        final brief = base.taskBrief.copyWith(
          domain: JobDomain.development,
          objective: 'Audit this codebase for findings.',
        );
        final snapshot = base.copyWith(
          taskBrief: brief,
          spec: base.spec.copyWith(
            domain: JobDomain.development,
            phases: [phase],
          ),
        );

        final updated = await service.runNextPhase(
          client: client,
          workspace: workspace,
          snapshot: snapshot,
          baseSystemPrompt: 'System',
        );

        expect(sawAuditProfile, isTrue);
        expect(updated.state.status, JobStatus.completed);
        expect(
          updated.state.phaseRuns.single.reviewResult!.modelReview!.summary,
          'Evidence is calibrated.',
        );
      },
    );
  });

  group('JobService inspectability and replanning', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_replan_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('reads workspace artifacts through the sandbox', () async {
      final artifact = File('${root.path}/artifact.md');
      await artifact.writeAsString('Durable output');

      final content = await service.readArtifact(
        workspace: workspace,
        artifactPath: 'artifact.md',
      );

      expect(content, 'Durable output');
      expect(
        service.readArtifact(workspace: workspace, artifactPath: '../escape'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'updates a job spec while preserving completed phase status',
      () async {
        final now = DateTime(2026, 1, 1);
        final brief = _brief(now);
        final snapshot = JobSnapshot(
          taskBrief: brief,
          spec: _spec(
            now: now,
            brief: brief,
            phases: [
              _phase(id: 'completed', status: PhaseStatus.completed),
              _phase(id: 'pending'),
            ],
          ),
          state: JobState(
            jobId: 'job_test',
            status: JobStatus.paused,
            currentPhaseId: 'pending',
            updatedAt: now,
            completedPhases: const ['completed'],
            failedPhases: const [],
            skippedPhases: const [],
            artifacts: const [],
            openQuestions: const [],
            assumptions: const [],
            risks: const [],
            phaseRuns: const [],
            latestSummary: 'Paused',
          ),
        );
        final edited = snapshot.spec.copyWith(
          phases: [
            _phase(id: 'completed', title: 'Completed edited'),
            _phase(id: 'pending', title: 'Pending edited'),
          ],
        );

        final updated = await service.updateJobSpec(
          workspace: workspace,
          snapshot: snapshot,
          rawJson: jsonEncode(edited.toJson()),
        );

        expect(updated.spec.phases.first.id, 'completed');
        expect(updated.spec.phases.first.status, PhaseStatus.completed);
        expect(updated.spec.phases.last.title, 'Pending edited');
        expect(updated.state.currentPhaseId, 'pending');
      },
    );

    test('proposes replans without saving until applied', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(now);
      final snapshot = JobSnapshot(
        taskBrief: brief,
        spec: _spec(
          now: now,
          brief: brief,
          phases: [_phase(id: 'old_pending', title: 'Old pending phase')],
        ),
        state: JobState(
          jobId: 'job_test',
          status: JobStatus.paused,
          currentPhaseId: 'old_pending',
          updatedAt: now,
          completedPhases: const [],
          failedPhases: const ['old_pending'],
          skippedPhases: const [],
          artifacts: const [],
          openQuestions: const [],
          assumptions: const [],
          risks: const [],
          phaseRuns: const [],
          latestSummary: 'Paused',
        ),
      );
      final replannedSpec = _spec(
        now: now,
        brief: brief,
        phases: [_phase(id: 'new_phase', title: 'New proposed phase')],
      );
      final server = await _completionServer([
        {'content': jsonEncode(replannedSpec.toJson())},
      ]);
      addTearDown(server.close);

      final proposal = await service.proposeReplanJob(
        client: server.client,
        workspace: workspace,
        snapshot: snapshot,
        baseSystemPrompt: 'System',
        scope: ReplanScope.remainingPhases,
      );

      expect(proposal.spec.phases.single.id, 'new_phase');
      expect(proposal.state.currentPhaseId, 'new_phase');
      expect(
        await File('${root.path}/.agent/jobs/job_test/job-spec.yaml').exists(),
        isFalse,
      );

      final applied = await service.applyReplanProposal(
        workspace: workspace,
        current: snapshot,
        proposal: proposal,
      );
      final loaded = await JobStorageService().loadJob(root.path, 'job_test');

      expect(applied.spec.phases.single.id, 'new_phase');
      expect(loaded?.spec.phases.single.id, 'new_phase');
    });

    test(
      'replans remaining phases without changing completed phases',
      () async {
        final now = DateTime(2026, 1, 1);
        final brief = _brief(now);
        final completedPhase = _phase(
          id: 'completed',
          title: 'Completed phase',
          status: PhaseStatus.completed,
        );
        final snapshot = JobSnapshot(
          taskBrief: brief,
          spec: _spec(
            now: now,
            brief: brief,
            phases: [
              completedPhase,
              _phase(id: 'old_pending', title: 'Old pending phase'),
            ],
          ),
          state: JobState(
            jobId: 'job_test',
            status: JobStatus.paused,
            currentPhaseId: 'old_pending',
            updatedAt: now,
            completedPhases: const ['completed'],
            failedPhases: const ['old_pending'],
            skippedPhases: const [],
            artifacts: [
              JobArtifact(
                path: 'completed.md',
                producedByPhaseId: 'completed',
                createdAt: DateTime(2026, 1, 1),
              ),
            ],
            openQuestions: const [],
            assumptions: const [],
            risks: const [],
            phaseRuns: const [],
            latestSummary: 'Paused',
          ),
        );
        final replannedSpec = _spec(
          now: now,
          brief: brief,
          phases: [_phase(id: 'new_phase', title: 'New remaining phase')],
        );
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': jsonEncode(replannedSpec.toJson())},
                  },
                ],
              }),
            );
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });
        final client = ChatClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          model: 'test-model',
        );
        addTearDown(client.dispose);

        final updated = await service.replanRemaining(
          client: client,
          workspace: workspace,
          snapshot: snapshot,
          baseSystemPrompt: 'System',
        );

        expect(updated.spec.phases.map((phase) => phase.id), [
          'completed',
          'new_phase',
        ]);
        expect(updated.spec.phases.first.status, PhaseStatus.completed);
        expect(updated.spec.phases.last.status, PhaseStatus.pending);
        expect(updated.state.completedPhases, ['completed']);
        expect(updated.state.failedPhases, isEmpty);
        expect(updated.state.currentPhaseId, 'new_phase');
      },
    );

    test('replans only the current phase', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(now);
      final snapshot = JobSnapshot(
        taskBrief: brief,
        spec: _spec(
          now: now,
          brief: brief,
          phases: [
            _phase(
              id: 'completed',
              title: 'Completed phase',
              status: PhaseStatus.completed,
            ),
            _phase(
              id: 'target',
              title: 'Old target phase',
              status: PhaseStatus.blocked,
            ),
            _phase(id: 'future', title: 'Future phase'),
          ],
        ),
        state: JobState(
          jobId: 'job_test',
          status: JobStatus.blocked,
          currentPhaseId: 'target',
          updatedAt: now,
          completedPhases: const ['completed'],
          failedPhases: const ['target'],
          skippedPhases: const [],
          artifacts: const [],
          openQuestions: const [],
          assumptions: const [],
          risks: const [],
          phaseRuns: const [],
          latestSummary: 'Blocked',
        ),
      );
      final replannedSpec = _spec(
        now: now,
        brief: brief,
        phases: [_phase(id: 'replacement', title: 'Replacement phase')],
      );
      final server = await _completionServer([
        {'content': jsonEncode(replannedSpec.toJson())},
      ]);
      addTearDown(server.close);

      final updated = await service.replanCurrentPhase(
        client: server.client,
        workspace: workspace,
        snapshot: snapshot,
        baseSystemPrompt: 'System',
      );

      expect(updated.spec.phases.map((phase) => phase.id), [
        'completed',
        'replacement',
        'future',
      ]);
      expect(updated.spec.phases.first.status, PhaseStatus.completed);
      expect(updated.spec.phases.last.title, 'Future phase');
      expect(updated.state.completedPhases, ['completed']);
      expect(updated.state.failedPhases, isEmpty);
      expect(updated.state.currentPhaseId, 'replacement');
    });

    test('replans the entire executable job and preserves history', () async {
      final now = DateTime(2026, 1, 1);
      final brief = _brief(now);
      final snapshot = JobSnapshot(
        taskBrief: brief,
        spec: _spec(
          now: now,
          brief: brief,
          phases: [
            _phase(
              id: 'completed',
              title: 'Completed phase',
              status: PhaseStatus.completed,
            ),
            _phase(id: 'old_pending', title: 'Old pending phase'),
          ],
        ),
        state: JobState(
          jobId: 'job_test',
          status: JobStatus.paused,
          currentPhaseId: 'old_pending',
          updatedAt: now,
          completedPhases: const ['completed'],
          failedPhases: const ['old_pending'],
          skippedPhases: const [],
          artifacts: [
            JobArtifact(
              path: 'completed.md',
              producedByPhaseId: 'completed',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          openQuestions: const [],
          assumptions: const [],
          risks: const [],
          phaseRuns: [
            PhaseRun(
              phaseId: 'completed',
              runId: 'run_1',
              status: PhaseRunStatus.completed,
              startedAt: DateTime(2026, 1, 1),
              completedAt: DateTime(2026, 1, 1),
              toolCalls: const [],
              filesRead: const [],
              filesWritten: const [],
              filesPatched: const [],
              terminalCommands: const [],
              summary: 'Historical run',
            ),
          ],
          latestSummary: 'Paused',
        ),
      );
      final replannedSpec = _spec(
        now: now,
        brief: brief,
        phases: [
          _phase(id: 'new_start', title: 'New start phase'),
          _phase(id: 'new_finish', title: 'New finish phase'),
        ],
      );
      final server = await _completionServer([
        {'content': jsonEncode(replannedSpec.toJson())},
      ]);
      addTearDown(server.close);

      final updated = await service.replanEntireJob(
        client: server.client,
        workspace: workspace,
        snapshot: snapshot,
        baseSystemPrompt: 'System',
      );

      expect(updated.spec.phases.map((phase) => phase.id), [
        'new_start',
        'new_finish',
      ]);
      expect(
        updated.spec.phases.every(
          (phase) => phase.status == PhaseStatus.pending,
        ),
        isTrue,
      );
      expect(updated.state.completedPhases, isEmpty);
      expect(updated.state.failedPhases, isEmpty);
      expect(updated.state.currentPhaseId, 'new_start');
      expect(updated.state.artifacts.single.path, 'completed.md');
      expect(updated.state.phaseRuns.single.summary, 'Historical run');
    });
  });

  group('JobService deterministic validators', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_validators_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('checks yaml outputs and required and forbidden patterns', () async {
      final server = await _completionServer([
        {'content': 'title: Report\nseverity: high\n'},
      ]);
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            expectedOutputs: const [
              PhaseOutput(
                path: 'output.yaml',
                required: true,
                format: ArtifactFormat.yaml,
              ),
            ],
            validation: const PhaseValidation(
              requiredPatterns: ['severity: high'],
              forbiddenPatterns: ['TODO'],
            ),
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.completed);
      final checks =
          updated.state.phaseRuns.single.reviewResult!.deterministicChecks;
      expect(
        checks
            .singleWhere((check) => check.id == 'yaml_parse:output.yaml')
            .passed,
        isTrue,
      );
      expect(
        checks
            .singleWhere(
              (check) => check.id == 'required_pattern:severity: high',
            )
            .passed,
        isTrue,
      );
      expect(
        checks
            .singleWhere((check) => check.id == 'forbidden_pattern:TODO')
            .passed,
        isTrue,
      );
    });

    test('fails invalid yaml output deterministically', () async {
      final server = await _completionServer([
        {'content': 'not yaml'},
      ]);
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            expectedOutputs: const [
              PhaseOutput(
                path: 'output.yaml',
                required: true,
                format: ArtifactFormat.yaml,
              ),
            ],
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      final checks =
          updated.state.phaseRuns.single.reviewResult!.deterministicChecks;
      expect(
        checks
            .singleWhere((check) => check.id == 'yaml_parse:output.yaml')
            .passed,
        isFalse,
      );
    });

    test('fails malformed yaml output deterministically', () async {
      final server = await _completionServer([
        {'content': 'items: [one, two'},
      ]);
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            expectedOutputs: const [
              PhaseOutput(
                path: 'output.yaml',
                required: true,
                format: ArtifactFormat.yaml,
              ),
            ],
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      final checks =
          updated.state.phaseRuns.single.reviewResult!.deterministicChecks;
      expect(
        checks
            .singleWhere((check) => check.id == 'yaml_parse:output.yaml')
            .passed,
        isFalse,
      );
    });

    test('enforces mustExist and mustNotModify validation', () async {
      await File('${root.path}/preexisting.txt').writeAsString('required');
      await File('${root.path}/protected.txt').writeAsString('original');
      final server = await _completionServer([
        {
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'write_file',
                'arguments': {'path': 'protected.txt', 'content': 'changed'},
              },
            },
          ],
        },
        {'content': 'done'},
      ]);
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            allowedTools: const ['write_file'],
            validation: const PhaseValidation(
              mustExist: ['preexisting.txt'],
              mustNotModify: ['protected.txt'],
            ),
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      final checks =
          updated.state.phaseRuns.single.reviewResult!.deterministicChecks;
      expect(
        checks
            .singleWhere((check) => check.id == 'must_exist:preexisting.txt')
            .passed,
        isTrue,
      );
      expect(
        checks
            .singleWhere((check) => check.id == 'must_not_modify:protected.txt')
            .passed,
        isFalse,
      );
    });

    test('records file change previews for mutating tools', () async {
      await File(
        '${root.path}/target.txt',
      ).writeAsString('alpha\nold\nomega\n');
      final server = await _completionServer([
        {
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'patch_file',
                'arguments': {
                  'path': 'target.txt',
                  'old_text': 'old',
                  'new_text': 'new',
                },
              },
            },
          ],
        },
        {'content': 'done'},
      ]);
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            allowedTools: const ['patch_file'],
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.completed);
      final change = updated.state.phaseRuns.single.fileChanges.single;
      expect(change.path, 'target.txt');
      expect(change.changeType, 'modified');
      expect(change.toolName, 'patch_file');
      expect(change.addedLines, 1);
      expect(change.removedLines, 1);
      expect(change.diff, contains('-old'));
      expect(change.diff, contains('+new'));
    });

    test('captures mutating tool calls as pending hunk approvals', () async {
      final target = File('${root.path}/target.txt');
      await target.writeAsString('alpha\nold\nomega\n');
      final server = await _completionServer([
        {
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'patch_file',
                'arguments': {
                  'path': 'target.txt',
                  'old_text': 'old',
                  'new_text': 'new',
                },
              },
            },
            {
              'id': 'call_2',
              'type': 'function',
              'function': {
                'name': 'write_file',
                'arguments': {
                  'path': 'after.txt',
                  'content': 'must not be applied before approval',
                },
              },
            },
          ],
        },
        {'content': 'done'},
      ]);
      addTearDown(server.close);

      final blocked = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            allowedTools: const ['patch_file', 'write_file'],
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
        requireFileEditApproval: true,
      );

      expect(await target.readAsString(), 'alpha\nold\nomega\n');
      expect(await File('${root.path}/after.txt').exists(), isFalse);
      expect(blocked.state.status, JobStatus.blocked);
      expect(blocked.spec.phases.single.status, PhaseStatus.blocked);
      expect(blocked.state.failedPhases, contains('phase_1'));
      expect(blocked.state.pendingApprovals, hasLength(1));
      expect(blocked.state.phaseRuns.single.status, PhaseRunStatus.blocked);
      expect(blocked.state.phaseRuns.single.filesPatched, isEmpty);
      expect(blocked.state.phaseRuns.single.fileChanges, isEmpty);

      final approval = blocked.state.pendingApprovals.single;
      expect(approval.status, 'pending');
      expect(approval.path, 'target.txt');
      expect(approval.toolName, 'patch_file');
      expect(approval.hunks, hasLength(1));
      expect(approval.hunks.single.diff, contains('-old'));
      expect(approval.hunks.single.diff, contains('+new'));
      expect(blocked.state.phaseRuns.single.toolCalls, hasLength(1));
      expect(
        blocked.state.phaseRuns.single.toolCalls.single.resultSummary,
        contains('approval_required'),
      );

      final resolved = await service.resolveFileApproval(
        workspace: workspace,
        snapshot: blocked,
        approvalId: approval.id,
        approvedHunkIds: {approval.hunks.single.id},
      );

      expect(await target.readAsString(), 'alpha\nnew\nomega');
      expect(resolved.state.status, JobStatus.paused);
      expect(resolved.spec.phases.single.status, PhaseStatus.pending);
      expect(resolved.state.failedPhases, isNot(contains('phase_1')));
      expect(resolved.state.pendingApprovals.single.status, 'applied');
      expect(
        resolved.state.pendingApprovals.single.hunks.single.status,
        'applied',
      );
      expect(resolved.state.phaseRuns.single.filesPatched, ['target.txt']);
      final change = resolved.state.phaseRuns.single.fileChanges.single;
      expect(change.path, 'target.txt');
      expect(change.toolName, 'patch_file');
      expect(change.diff, contains('-old'));
      expect(change.diff, contains('+new'));
    });

    test('supports injected deterministic phase validators', () async {
      service = JobService(
        toolService: ToolService(),
        phaseValidators: const [_BlockingPhaseValidator()],
      );
      final server = await _completionServer([
        {'content': 'done'},
      ]);
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phase: _phase(
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      final checks =
          updated.state.phaseRuns.single.reviewResult!.deterministicChecks;
      expect(
        checks.singleWhere((check) => check.id == 'custom_block').passed,
        isFalse,
      );
    });

    test('does not enforce phase or total tool call budgets', () async {
      await File('${root.path}/input.txt').writeAsString('source');
      final server = await _completionServer([
        {
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'read_file',
                'arguments': {'path': 'input.txt'},
              },
            },
          ],
        },
        {'content': 'done'},
      ]);
      addTearDown(server.close);

      final previousRun = PhaseRun(
        phaseId: 'previous',
        runId: 'previous_run',
        status: PhaseRunStatus.completed,
        startedAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 1, 1),
        toolCalls: [
          ToolCallRecord(
            id: 'previous_call',
            jobId: 'job_test',
            phaseId: 'previous',
            runId: 'previous_run',
            toolName: 'read_file',
            timestamp: DateTime(2026, 1, 1),
          ),
        ],
        filesRead: const [],
        filesWritten: const [],
        filesPatched: const [],
        terminalCommands: const [],
        summary: 'Previous phase',
      );

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phaseRuns: [previousRun],
          stopPolicy: const StopPolicy(),
          phase: _phase(
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.completed);
      final checks = updated
          .state
          .phaseRuns
          .last
          .reviewResult!
          .deterministicChecks
          .map((check) => check.id);
      expect(checks, isNot(contains('max_tool_calls')));
      expect(checks, isNot(contains('max_total_tool_calls')));
      expect(
        updated.state.phaseRuns.last.toolCalls.where(
          (call) => call.toolName == 'read_file',
        ),
        isNotEmpty,
      );
      expect(updated.state.phaseRuns.last.toolCalls.single.error, isNull);
    });

    test('does not enforce tool error count as a review failure', () async {
      final server = await _completionServer([
        {'content': 'done'},
      ]);
      addTearDown(server.close);

      final previousRun = PhaseRun(
        phaseId: 'previous',
        runId: 'previous_run',
        status: PhaseRunStatus.reviewFailed,
        startedAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 1, 1),
        toolCalls: [
          ToolCallRecord(
            id: 'previous_call',
            jobId: 'job_test',
            phaseId: 'previous',
            runId: 'previous_run',
            toolName: 'read_file',
            arguments: const {'path': 'missing.txt'},
            error: 'Path not found.',
            timestamp: DateTime(2026, 1, 1),
          ),
        ],
        filesRead: const [],
        filesWritten: const [],
        filesPatched: const [],
        terminalCommands: const [],
        summary: 'Previous failed attempt',
      );

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: workspace,
        snapshot: _snapshot(
          phaseRuns: [previousRun],
          stopPolicy: const StopPolicy(),
          phase: _phase(
            expectedOutputs: const [],
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.completed);
      final checks = updated
          .state
          .phaseRuns
          .last
          .reviewResult!
          .deterministicChecks
          .map((check) => check.id);
      expect(checks, isNot(contains('tool_error_count')));
    });

    test('enforces phase runtime, file read, and terminal budgets', () async {
      await File('${root.path}/input.txt').writeAsString('source');
      final server = await _completionServer([
        {
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'read_file',
                'arguments': {'path': 'input.txt'},
              },
            },
            {
              'id': 'call_2',
              'type': 'function',
              'function': {
                'name': 'run_command',
                'arguments': {'command': 'pwd'},
              },
            },
          ],
        },
        {'content': 'done'},
      ], responseDelay: const Duration(milliseconds: 20));
      addTearDown(server.close);

      final updated = await service.runNextPhase(
        client: server.client,
        workspace: WorkspaceAttachment.fromPath(
          root.path,
          commandExecutionApproved: true,
        ),
        snapshot: _snapshot(
          stopPolicy: const StopPolicy(
            maxRuntimeSeconds: 0,
            maxPhaseFilesRead: 0,
            maxPhaseTerminalCommands: 0,
          ),
          phase: _phase(
            allowedTools: const ['read_file', 'run_command'],
            terminalPolicy: TerminalPolicy.workspaceMutating,
            review: const ReviewPolicy(
              required: true,
              reviewer: ReviewerType.deterministic,
            ),
            retryPolicy: null,
          ),
        ),
        baseSystemPrompt: 'System',
      );

      expect(updated.state.status, JobStatus.blocked);
      final checks =
          updated.state.phaseRuns.single.reviewResult!.deterministicChecks;
      expect(
        checks.singleWhere((check) => check.id == 'max_runtime_seconds').passed,
        isFalse,
      );
      expect(
        checks
            .singleWhere((check) => check.id == 'max_phase_files_read')
            .passed,
        isFalse,
      );
      expect(
        checks
            .singleWhere((check) => check.id == 'max_phase_terminal_commands')
            .passed,
        isFalse,
      );
    });
  });

  group('JobService recovery', () {
    late Directory root;
    late JobService service;
    late WorkspaceAttachment workspace;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_job_recovery_');
      service = JobService(toolService: ToolService());
      workspace = WorkspaceAttachment.fromPath(root.path);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('marks interrupted running phases as blocked on resume', () async {
      final recovered = await service.recoverJob(
        workspace: workspace,
        snapshot: _snapshot(
          status: JobStatus.running,
          phaseStatus: PhaseStatus.running,
        ),
      );

      expect(recovered.state.status, JobStatus.blocked);
      expect(recovered.spec.phases.single.status, PhaseStatus.blocked);
      expect(recovered.state.currentPhaseId, 'phase_1');
      expect(recovered.state.latestSummary, contains('interrupted phase'));
    });

    test('blocks completed phases with missing required artifacts', () async {
      final recovered = await service.recoverJob(
        workspace: workspace,
        snapshot: _snapshot(
          status: JobStatus.completed,
          phaseStatus: PhaseStatus.completed,
          completedPhases: const ['phase_1'],
          artifacts: [
            JobArtifact(
              path: 'output.md',
              producedByPhaseId: 'phase_1',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );

      expect(recovered.state.status, JobStatus.blocked);
      expect(recovered.spec.phases.single.status, PhaseStatus.blocked);
      expect(recovered.state.completedPhases, isEmpty);
      expect(recovered.state.failedPhases, ['phase_1']);
      expect(recovered.state.artifacts, isEmpty);
      expect(recovered.state.latestSummary, contains('missing or empty'));
    });

    test(
      'blocks missing required phase input before model execution',
      () async {
        final client = ChatClient(baseUrl: 'http://127.0.0.1:1', model: 'none');
        addTearDown(client.dispose);

        final recovered = await service.runNextPhase(
          client: client,
          workspace: workspace,
          snapshot: _snapshot(
            phase: _phase(
              inputs: const [PhaseInput(path: 'missing.md', required: true)],
            ),
          ),
          baseSystemPrompt: 'System',
        );

        expect(recovered.state.status, JobStatus.blocked);
        expect(recovered.state.phaseRuns, isEmpty);
        expect(recovered.state.latestSummary, contains('Required input'));
      },
    );
  });
}

Future<({ChatClient client, Future<void> Function() close})> _completionServer(
  List<Map<String, dynamic>> responses, {
  Duration? responseDelay,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requestCount = 0;
  final subscription = server.listen((request) async {
    final index = requestCount >= responses.length
        ? responses.length - 1
        : requestCount;
    requestCount++;
    if (responseDelay != null) {
      await Future<void>.delayed(responseDelay);
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'choices': [
            {'message': responses[index]},
          ],
        }),
      );
    await request.response.close();
  });

  final client = ChatClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    model: 'test-model',
  );
  return (
    client: client,
    close: () async {
      client.dispose();
      await subscription.cancel();
      await server.close(force: true);
    },
  );
}

JobSnapshot _snapshot({
  JobStatus status = JobStatus.planned,
  PhaseStatus phaseStatus = PhaseStatus.pending,
  JobPhase? phase,
  List<OpenQuestion> openQuestions = const [],
  ReviewPolicy review = const ReviewPolicy(
    required: true,
    reviewer: ReviewerType.hybrid,
  ),
  StopPolicy stopPolicy = const StopPolicy(),
  List<PhaseRun> phaseRuns = const [],
  List<String> completedPhases = const [],
  List<String> failedPhases = const [],
  List<JobArtifact> artifacts = const [],
}) {
  final now = DateTime(2026, 1, 1);
  final brief = _brief(now);
  final selectedPhase = phase ?? _phase(status: phaseStatus, review: review);
  return JobSnapshot(
    taskBrief: brief,
    spec: _spec(
      now: now,
      brief: brief,
      status: status,
      phases: [selectedPhase],
      stopPolicy: stopPolicy,
    ),
    state: JobState(
      jobId: 'job_test',
      status: status,
      currentPhaseId: selectedPhase.id,
      updatedAt: now,
      completedPhases: completedPhases,
      failedPhases: failedPhases,
      skippedPhases: const [],
      artifacts: artifacts,
      openQuestions: openQuestions,
      assumptions: const [],
      risks: const [],
      phaseRuns: phaseRuns,
      latestSummary: 'Planned',
    ),
  );
}

JobSnapshot _terminalSnapshot() {
  final now = DateTime(2026, 1, 1);
  final brief = _brief(now);
  final phase = _phase(
    terminalPolicy: TerminalPolicy.readonly,
    allowedTools: const ['run_command'],
    review: const ReviewPolicy(
      required: true,
      reviewer: ReviewerType.deterministic,
    ),
    retryPolicy: null,
  );
  return JobSnapshot(
    taskBrief: brief,
    spec: _spec(
      now: now,
      brief: brief,
      phases: [phase],
      toolPolicy: const ToolPolicy(
        defaultAllowed: ['run_command'],
        terminal: TerminalToolPolicy(
          allowed: true,
          policy: TerminalPolicy.readonly,
        ),
      ),
    ),
    state: JobState(
      jobId: 'job_test',
      status: JobStatus.planned,
      updatedAt: now,
      completedPhases: const [],
      failedPhases: const [],
      skippedPhases: const [],
      artifacts: const [],
      openQuestions: const [],
      assumptions: const [],
      risks: const [],
      phaseRuns: const [],
      latestSummary: 'Planned',
    ),
  );
}

TaskBrief _brief(
  DateTime now, {
  List<ClarifyingQuestion> clarifyingQuestions = const [],
}) {
  return TaskBrief(
    id: 'task_test',
    createdAt: now,
    updatedAt: now,
    title: 'Test job',
    originalPrompt: 'Do the thing',
    objective: 'Do the thing',
    successCriteria: const ['Produces output'],
    constraints: const ['Stay inside workspace'],
    nonGoals: const [],
    assumptions: const [],
    clarifyingQuestions: clarifyingQuestions,
    recommendedMode: ExecutionMode.job,
    recommendedAutonomy: AutonomyLevel.checkpointed,
    requiredOutputs: const [RequiredOutput(path: 'output.md', required: true)],
    domain: JobDomain.general,
    riskLevel: RiskLevel.low,
  );
}

JobSpec _spec({
  required DateTime now,
  required TaskBrief brief,
  JobStatus status = JobStatus.planned,
  List<JobPhase> phases = const [],
  ToolPolicy toolPolicy = const ToolPolicy(defaultAllowed: ['read_file']),
  StopPolicy stopPolicy = const StopPolicy(),
}) {
  return JobSpec(
    version: 1,
    id: 'job_test',
    title: 'Test job',
    createdAt: now,
    updatedAt: now,
    taskBriefId: brief.id,
    status: status,
    domain: JobDomain.general,
    autonomy: AutonomyLevel.checkpointed,
    globalConstraints: brief.constraints,
    globalSuccessCriteria: brief.successCriteria,
    toolPolicy: toolPolicy,
    stopPolicy: stopPolicy,
    phases: phases,
  );
}

JobPhase _phase({
  String id = 'phase_1',
  String title = 'Phase 1',
  PhaseStatus status = PhaseStatus.pending,
  TerminalPolicy terminalPolicy = TerminalPolicy.none,
  List<PhaseInput> inputs = const [],
  List<PhaseOutput> expectedOutputs = const [
    PhaseOutput(path: 'output.md', required: true),
  ],
  List<String> allowedTools = const ['read_file'],
  PhaseValidation? validation,
  ReviewPolicy review = const ReviewPolicy(
    required: true,
    reviewer: ReviewerType.hybrid,
  ),
  RetryPolicy? retryPolicy = const RetryPolicy(),
}) {
  return JobPhase(
    id: id,
    title: title,
    objective: 'Produce output',
    status: status,
    inputs: inputs,
    expectedOutputs: expectedOutputs,
    allowedTools: allowedTools,
    terminalPolicy: terminalPolicy,
    validation: validation,
    completionCriteria: const ['Output exists'],
    review: review,
    humanCheckpoint: false,
    retryPolicy: retryPolicy,
  );
}

class _BlockingPhaseValidator implements PhaseValidator {
  const _BlockingPhaseValidator();

  @override
  String get id => 'custom_block';

  @override
  PhaseValidatorType get type => PhaseValidatorType.deterministic;

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    return const [
      PhaseValidationResult(
        id: 'custom_block',
        passed: false,
        severity: 'error',
        message: 'Custom validator blocked the phase.',
      ),
    ];
  }
}
