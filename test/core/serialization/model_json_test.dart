import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/chat/context_summary_prompt.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/tools/calculator_tool.dart';

void main() {
  final now = DateTime(2026, 1, 2, 3, 4, 5);

  test('facade supports untyped maps and compact or indented strings', () {
    final snapshot = ModelJson.decode<ModelConfigurationSnapshot>(const {});
    expect(snapshot.nCtx, 4096);

    final compact = ModelJson.encodeString(snapshot);
    final indented = ModelJson.encodeString(snapshot, indent: '  ');
    expect(jsonDecode(compact), ModelJson.encode(snapshot));
    expect(indented, contains('\n  "modelName"'));
  });

  test('task DTOs preserve their canonical maps', () {
    final gate = TaskGate(
      id: 'artifact_exists',
      params: const {
        'paths': ['out.md'],
      },
    );
    final artifact = TaskArtifact(
      path: 'out.md',
      description: 'Output',
      stepId: 'step_1',
      createdAt: now,
    );
    final gateResult = TaskGateResult(
      gateId: gate.id,
      status: TaskGateStatus.passed,
      summary: 'Passed',
      evaluatedAt: now,
    );
    final toolCall = TaskToolCallRecord(
      id: 'call_1',
      stepId: 'step_1',
      runId: 'run_1',
      toolName: 'run_command',
      arguments: const {'command': 'dart test'},
      timestamp: now,
    );
    final step = TaskStep(
      id: 'step_1',
      title: 'Step',
      objective: 'Work',
      instructions: const ['Do it'],
      mayEditFiles: true,
      artifacts: [artifact],
      gates: [gate],
      status: TaskStepStatus.pending,
    );
    final run = TaskRun(
      runId: 'run_1',
      stepId: step.id,
      status: TaskRunStatus.needsReplan,
      summary: 'Needs another pass',
      memoryUpdate: '',
      toolCalls: [toolCall],
      artifacts: [artifact],
      gateResults: [gateResult],
      startedAt: now,
    );
    final approval = PendingTaskApproval(
      stepId: step.id,
      reason: 'Review',
      createdAt: now,
    );
    final question = PendingTaskQuestion(
      id: 'question_1',
      stepId: step.id,
      question: 'Continue?',
      createdAt: now,
    );
    final document = TaskDocument(
      id: 'task_1',
      title: 'Task',
      originalPrompt: 'Work',
      goal: 'Finish',
      constraints: const [],
      successCriteria: const ['Done'],
      gates: [gate],
      steps: [step],
      status: TaskStatus.blocked,
      currentStepId: step.id,
      memorySummary: '',
      runs: [run],
      pendingApproval: approval,
      pendingQuestion: question,
      createdAt: now,
      updatedAt: now,
    );

    expect(ModelJson.encode(gate), {
      'id': 'artifact_exists',
      'required': true,
      'scope': 'step',
      'params': {
        'paths': ['out.md'],
      },
    });
    expect(ModelJson.encode(artifact), {
      'path': 'out.md',
      'description': 'Output',
      'stepId': 'step_1',
      'createdAt': now.toIso8601String(),
    });
    expect(ModelJson.encode(gateResult)['status'], 'passed');
    expect(ModelJson.encode(toolCall), isNot(contains('result')));
    expect(ModelJson.encode(step)['status'], 'pending');
    expect(ModelJson.encode(run)['status'], 'needs_replan');
    expect(ModelJson.encode(approval)['stepId'], 'step_1');
    expect(ModelJson.encode(question)['question'], 'Continue?');
    expect(ModelJson.encode(document), containsPair('schemaVersion', 2));

    final brief = ModelJson.decode<RefinedTaskBrief>({
      'title': 'Brief',
      'objective': 'Ship',
      'success_criteria': ['Works'],
    });
    expect(brief.goal, 'Ship');
    expect(ModelJson.encode(brief)['successCriteria'], ['Works']);
  });

  test('project DTOs preserve maps, aliases, defaults, and migration', () {
    final artifact = ProjectArtifact(
      id: 'artifact_1',
      projectTaskId: 'project_task_1',
      taskDocumentId: null,
      path: 'out.md',
      description: 'Output',
      kind: 'file',
      createdAt: now,
    );
    final task = ProjectTask(
      id: 'project_task_1',
      title: 'Task',
      objective: 'Work',
      relevantSuccessCriteria: const ['Done'],
      doneCriteria: const ['Done'],
      outOfScope: const [],
      context: const [],
      expectedArtifacts: [artifact],
      status: ProjectTaskStatus.queued,
      taskDocumentId: null,
      fingerprint: 'fingerprint',
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
    final incident = ProjectRecoveryIncident(
      id: 'incident_1',
      status: ProjectRecoveryIncidentStatus.active,
      sourceTaskIds: const ['task_1'],
      sourceTaskTitles: const ['Task'],
      failedGateId: 'tests',
      failureSummary: 'Failed',
      attemptCount: 1,
      recoveryTaskIds: const [],
      createdAt: now,
      updatedAt: now,
    );
    final decision = ProjectDecisionRecord(
      id: 'decision_1',
      decision: ProjectDecisionType.createTask,
      summary: 'Create',
      memoryUpdate: '',
      createdAt: now,
    );
    final blocker = ProjectBlocker(
      type: ProjectBlockerType.taskFailed,
      message: 'Failed',
      createdAt: now,
    );
    final question = PendingProjectQuestion(
      id: 'question_1',
      question: 'Continue?',
      createdAt: now,
    );
    final taskRef = ProjectTaskRef(
      taskId: 'task_1',
      title: 'Task',
      status: TaskStatus.paused,
      summary: '',
      createdAt: now,
      updatedAt: now,
    );

    expect(ModelJson.encode(artifact), isNot(contains('taskDocumentId')));
    expect(ModelJson.encode(task)['expectedArtifacts'], hasLength(1));
    expect(ModelJson.encode(incident)['maxAttempts'], 3);
    expect(ModelJson.encode(decision)['decision'], 'create_task');
    expect(ModelJson.encode(blocker)['type'], 'task_failed');
    expect(ModelJson.encode(question)['question'], 'Continue?');
    expect(ModelJson.encode(taskRef)['status'], 'paused');

    final migrated = ModelJson.decode<ProjectDocument>({
      'schema_version': 1,
      'id': 'project_1',
      'title': 'Legacy',
      'original_prompt': 'Build',
      'goal': 'Build it',
      'status': 'running',
      'active_task_id': 'task_1',
      'tasks': [
        {
          'task_id': 'task_1',
          'title': 'Legacy task',
          'status': 'running',
          'summary': 'Work',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
      ],
      'pending_question': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    expect(migrated.schemaVersion, 2);
    expect(migrated.currentTask?.taskDocumentId, 'task_1');
    expect(ModelJson.encode(migrated), isNot(contains('tasks')));
  });

  test('prompt snapshots retain epoch dates and nullable keys', () {
    final module = PromptModule(
      id: 'module_1',
      name: 'Module',
      category: 'general',
      content: 'Instructions',
      priority: 10,
      isBuiltIn: false,
      requiredModuleIds: const [],
      conflictingModuleIds: const [],
      createdAt: now,
      updatedAt: now,
    );
    final preset = PromptPreset(
      id: 'preset_1',
      name: 'Preset',
      baseModuleIds: const ['module_1'],
      optionalModuleIds: const [],
      customInstructions: '',
      legacyFullPrompt: null,
      isBuiltIn: false,
      createdAt: now,
      updatedAt: now,
    );
    final snapshot = SystemPromptSnapshot(
      id: null,
      name: 'Prompt',
      text: 'Instructions',
      preset: preset,
      modules: [module],
    );

    expect(ModelJson.encode(module)['createdAt'], now.millisecondsSinceEpoch);
    expect(ModelJson.encode(preset), containsPair('lastUsedAt', null));
    expect(ModelJson.encode(snapshot), containsPair('id', null));
    expect(
      ModelJson.decode<SystemPromptSnapshot>(ModelJson.encode(snapshot)).text,
      'Instructions',
    );
  });

  test('boundary DTOs keep aliases and protocol omission rules', () async {
    final summary = ModelJson.decode<ContextSummary>({
      'schema_version': 1,
      'task': 'Work',
      'open_questions': ['Which platform?'],
    });
    expect(summary.openQuestions, ['Which platform?']);

    final question = ModelJson.decode<AgentQuestion>({
      'question': 'Choose?',
      'whyBlocking': 'Required',
      'default_if_unanswered': 'Desktop',
      'type': 'PREFERENCE',
    });
    expect(question.kind, QuestionKind.preference);
    expect(question.reason, 'Required');

    const message = ChatMessage(
      role: 'assistant',
      content: 'Done',
      reasoningContent: 'Thought',
    );
    expect(ModelJson.encode(message), {
      'role': 'assistant',
      'content': 'Done',
      'reasoning_content': 'Thought',
    });

    final planning = TaskPlanningContext(
      projectGoal: 'Build',
      projectTaskObjective: 'Implement',
      expectedArtifacts: const [TaskArtifact(path: 'out.md')],
      requiredGates: const [TaskGate(id: 'tests')],
    );
    expect(ModelJson.encode(planning)['expectedArtifacts'], [
      {'path': 'out.md'},
    ]);

    const metadata = WorkspaceMetadata(
      rootFiles: ['pubspec.yaml'],
      gitAvailable: true,
    );
    expect(ModelJson.encode(metadata), isNot(contains('workspaceName')));

    final operation = ModelJson.decode<CalculatorOperation>({
      'paramA': '2',
      'paramB': 3,
      'operator': '+',
    });
    expect(operation.paramA, 2);
    expect(
      () => ModelJson.decode<CalculatorOperation>({'paramA': 'nope'}),
      throwsA(anything),
    );
  });
}
