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
import 'package:hermes/core/services/project_system/project_planning_gateway.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/finalizer_tool_call_runner.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/tool_service.dart';

export 'package:hermes/core/services/project_system/project_planning_gateway.dart'
    show
        ProjectCompletionAssessment,
        ProjectEvidenceSnapshot,
        ProjectInitialisation,
        ProjectPlanningGateway;

class ProjectModelCalls implements ProjectPlanningGateway {
  ProjectModelCalls({required ToolService toolService})
    : _creationRunner = FinalizerToolCallRunner(toolService: toolService);

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');
  final FinalizerToolCallRunner _creationRunner;

  @override
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
            '{"title":"...","refinedGoal":"...","criteria":[{"id":"criterion_001","statement":"...","required":true,"verificationMode":"mixed"}],"constraints":["..."],"memory":[{"id":"memory_001","kind":"assumption","content":"..."}],"milestones":[{"id":"milestone_001","title":"...","objective":"...","criterionIds":["criterion_001"],"exitConditions":["..."],"order":1}],"openQuestions":[],"backlog":[{"id":"project_task_001","title":"...","objective":"...","criterionIds":["criterion_001"],"milestoneId":"milestone_001","doneCriteria":["..."],"outOfScope":["..."],"expectedEvidence":[{"id":"evidence_001","type":"task_claim","criterionIds":["criterion_001"],"description":"..."}]}]}',
        finalizerTool: _finaliseProjectCreationToolDefinition(
          requiredProperties: const [
            'title',
            'refinedGoal',
            'criteria',
            'constraints',
          ],
        ),
        user:
            '''
Initialize a persistent project state. Do not execute the project.
Create a rolling roadmap with one to three milestones and approximately three to seven detailed near-term tasks. Keep distant work coarse in milestone objectives rather than expanding an unbounded backlog.
Every task needs stable IDs, dependencies, criterion and milestone links, priority, risk, effort, boundaries, expected evidence, and a concise rationale in selectionRationale.
For every small task that will modify workspace files, writePaths must contain the explicit files or directories it may change. Leave writePaths empty only for genuinely read-only work.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; record a typed assumption in memory instead.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "title": "...",
  "refinedGoal": "...",
  "criteria": [{"id":"criterion_001","statement":"...","required":true,"verificationMode":"mixed"}],
  "constraints": ["..."],
  "memory": [{"id":"memory_001","kind":"fact|assumption|requirement|decision|risk","content":"...","confidence":"confirmed|inferred|uncertain"}],
  "milestones": [{"id":"milestone_001","title":"...","objective":"...","criterionIds":["criterion_001"],"exitConditions":["..."],"order":1}],
  "openQuestions": [{"question": "..."}],
  "backlog": [{"id":"project_task_001","title":"...","objective":"one bounded task","criterionIds":["criterion_001"],"milestoneId":"milestone_001","dependsOnTaskIds":[],"priority":"normal","risk":"low","riskReduction":"low","effort":"small","doneCriteria":["..."],"outOfScope":["..."],"expectedEvidence":[{"id":"expectation_001","type":"task_claim","criterionIds":["criterion_001"],"description":"...","required":true}],"readPaths":[],"writePaths":[],"selectionRationale":"..."}]
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
      final structuredCriteria = _criteriaFromJson(json['criteria']);
      final fallbackCriteria = structuredCriteria.isEmpty
          ? [
              for (var index = 0; index < criteria.length; index++)
                ProjectCriterion(
                  id: 'criterion_${(index + 1).toString().padLeft(3, '0')}',
                  statement: criteria[index],
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
            ]
          : structuredCriteria;
      return ProjectInitialisation(
        title: jsonString(
          json['title'],
          fallback: _titleFromGoal(originalGoal),
        ),
        refinedGoal: refinedGoal,
        successCriteria: structuredCriteria.isNotEmpty
            ? structuredCriteria.map((item) => item.statement).toList()
            : criteria.isEmpty
            ? ['Complete the stated project goal.']
            : criteria,
        constraints: jsonStringList(json['constraints']).isEmpty
            ? ['Stay within the attached workspace.']
            : jsonStringList(json['constraints']),
        knownFacts: jsonStringList(json['knownFacts'] ?? json['known_facts']),
        openQuestions: _questionsFromJson(
          json['openQuestions'] ?? json['open_questions'],
        ),
        backlog: _bindTasksToCriteria(
          _tasksFromJson(json['backlog']),
          fallbackCriteria,
        ),
        criteria: structuredCriteria,
        milestones: _milestonesFromJson(json['milestones']),
        memory: _memoryFromJson(json['memory']),
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return _fallbackInitialisation(originalGoal);
    }
  }

  @override
  Future<ProjectPlanProposal> revisePlan({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Plan Revision',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"summary":"...","rationale":"...","assumptions":[],"criterionUpserts":[],"removedCriterionIds":[],"milestoneUpserts":[],"removedMilestoneIds":[],"taskAdditions":[],"taskUpdates":[],"deferredTaskIds":[],"obsoleteTaskIds":[],"memoryAdditions":[],"memorySupersessions":[],"openQuestions":[],"requiresApproval":false,"approvalReason":""}',
        user:
            '''
Propose one coherent revision to the rolling project plan for all supplied triggers.
Do not execute work. Preserve completed task history, accepted evidence, gate results, recovery incidents, and protected user memory.
Criterion status and evidence are evaluator-owned progress state. Do not use criterionUpserts merely to mark an existing criterion satisfied, partial, or unsatisfied, or to attach evidence; only upsert a criterion when its statement, required flag, or verification mode must change.
Return only small, bounded, independently verifiable near-term tasks. Use stable existing IDs for updates and new unique IDs for additions.
For every small task that will modify workspace files, writePaths must contain the explicit files or directories it may change. Leave writePaths empty only for genuinely read-only work.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable next task/order and record the assumption in memoryAdditions.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "summary": "...", "rationale": "...", "assumptions": [],
  "criterionUpserts": [], "removedCriterionIds": [],
  "milestoneUpserts": [], "removedMilestoneIds": [],
  "taskAdditions": [], "taskUpdates": [],
  "deferredTaskIds": [], "obsoleteTaskIds": [],
  "memoryAdditions": [], "memorySupersessions": [],
  "openQuestions": [], "requiresApproval": false, "approvalReason": ""
}

Revision triggers:
${_encoder.convert(triggers.map((item) => item.name).toList())}

Bounded discovery snapshot:
${_encoder.convert(evidenceSnapshot.toMap())}

Project state:
${_encoder.convert(ModelJson.encode(project))}
''',
      );
      return _proposalFromJson(json, project: project, triggers: triggers);
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return ProjectPlanProposal(
        revision: project.currentRevision + 1,
        triggers: triggers,
        summary: 'No safe plan revision was produced.',
        rationale: 'The planning call failed without a valid proposal.',
        createdAt: DateTime.now(),
      );
    }
  }

  @override
  Future<ProjectPlanProposal?> repairPlanProposal({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectPlanProposal proposal,
    required List<Map<String, String>> validationIssues,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Plan Repair',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"summary":"...","rationale":"...","taskAdditions":[],"taskUpdates":[],"deferredTaskIds":[],"obsoleteTaskIds":[]}',
        user:
            '''
Repair the proposed plan exactly once so every structured validation issue is resolved.
Preserve its intent and revision number. Do not execute work or mutate immutable history.

Validation issues:
${_encoder.convert(validationIssues)}

Invalid proposal:
${_encoder.convert(ModelJson.encode(proposal))}

Authoritative project state:
${_encoder.convert(ModelJson.encode(project))}
''',
      );
      return _proposalFromJson(
        json,
        project: project,
        triggers: proposal.triggers,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  @override
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
      "readPaths": ["..."],
      "writePaths": ["..."],
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
      return _bindTasksToCriteria(
        _tasksFromJson(json['tasks']),
        project.criteria,
      ).take(5).toList();
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  @override
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
Perform one bounded semantic review of the unresolved Project criteria and their persisted evidence.
Task completion alone is not evidence that a criterion is satisfied. Treat proposed task claims as advisory, inspect accepted gates and artifacts, and list every criterion that still lacks adequate evidence in remainingCriteria.
Set complete only when every required criterion is adequately supported. Your decision will be persisted as an evidence-review rationale.
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

Use the supplied bounded workspace profile as the complete discovery input.
Do not call tools or perform a second workspace exploration during project creation.
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
      allowReadOnlyTools: false,
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
      diagnosticsLabel: label,
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
      fallback: 'project_task_${index + 1}_${uuid.v7()}',
    );
    map['status'] ??= ProjectTaskStatus.queued.wire;
    final task = ModelJson.decode<ProjectTask>(map);
    final expectedEvidence = task.expectedEvidence.isEmpty
        ? [
            ProjectEvidenceExpectation(
              id: 'expect_${task.id}',
              type: ProjectEvidenceType.taskClaim,
              criterionIds: task.criterionIds,
              description: task.doneCriteria.isEmpty
                  ? 'The bounded task result is independently verified.'
                  : task.doneCriteria.join(' '),
            ),
          ]
        : task.expectedEvidence;
    return task.copyWith(
      expectedEvidence: expectedEvidence,
      fingerprint: projectTaskFingerprint(
        task.objective,
        task.relevantSuccessCriteria,
      ),
    );
  }

  ProjectPlanProposal _proposalFromJson(
    Map<String, dynamic> json, {
    required ProjectState project,
    required List<ProjectPlanRevisionTrigger> triggers,
  }) {
    final rawTaskAdditions =
        json['taskAdditions'] ??
        json['task_additions'] ??
        (json['task'] is Map ? [json['task']] : null);
    final criterionUpserts = _criteriaFromJson(
      json['criterionUpserts'] ?? json['criterion_upserts'],
    );
    final removedCriterionIds = jsonStringList(
      json['removedCriterionIds'] ?? json['removed_criterion_ids'],
    );
    final availableCriteria = <String, ProjectCriterion>{
      for (final criterion in project.criteria) criterion.id: criterion,
      for (final criterion in criterionUpserts) criterion.id: criterion,
    }..removeWhere((id, _) => removedCriterionIds.contains(id));
    return ProjectPlanProposal(
      revision: project.currentRevision + 1,
      triggers: triggers.toSet().toList(),
      summary: jsonString(
        json['summary'],
        fallback: 'Revise the rolling plan.',
      ),
      rationale: jsonString(
        json['rationale'],
        fallback: 'Respond to the collected replanning triggers.',
      ),
      assumptions: jsonStringList(json['assumptions']),
      criterionUpserts: criterionUpserts,
      removedCriterionIds: removedCriterionIds,
      milestoneUpserts: _milestonesFromJson(
        json['milestoneUpserts'] ?? json['milestone_upserts'],
      ),
      removedMilestoneIds: jsonStringList(
        json['removedMilestoneIds'] ?? json['removed_milestone_ids'],
      ),
      taskAdditions: _bindTasksToCriteria(
        _tasksFromJson(rawTaskAdditions),
        availableCriteria.values,
      ),
      taskUpdates: _bindTasksToCriteria(
        _tasksFromJson(json['taskUpdates'] ?? json['task_updates']),
        availableCriteria.values,
      ),
      deferredTaskIds: jsonStringList(
        json['deferredTaskIds'] ?? json['deferred_task_ids'],
      ),
      obsoleteTaskIds: jsonStringList(
        json['obsoleteTaskIds'] ?? json['obsolete_task_ids'],
      ),
      memoryAdditions: _memoryFromJson(
        json['memoryAdditions'] ?? json['memory_additions'],
      ),
      memorySupersessions: _memorySupersessionsFromJson(
        json['memorySupersessions'] ?? json['memory_supersessions'],
      ),
      openQuestions: _questionsFromJson(
        json['openQuestions'] ?? json['open_questions'],
      ),
      requiresApproval: jsonBool(
        json['requiresApproval'] ?? json['requires_approval'],
      ),
      approvalReason: jsonString(
        json['approvalReason'] ?? json['approval_reason'],
      ),
      createdAt: DateTime.now(),
    );
  }

  List<ProjectTask> _bindTasksToCriteria(
    List<ProjectTask> tasks,
    Iterable<ProjectCriterion> criteria,
  ) {
    final available = criteria.toList();
    final criterionIds = available.map((item) => item.id).toSet();
    final byStatement = {
      for (final criterion in available)
        criterion.statement.trim().toLowerCase(): criterion.id,
    };
    String? resolveCriterion(String value) {
      if (criterionIds.contains(value)) return value;
      return byStatement[value.trim().toLowerCase()];
    }

    return [
      for (final task in tasks)
        (() {
          final resolved = task.criterionIds
              .map((value) => resolveCriterion(value) ?? value)
              .toSet()
              .toList();
          final boundIds = resolved;
          return task.copyWith(
            criterionIds: boundIds,
            expectedEvidence: [
              for (final expectation in task.expectedEvidence)
                ProjectEvidenceExpectation(
                  id: expectation.id,
                  type: expectation.type,
                  criterionIds: expectation.criterionIds.isEmpty
                      ? boundIds
                      : expectation.criterionIds
                            .map((value) => resolveCriterion(value) ?? value)
                            .where(boundIds.contains)
                            .toSet()
                            .toList(),
                  description: expectation.description,
                  required: expectation.required,
                  sourceRef: expectation.sourceRef,
                  details: expectation.details,
                ),
            ],
          );
        })(),
    ];
  }

  List<ProjectCriterion> _criteriaFromJson(Object? value) {
    if (value is! List) return const [];
    final now = DateTime.now();
    final criteria = <ProjectCriterion>[];
    for (var index = 0; index < value.length; index++) {
      final raw = value[index];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['id'] = jsonString(
        map['id'],
        fallback: 'criterion_${(index + 1).toString().padLeft(3, '0')}',
      );
      map['statement'] = jsonString(map['statement']);
      map['createdAt'] ??= now.toIso8601String();
      map['updatedAt'] ??= now.toIso8601String();
      criteria.add(ModelJson.decode<ProjectCriterion>(map));
    }
    return criteria;
  }

  List<ProjectMilestone> _milestonesFromJson(Object? value) {
    if (value is! List) return const [];
    final now = DateTime.now();
    final milestones = <ProjectMilestone>[];
    for (var index = 0; index < value.length; index++) {
      final raw = value[index];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['id'] = jsonString(
        map['id'],
        fallback: 'milestone_${(index + 1).toString().padLeft(3, '0')}',
      );
      map['title'] = jsonString(
        map['title'],
        fallback: 'Milestone ${index + 1}',
      );
      map['objective'] = jsonString(map['objective'], fallback: map['title']);
      map['order'] ??= index + 1;
      map['createdAt'] ??= now.toIso8601String();
      map['updatedAt'] ??= now.toIso8601String();
      milestones.add(ModelJson.decode<ProjectMilestone>(map));
    }
    return milestones;
  }

  List<ProjectMemoryEntry> _memoryFromJson(Object? value) {
    if (value is! List) return const [];
    final now = DateTime.now();
    final entries = <ProjectMemoryEntry>[];
    for (var index = 0; index < value.length; index++) {
      final raw = value[index];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['id'] = jsonString(
        map['id'],
        fallback: 'memory_${(index + 1).toString().padLeft(3, '0')}',
      );
      map['content'] = jsonString(map['content']);
      map['sourceType'] ??= ProjectMemorySourceType.planner.name;
      map['confidence'] ??= ProjectMemoryConfidence.inferred.name;
      map['createdAt'] ??= now.toIso8601String();
      map['updatedAt'] ??= now.toIso8601String();
      entries.add(ModelJson.decode<ProjectMemoryEntry>(map));
    }
    return entries;
  }

  List<ProjectMemorySupersession> _memorySupersessionsFromJson(Object? value) {
    if (value is! List) return const [];
    final entries = <ProjectMemorySupersession>[];
    for (final raw in value.whereType<Map>()) {
      final entryId = jsonString(raw['entryId'] ?? raw['entry_id']);
      final replacementId = jsonString(
        raw['supersededById'] ?? raw['superseded_by_id'],
      );
      if (entryId.isEmpty || replacementId.isEmpty) continue;
      entries.add(
        ProjectMemorySupersession(
          entryId: entryId,
          supersededById: replacementId,
        ),
      );
    }
    return entries;
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
        'summary': {'type': 'string'},
        'rationale': {'type': 'string'},
        'criteria': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'memory': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'milestones': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'assumptions': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'criterionUpserts': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'removedCriterionIds': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'milestoneUpserts': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'removedMilestoneIds': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'taskAdditions': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'taskUpdates': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'deferredTaskIds': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'obsoleteTaskIds': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'memoryAdditions': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'memorySupersessions': {
          'type': 'array',
          'items': {'type': 'object'},
        },
        'requiresApproval': {'type': 'boolean'},
        'approvalReason': {'type': 'string'},
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
