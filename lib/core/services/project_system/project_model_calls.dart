import 'dart:convert';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/finalizer_tool_call_runner.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/tool_service.dart';

class ProjectInitialisation {
  final String title;
  final String refinedGoal;
  final List<String> successCriteria;
  final List<String> constraints;
  final List<String> knownFacts;
  final List<PendingProjectQuestion> openQuestions;
  final List<ProjectTask> backlog;

  const ProjectInitialisation({
    required this.title,
    required this.refinedGoal,
    required this.successCriteria,
    required this.constraints,
    required this.knownFacts,
    required this.openQuestions,
    required this.backlog,
  });
}

class ProjectCompletionAssessment {
  final bool complete;
  final String finalSummary;
  final List<String> remainingCriteria;
  final List<PendingProjectQuestion> openQuestions;

  const ProjectCompletionAssessment({
    required this.complete,
    required this.finalSummary,
    required this.remainingCriteria,
    required this.openQuestions,
  });
}

class ProjectBacklogRefresh {
  final List<ProjectTask> backlog;
  final List<String> knownFacts;
  final List<PendingProjectQuestion> openQuestions;

  const ProjectBacklogRefresh({
    required this.backlog,
    required this.knownFacts,
    required this.openQuestions,
  });
}

class ProjectModelCalls {
  ProjectModelCalls({required ToolService toolService})
    : _creationRunner = FinalizerToolCallRunner(toolService: toolService);

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');
  final FinalizerToolCallRunner _creationRunner;

  Future<ProjectInitialisation> initializeProject({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeFinalizedJson(
        client: client,
        workspace: workspace,
        label: 'Project Initializer',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"title":"...","refinedGoal":"...","successCriteria":["..."],"constraints":["..."],"knownFacts":["..."],"openQuestions":[{"question":"..."}],"backlog":[]}',
        finalizerTool: _finaliseProjectCreationToolDefinition(
          requiredProperties: const [
            'title',
            'refinedGoal',
            'successCriteria',
            'constraints',
          ],
        ),
        user:
            '''
Initialize a persistent project state. Do not execute the project.
Do not create a full task plan up front. Backlog is optional; include only tasks that are immediately obvious and small.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; record a useful assumption in knownFacts instead.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "title": "...",
  "refinedGoal": "...",
  "successCriteria": ["..."],
  "constraints": ["..."],
  "knownFacts": ["..."],
  "openQuestions": [{"question": "..."}],
  "backlog": []
}

Workspace metadata:
${_encoder.convert(workspaceMetadata)}

Original project goal:
$originalGoal
''',
      );
      final refinedGoal = jsonString(
        json['refinedGoal'] ?? json['refined_goal'],
        fallback: originalGoal,
      );
      final criteria = jsonStringList(
        json['successCriteria'] ?? json['success_criteria'],
      );
      return ProjectInitialisation(
        title: jsonString(
          json['title'],
          fallback: _titleFromGoal(originalGoal),
        ),
        refinedGoal: refinedGoal,
        successCriteria: criteria.isEmpty
            ? ['Complete the stated project goal.']
            : criteria,
        constraints: jsonStringList(json['constraints']).isEmpty
            ? ['Stay within the attached workspace.']
            : jsonStringList(json['constraints']),
        knownFacts: jsonStringList(json['knownFacts'] ?? json['known_facts']),
        openQuestions: _questionsFromJson(
          json['openQuestions'] ?? json['open_questions'],
        ),
        backlog: _tasksFromJson(json['backlog']),
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return _fallbackInitialisation(originalGoal);
    }
  }

  Future<ProjectBacklogRefresh> refreshBacklog({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required Map<String, dynamic> workspaceMetadata,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeFinalizedJson(
        client: client,
        workspace: workspace,
        label: 'Project Backlog Refresh',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"backlog":[{"title":"...","objective":"...","relevantSuccessCriteria":["..."],"doneCriteria":["..."],"outOfScope":["..."],"context":["..."],"expectedArtifacts":[]}],"knownFacts":["..."],"openQuestions":[{"question":"..."}]}',
        finalizerTool: _finaliseProjectCreationToolDefinition(
          requiredProperties: const ['backlog'],
        ),
        user:
            '''
Refresh the project backlog. Return only small, bounded, independently verifiable tasks.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable next task/order and record the assumption in knownFacts.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "backlog": [
    {
      "title": "...",
      "objective": "one small bounded task",
      "relevantSuccessCriteria": ["one or two criteria"],
      "doneCriteria": ["..."],
      "outOfScope": ["..."],
      "context": ["..."],
      "expectedArtifacts": [{"path": "...", "description": "...", "kind": "file"}]
    }
  ],
  "knownFacts": ["..."],
  "openQuestions": [{"question": "..."}]
}

Workspace metadata:
${_encoder.convert(workspaceMetadata)}

Project state:
${_encoder.convert(ModelJson.encode(project))}
''',
      );
      return ProjectBacklogRefresh(
        backlog: _tasksFromJson(json['backlog']),
        knownFacts: jsonStringList(json['knownFacts'] ?? json['known_facts']),
        openQuestions: _questionsFromJson(
          json['openQuestions'] ?? json['open_questions'],
        ),
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return const ProjectBacklogRefresh(
        backlog: [],
        knownFacts: [],
        openQuestions: [],
      );
    }
  }

  Future<ProjectTask?> proposeNextTask({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    required Map<String, dynamic> workspaceMetadata,
    required Set<String> forbiddenFingerprints,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Task Selector',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"task":{"title":"...","objective":"...","relevantSuccessCriteria":["..."],"doneCriteria":["..."],"outOfScope":["..."],"context":["..."],"expectedArtifacts":[]}}',
        user:
            '''
Propose exactly one next bounded task for the existing persistent project.
Valid queued backlog tasks are selected before this call. Do not repeat any backlog task or forbidden fingerprint; propose a new bounded task instead.
Do not create a new project.
Respect knownFacts and previous user answers; do not repeat questions that are already answered there.

Return only JSON:
{
  "task": {
    "title": "...",
    "objective": "one small bounded task",
    "relevantSuccessCriteria": ["one or two criteria"],
    "doneCriteria": ["..."],
    "outOfScope": ["..."],
    "context": ["..."],
    "expectedArtifacts": [{"path": "...", "description": "...", "kind": "file"}]
  }
}

Forbidden task fingerprints:
${_encoder.convert(forbiddenFingerprints.toList()..sort())}

Workspace metadata:
${_encoder.convert(workspaceMetadata)}

Project state:
${_encoder.convert(ModelJson.encode(project))}
''',
      );
      final raw = json['task'];
      if (raw is Map) {
        return _taskFromMap(Map<String, dynamic>.from(raw), 0);
      }
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return project.backlog.isEmpty
          ? _fallbackNextTask(project)
          : project.backlog.first;
    }
    return project.backlog.isEmpty
        ? _fallbackNextTask(project)
        : project.backlog.first;
  }

  Future<List<ProjectTask>> splitTask({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    required ProjectTask oversizedTask,
    required List<String> violations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Task Splitter',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"tasks":[{"title":"...","objective":"...","relevantSuccessCriteria":["..."],"doneCriteria":["..."],"outOfScope":["..."],"context":["..."],"expectedArtifacts":[]}]}',
        user:
            '''
Split this oversized or invalid project task into 2 to 5 smaller bounded tasks.

Return only JSON:
{
  "tasks": [
    {
      "title": "...",
      "objective": "one small bounded task",
      "relevantSuccessCriteria": ["one or two criteria"],
      "doneCriteria": ["..."],
      "outOfScope": ["..."],
      "context": ["..."],
      "expectedArtifacts": [{"path": "...", "description": "...", "kind": "file"}]
    }
  ]
}

Validation violations:
${_encoder.convert(violations)}

Invalid task:
${_encoder.convert(ModelJson.encode(oversizedTask))}

Project state:
${_encoder.convert(ModelJson.encode(project))}
''',
      );
      return _tasksFromJson(json['tasks']).take(5).toList();
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Completion Evaluator',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"complete":false,"finalSummary":"...","remainingCriteria":["..."],"openQuestions":[{"question":"..."}]}',
        user:
            '''
Evaluate whether this project is complete. Do not mark complete unless every success criterion is satisfied by completed project tasks and artifacts.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "complete": false,
  "finalSummary": "...",
  "remainingCriteria": ["..."],
  "openQuestions": [{"question": "..."}]
}

Project state:
${_encoder.convert(ModelJson.encode(project))}
''',
      );
      return ProjectCompletionAssessment(
        complete: jsonBool(json['complete']),
        finalSummary: jsonString(json['finalSummary'] ?? json['final_summary']),
        remainingCriteria: jsonStringList(
          json['remainingCriteria'] ?? json['remaining_criteria'],
        ),
        openQuestions: _questionsFromJson(
          json['openQuestions'] ?? json['open_questions'],
        ),
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return ProjectCompletionAssessment(
        complete: false,
        finalSummary: '',
        remainingCriteria: project.successCriteria,
        openQuestions: const [],
      );
    }
  }

  Future<Map<String, dynamic>> _completeJson({
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    required String expectedShape,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final first = await _completeRaw(
      client: client,
      system: system,
      user: user,
      label: label,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final parsed = TaskJson.tryParseObject(first);
    if (parsed != null) return parsed;

    final repaired = await _completeRaw(
      client: client,
      system: system,
      user:
          '''
Repair this malformed model output into one valid JSON object matching this shape:
$expectedShape

Malformed output:
$first

Return only the repaired JSON object.
''',
      label: '$label Repair',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    return TaskJson.parseObject(repaired);
  }

  Future<Map<String, dynamic>> _completeFinalizedJson({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required String system,
    required String user,
    required String label,
    required String expectedShape,
    required ToolDefinition finalizerTool,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) {
    return _creationRunner.completeWithFinalizer(
      client: client,
      workspace: workspace,
      label: label,
      system:
          '''
$system

You may use read-only tools to inspect the workspace before creating or refreshing the project state.
Do not edit files, run terminal commands, rename paths, delete paths, or create artifacts during project creation.
When the project creation data is ready, call the $_finaliseProjectCreationToolId tool with the complete structured payload.
'''
              .trim(),
      user: user,
      finalizerTool: finalizerTool,
      reminderPrompt:
          '''
You did not call $_finaliseProjectCreationToolId. Return only the JSON object that would be passed as that tool's arguments, matching this shape:
$expectedShape
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
  }

  Future<String> _completeRaw({
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.start, label: label),
    );
    final completion = await client.completeChatStreamed(
      messages: [
        ChatMessage(role: 'system', content: system),
        ChatMessage(role: 'user', content: user),
      ],
      onToken: (token) {
        final content = token.content;
        if (content != null && content.isNotEmpty) {
          _emit(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.content,
              label: label,
              text: content,
              token: token,
            ),
          );
        }
        final reasoning = token.reasoning;
        if (reasoning != null && reasoning.isNotEmpty) {
          _emit(
            onModelOutput,
            TaskModelOutputEvent(
              type: TaskModelOutputEventType.reasoning,
              label: label,
              text: reasoning,
              token: token,
            ),
          );
        }
      },
      cancellationToken: cancellationToken,
    );
    _emit(
      onModelOutput,
      TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
    );
    return completion.content.trim().isNotEmpty
        ? completion.content
        : completion.reasoning;
  }

  void _emit(TaskModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }

  ProjectInitialisation _fallbackInitialisation(String originalGoal) {
    return ProjectInitialisation(
      title: _titleFromGoal(originalGoal),
      refinedGoal: originalGoal,
      successCriteria: const ['Complete the stated project goal.'],
      constraints: const ['Stay within the attached workspace.'],
      knownFacts: const [],
      openQuestions: const [],
      backlog: const [],
    );
  }

  List<ProjectTask> _tasksFromJson(Object? value) {
    if (value is! List) return const [];
    final tasks = <ProjectTask>[];
    for (var i = 0; i < value.length; i++) {
      final raw = value[i];
      if (raw is! Map) continue;
      tasks.add(_taskFromMap(Map<String, dynamic>.from(raw), i));
    }
    return tasks;
  }

  ProjectTask _taskFromMap(Map<String, dynamic> map, int index) {
    map['id'] = jsonString(
      map['id'],
      fallback: 'project_task_${index + 1}_${uuid.v7().substring(0, 8)}',
    );
    map['status'] ??= ProjectTaskStatus.queued.wire;
    final task = ModelJson.decode<ProjectTask>(map);
    return task.copyWith(
      fingerprint: projectTaskFingerprint(
        task.objective,
        task.relevantSuccessCriteria,
      ),
    );
  }

  ProjectTask? _fallbackNextTask(ProjectState project) {
    final remainingCriteria = project.successCriteria.where((criterion) {
      final normalised = criterion.trim().toLowerCase();
      return !project.completedTasks.any(
        (task) => task.relevantSuccessCriteria.any(
          (completed) => completed.trim().toLowerCase() == normalised,
        ),
      );
    }).toList();
    final criterion = remainingCriteria.isEmpty
        ? 'Identify the next smallest useful project task.'
        : remainingCriteria.first;
    final now = DateTime.now();
    final objective = 'Make focused progress on: $criterion';
    return ProjectTask(
      id: 'project_task_${uuid.v7()}',
      title: _titleFromGoal(criterion),
      objective: objective,
      relevantSuccessCriteria: [criterion],
      doneCriteria: [
        'Concrete progress for "$criterion" is completed and summarized.',
      ],
      outOfScope: const [
        'Do not complete unrelated success criteria.',
        'Do not expand this into the whole project.',
      ],
      context: project.knownFacts,
      expectedArtifacts: const [],
      status: ProjectTaskStatus.queued,
      taskDocumentId: null,
      fingerprint: projectTaskFingerprint(objective, [criterion]),
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<PendingProjectQuestion> _questionsFromJson(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((raw) {
      final map = Map<String, dynamic>.from(raw);
      map['id'] = jsonString(map['id'], fallback: 'question_${uuid.v7()}');
      map['createdAt'] ??= DateTime.now().toIso8601String();
      final agentQuestion = AgentQuestion.parse(map);
      if (agentQuestion != null) {
        map['question'] = agentQuestion.displayText;
      }
      return ModelJson.decode<PendingProjectQuestion>(map);
    }).toList();
  }

  String _titleFromGoal(String goal) {
    final singleLine = goal.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled project';
    return singleLine.length <= 60
        ? singleLine
        : '${singleLine.substring(0, 57)}...';
  }
}

const String _finaliseProjectCreationToolId = 'finaliseProjectCreation';

ToolDefinition _finaliseProjectCreationToolDefinition({
  required List<String> requiredProperties,
}) {
  return ToolDefinition(
    id: _finaliseProjectCreationToolId,
    name: 'Finalise project creation',
    description:
        'Finalize project creation or backlog refresh with the complete structured project payload. Call this exactly once after any needed read-only workspace discovery.',
    schema: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'refinedGoal': {'type': 'string'},
        'successCriteria': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'constraints': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'knownFacts': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'openQuestions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'question': {'type': 'string'},
              'reason': {'type': 'string'},
              'defaultIfUnanswered': {'type': 'string'},
              'riskOfAssuming': {'type': 'string'},
              'kind': {
                'type': 'string',
                'enum': ['blocking', 'preference', 'advisory'],
              },
            },
            'required': ['question'],
          },
        },
        'backlog': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'objective': {'type': 'string'},
              'relevantSuccessCriteria': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'doneCriteria': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'outOfScope': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'context': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'expectedArtifacts': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'path': {'type': 'string'},
                    'description': {'type': 'string'},
                    'kind': {'type': 'string'},
                  },
                },
              },
            },
            'required': ['title', 'objective', 'doneCriteria', 'outOfScope'],
          },
        },
      },
      'required': requiredProperties,
    },
  );
}

const String _projectJsonSystemInstruction = '''
You are a project orchestration planner.
Return only valid JSON.
Use only read-only tools when they are exposed.
Do not execute workspace changes directly.
Project mode controls a loop outside the model.
Every proposed task must be small, bounded, independently verifiable, and narrower than the whole project.
Every proposed task must include doneCriteria and outOfScope.
Never propose one task that completes the entire project unless the project has exactly one remaining narrow criterion.
''';
