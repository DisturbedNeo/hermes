import 'dart:convert';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/planning_protocol.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/project_system/project_planning_gateway.dart';
import 'package:hermes/core/services/project_system/project_planning_tool_call_runner.dart';
import 'package:hermes/core/services/project_system/project_planning_tools.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';
import 'package:hermes/core/services/project_system/project_view_service.dart';
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
        ProjectIncrementalPlanResult,
        ProjectIncrementalPlanningGateway,
        ProjectPlanningGateway;

class ProjectModelCalls
    implements
        ProjectPlanningGateway,
        ProjectIncrementalPlanningGateway,
        PlanningProtocolConfigurable {
  ProjectModelCalls({
    required ToolService toolService,
    ProjectViewService projectViewService = const ProjectViewService(),
  }) : _creationRunner = FinalizerToolCallRunner(toolService: toolService),
       _projectViewService = projectViewService,
       _planningRunner = const ProjectPlanningToolCallRunner();

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');
  final FinalizerToolCallRunner _creationRunner;
  final ProjectViewService _projectViewService;
  final ProjectPlanningToolCallRunner _planningRunner;
  @override
  PlanningProtocolMode planningProtocolMode = PlanningProtocolMode.automatic;

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
      if (planningProtocolMode == PlanningProtocolMode.legacy) {
        final json = await _completeFinalizedJson(
          client: client,
          workspace: workspace,
          label: 'Project Initial Planning (legacy compatibility)',
          system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
          expectedShape:
              '{"title":"...","refinedGoal":"...","criteria":[],"constraints":[],"memory":[],"milestones":[],"openQuestions":[],"tasks":[]}',
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
Create the initial project plan for this user goal. Use the supplied
workspace profile as the complete discovery input and do not execute work.

Original project goal:
$originalGoal

Authoritative workspace metadata:
${_encoder.convert(workspaceMetadata)}
''',
        );
        return _initialisationFromJson(json, originalGoal: originalGoal);
      }
      return await _completeInitialPlanning(
        client: client,
        baseSystemPrompt: baseSystemPrompt,
        workspace: workspace,
        originalGoal: originalGoal,
        workspaceMetadata: workspaceMetadata,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
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
  Future<ProjectInitialisation?> repairInitialisation({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    required ProjectInitialisation initialisation,
    required List<Map<String, String>> validationIssues,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeFinalizedJson(
        client: client,
        workspace: workspace,
        label: 'Project Initializer Repair',
        system: '$baseSystemPrompt\n\n$_projectJsonSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"title":"...","refinedGoal":"...","criteria":[],"constraints":[],"memory":[],"milestones":[],"openQuestions":[],"tasks":[]}',
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
Repair or replan this initial project plan. Resolve every structured validation issue without inventing workspace state. This may be retried automatically when the repaired plan still fails validation, so return a complete replacement plan rather than a partial patch.
The supplied workspace profile is authoritative: a component absent from its tree is absent, not undiscovered or stale. A readPath may name an absent path only when a declared dependency produces it through writePaths or expectedArtifacts.
Preserve the user's original outcome separately from the refined planning interpretation. Do not execute work.
Model-authored memory is advisory. Include sourceId such as workspace:Design.md for claims derived from supplied files.

Validation issues:
${_encoder.convert(validationIssues)}

Invalid initial plan:
${_encoder.convert(_initialisationToMap(initialisation))}

Authoritative workspace metadata:
${_encoder.convert(workspaceMetadata)}

Original project goal:
$originalGoal
''',
      );
      return _initialisationFromJson(json, originalGoal: originalGoal);
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ProjectDesiredPlan> revisePlan({
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
            '{"summary":"...","rationale":"...","assumptions":[],"criteria":[],"milestones":[],"tasks":[],"deferredTaskIds":[],"obsoleteTaskIds":[],"memoryAdditions":[],"memorySupersessions":[],"openQuestions":[],"requiresApproval":false,"approvalReason":""}',
        user:
            '''
Propose one coherent revision to the rolling project plan for all supplied triggers.
Do not execute work. Preserve completed task history, accepted evidence, gate results, recovery incidents, and protected user memory.
The original goal is the authoritative user request; the refined goal is a separate planning interpretation and must not overwrite it. Treat the supplied discovery snapshot as authoritative for current workspace state.
    Criterion status and evidence are evaluator-owned progress state. Return the complete desired criterion definitions without changing evaluator-owned status.
    Return the complete desired set of active and non-terminal bounded tasks. Use stable existing IDs for updates and new unique IDs for additions. Completed, failed, running, and recovery history is preserved by the reconciler.
    Criteria, milestones, and tasks are complete collections: always include each field, including an explicit empty array when that collection should be cleared. Omitted or malformed collection fields are treated as unavailable and preserve the current planner-visible state.
For every small task that will modify workspace files, writePaths must contain the explicit files or directories it may change. Leave writePaths empty only for genuinely read-only work.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable next task/order and record the assumption in memoryAdditions.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
    Include sourceId such as workspace:Design.md on memory derived from supplied files. If confirmed workspace evidence contradicts active inferred planner memory, supersede each conflicting entry through memorySupersessions.

Return only JSON:
{
      "summary": "...", "rationale": "...", "assumptions": [],
      "criteria": [], "milestones": [], "tasks": [],
  "deferredTaskIds": [], "obsoleteTaskIds": [],
  "memoryAdditions": [], "memorySupersessions": [],
  "openQuestions": [], "requiresApproval": false, "approvalReason": ""
}

Revision triggers:
${_encoder.convert(triggers.map((item) => item.name).toList())}

Bounded discovery snapshot:
${_encoder.convert(evidenceSnapshot.toMap())}

Compact project view:
${_encoder.convert(_projectViewService.query(project))}
''',
      );
      return _proposalFromJson(json, project: project, triggers: triggers);
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (_) {
      return ProjectDesiredPlan(
        revision: project.nextRevision,
        triggers: triggers,
        summary: 'No safe plan revision was produced.',
        rationale: 'The planning call failed without a valid proposal.',
        hasCompleteCollections: false,
        createdAt: DateTime.now(),
      );
    }
  }

  @override
  Future<ProjectIncrementalPlanResult> revisePlanWithCommands({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    required ProjectPlanApprovalPolicy approvalPolicy,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final context = ProjectPlanningContext(
      project: project,
      workspaceRoot: workspace.rootPath,
      triggers: triggers,
      summary: 'Apply the focused project plan revision.',
      rationale:
          'Keep completed history intact and change only what is needed.',
      approvalPolicy: approvalPolicy,
    );
    final registry = ProjectPlanningToolRegistry(context: context);
    try {
      final result = await _planningRunner.complete(
        client: client,
        registry: registry,
        label: 'Incremental Project Plan Revision',
        system:
            '''
$baseSystemPrompt

You are the project plan revision agent. Use the project planning tools to
make a small, explicit update to the existing plan and finish by calling
plan_commit. Do not return a plan as JSON text and do not invent persistent
IDs, statuses, timestamps, evidence, gates, or runtime state.

Begin with project_view when you need context. The view is bounded; request a
specific task, criterion, or memory detail when needed. Use
plan_update_task for an existing mutable task. Use plan_add_tasks for new
work; the builder generates fresh IDs. Completed, failed, split, rejected,
cancelled, and running task history is immutable. Use plan_retry_task only for
failed or rejected work, use plan_split_task only for a mutable oversized task,
and use plan_add_tasks for focused work around terminal history. Use
plan_set_dependency to make ordering changes and plan_set_disposition only
when deferral or obsolescence is justified. Add focused checks, notes, or a
blocking user decision only when they are needed.

Make the smallest safe diff that addresses all supplied triggers. Preserve
the original goal, accepted evidence, protected memory, and completed work.
Use plan_preview if it helps inspect the diff or validation before the final
plan_commit. A successful plan_commit is the only completion signal.
''',
        user:
            '''
Revision triggers:
${_encoder.convert(triggers.map((item) => item.name).toList())}

Bounded discovery snapshot:
${_encoder.convert(evidenceSnapshot.toMap())}

Current bounded project view:
${_encoder.convert(_projectViewService.query(project))}
''',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      return _incrementalPlanResult(
        context,
        result,
        workspaceRoot: workspace.rootPath,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (error) {
      return _incrementalFailure(
        project,
        'Incremental plan revision failed: $error',
      );
    }
  }

  @override
  Future<ProjectIncrementalPlanResult> splitTaskWithCommands({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required Task oversizedTask,
    required List<String> violations,
    required ProjectPlanApprovalPolicy approvalPolicy,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final context = ProjectPlanningContext(
      project: project,
      workspaceRoot: workspace.rootPath,
      triggers: const [ProjectPlanRevisionTrigger.taskReplanRequested],
      summary: 'Split an invalid project task into bounded work.',
      rationale:
          'Replace one unsafe task with smaller independently executable tasks.',
      approvalPolicy: approvalPolicy,
    );
    final registry = ProjectPlanningToolRegistry(context: context);
    try {
      final result = await _planningRunner.complete(
        client: client,
        registry: registry,
        label: 'Incremental Project Task Split',
        system:
            '''
$baseSystemPrompt

You are the project task-splitting agent. Inspect the supplied task with
project_view and call plan_split_task exactly once with 2 to 5 bounded child
tasks, then call plan_commit. Do not return JSON text. Do not reuse the
parent's ID or supply IDs, statuses, timestamps, evidence, gates, or runtime
fields. The builder creates fresh child IDs, preserves the invalid parent as
split history, and validates all criterion and dependency references.

Each child must have one clear objective, explicit done_criteria,
out_of_scope, read_paths, write_paths, and any required expected_artifacts.
Keep the children small enough to execute independently and address every
reported violation. A successful plan_commit is the only completion signal.
''',
        user:
            '''
Task to split: ${oversizedTask.id}
Task title: ${oversizedTask.title}

Validation violations:
${_encoder.convert(violations)}

Current bounded project view:
${_encoder.convert(_projectViewService.query(project, taskRef: oversizedTask.id))}
''',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      return _incrementalPlanResult(
        context,
        result,
        workspaceRoot: workspace.rootPath,
        splitTaskId: oversizedTask.id,
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (error) {
      return _incrementalFailure(
        project,
        'Incremental task split failed: $error',
      );
    }
  }

  Future<ProjectIncrementalPlanResult> _incrementalPlanResult(
    ProjectPlanningContext context,
    Map<String, dynamic> result, {
    required String workspaceRoot,
    String? splitTaskId,
  }) async {
    final legacy = _legacyPlanMap(result);
    if (legacy != null &&
        planningProtocolMode == PlanningProtocolMode.automatic) {
      final proposal = _proposalFromJson(
        legacy,
        project: context.project,
        triggers: context.builder.triggers,
      );
      final applied = await const ProjectPlanRevisionService().prepareAndApply(
        project: context.project,
        proposal: proposal,
        workspaceRoot: workspaceRoot,
        approvalPolicy: context.approvalPolicy,
        splitTaskIds: splitTaskId == null ? const [] : [splitTaskId],
      );
      final planningMetrics = _planningMetricsFromResult(result);
      if (applied.validation.valid) {
        return ProjectIncrementalPlanResult(
          project: applied.project,
          committed: true,
          changed: applied.changed,
          awaitingApproval: applied.awaitingApproval,
          modelCalls:
              (result['model_calls'] as num?)?.toInt() ??
              planningMetrics.planningCalls,
          planningMetrics: planningMetrics,
        );
      }
      return _incrementalFailure(
        applied.project,
        applied.project.blocker?.message ??
            'The compatibility plan did not pass validation.',
        planningMetrics: planningMetrics.copyWith(
          validationBlockerCount: planningMetrics.validationBlockerCount + 1,
        ),
      );
    }
    final committed = context.committedProject;
    if (committed != null && context.closed && result['ok'] == true) {
      return ProjectIncrementalPlanResult(
        project: committed,
        committed: true,
        changed: result['changed'] == true,
        awaitingApproval: result['awaiting_approval'] == true,
        modelCalls: (result['model_calls'] as num?)?.toInt() ?? 1,
        planningMetrics: _planningMetricsFromResult(result),
      );
    }
    final code = result['code']?.toString().trim();
    final message = result['message']?.toString().trim();
    return _incrementalFailure(
      context.project,
      [
        if (code != null && code.isNotEmpty) '$code:',
        if (message != null && message.isNotEmpty) message,
        if ((code == null || code.isEmpty) &&
            (message == null || message.isEmpty))
          'The planner did not commit an incremental plan.',
      ].join(' '),
      planningMetrics: _planningMetricsFromResult(result),
    );
  }

  ProjectIncrementalPlanResult _incrementalFailure(
    ProjectState project,
    String error, {
    PlanningMetrics planningMetrics = const PlanningMetrics(),
  }) => ProjectIncrementalPlanResult(
    project: project,
    committed: false,
    changed: false,
    awaitingApproval: false,
    modelCalls: 1,
    planningMetrics: planningMetrics,
    error: error,
  );

  PlanningMetrics _planningMetricsFromResult(Map<String, dynamic> result) {
    final raw = result['planning_metrics'];
    if (raw is! Map) return const PlanningMetrics();
    try {
      return ModelJson.decode<PlanningMetrics>(Map<String, dynamic>.from(raw));
    } catch (_) {
      return const PlanningMetrics();
    }
  }

  Map<String, dynamic>? _legacyPlanMap(Map<String, dynamic> result) {
    final raw = result['legacy_finalizer'] == true
        ? result['arguments']
        : result['legacy_json'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  @override
  Future<ProjectDesiredPlan?> repairPlanProposal({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectDesiredPlan proposal,
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
            '{"summary":"...","rationale":"...","criteria":[],"milestones":[],"tasks":[],"deferredTaskIds":[],"obsoleteTaskIds":[],"openQuestions":[]}',
        user:
            '''
Repair or replan the proposed plan so every structured validation issue is resolved. This may be retried automatically when the repaired plan still fails validation, so return a complete replacement plan rather than a partial patch.
Preserve its intent and revision number. Do not execute work or mutate immutable history.

Validation issues:
${_encoder.convert(validationIssues)}

Invalid proposal:
${_encoder.convert(ModelJson.encode(proposal))}

Compact authoritative project view:
${_encoder.convert(_projectViewService.query(project))}
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
  Future<List<Task>> splitTask({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    required Task oversizedTask,
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
            '{"tasks":[{"title":"...","objective":"...","criterionIds":["criterion_001"],"doneCriteria":["..."],"outOfScope":["..."],"context":["..."],"expectedArtifacts":[]}]}',
        user:
            '''
Split this oversized or invalid project task into 2 to 5 smaller bounded tasks.

Return only JSON:
{
  "tasks": [
    {
      "title": "...",
      "objective": "one small bounded task",
      "criterionIds": ["criterion_001"],
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

Allowed criterion IDs and exact statements:
${_encoder.convert({for (final criterion in project.criteria) criterion.id: criterion.statement})}

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
            '{"complete":false,"finalSummary":"...","remainingCriteria":["..."],"supportedCriterionIds":["criterion_001"],"openQuestions":[{"question":"..."}]}',
        user:
            '''
Perform one bounded semantic review of the unresolved Project criteria and their persisted evidence.
Task completion alone is not evidence that a criterion is satisfied. Treat proposed task claims as advisory. List every criterion that still lacks adequate evidence in remainingCriteria, and list criterion IDs with credible partial support in supportedCriterionIds.
Only include a criterion in supportedCriterionIds when persisted proposed or accepted evidence provides meaningful support beyond merely reporting that work was attempted. Do not include deterministic criteria unless their deterministic evidence is present; do not include evidence that is only advisory.
Set complete only when every required criterion is adequately supported. Your decision will be persisted as an evidence-review rationale.
Do not add openQuestions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences.
Add openQuestions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "complete": false,
  "finalSummary": "...",
  "remainingCriteria": ["..."],
  "supportedCriterionIds": ["criterion_001"],
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
        supportedCriterionIds: jsonStringList(
          json['supportedCriterionIds'] ?? json['supported_criterion_ids'],
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
        remainingCriteria: project.criteria
            .map((item) => item.statement)
            .toList(),
        supportedCriterionIds: const [],
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

  Future<ProjectInitialisation> _completeInitialPlanning({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    String additionalInstruction = '',
  }) async {
    final now = DateTime.now();
    final context = ProjectPlanningContext(
      project: _initialPlanningSeed(originalGoal, now),
      workspaceRoot: workspace.rootPath,
      now: now,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
      summary: 'Create the initial project roadmap.',
      rationale:
          'Create a bounded, executable plan from the supplied goal and workspace profile.',
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      includeProjectDetails: true,
    );
    final result = await _planningRunner.complete(
      client: client,
      registry: registry,
      label: 'Project Initial Planning',
      system:
          '''
$baseSystemPrompt

You are planning a new project through explicit planning commands. Do not return a complete project JSON document and do not execute workspace changes. The planning registry is the only tool surface available.
Tool arguments must follow their schemas, but the plan itself must be built through tool calls rather than returned as a large JSON document.
Use plan_set_project_details first to set a concise title, a useful refined goal, and the constraints that must remain true. Add one or more success criteria with plan_add_criteria. Milestones are optional; add one or more with plan_add_milestones when they clarify delivery, otherwise Hermes will create a default milestone for executable work.
Use plan_add_tasks for a small batch of bounded near-term tasks, normally no more than seven queued tasks. Each task needs an objective or title, at least one criterion reference, done criteria, and an explicit out-of-scope boundary. Use temporary refs such as scaffold and verify to link tasks and dependencies; Hermes generates canonical IDs.
Add command checks with plan_add_check when a task needs verification. Add notes with plan_add_note for sourced facts, assumptions, risks, or decisions. Ask a user decision only for genuinely irreversible, high-risk, credential, scope, or otherwise unsafe-to-assume ambiguity.
Use project_view when you need a bounded summary or detail. Use plan_preview to inspect the compact diff, then call plan_commit when the plan is complete. Do not supply IDs, statuses, timestamps, revisions, gates, evidence IDs, or runtime execution fields.
'''
              .trim(),
      user:
          '''
Create the initial project plan for this user goal.

Original user goal:
$originalGoal

Bounded workspace profile:
${_encoder.convert(_compactWorkspaceMetadata(workspaceMetadata))}
${additionalInstruction.trim().isEmpty ? '' : '\n\n$additionalInstruction'}
''',
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final legacy = _legacyPlanMap(result);
    if (legacy != null &&
        planningProtocolMode == PlanningProtocolMode.automatic) {
      return _initialisationFromJson(
        legacy,
        originalGoal: originalGoal,
        planningMetrics: _planningMetricsFromResult(result),
      );
    }
    if (result['ok'] != true || context.committedProposal == null) {
      throw FormatException(
        'Initial planning did not commit a valid draft: ${result['message'] ?? result['code'] ?? 'unknown error'}.',
      );
    }
    return _initialisationFromPlanningContext(
      context,
      context.committedProposal!,
      originalGoal: originalGoal,
      planningMetrics: _planningMetricsFromResult(result),
    );
  }

  ProjectState _initialPlanningSeed(String originalGoal, DateTime now) =>
      ProjectState(
        id: 'planning_${uuid.v7()}',
        title: _titleFromGoal(originalGoal),
        originalGoal: originalGoal,
        refinedGoal: originalGoal,
        criteria: const [],
        constraints: const ['Stay within the attached workspace.'],
        tasks: const [],
        milestones: const [],
        memory: const [],
        planHistory: const [],
        status: ProjectStatus.active,
        activeTaskId: null,
        createdAt: now,
        updatedAt: now,
      );

  ProjectInitialisation _initialisationFromPlanningContext(
    ProjectPlanningContext context,
    ProjectDesiredPlan proposal, {
    required String originalGoal,
    PlanningMetrics planningMetrics = const PlanningMetrics(),
  }) {
    var milestones = proposal.milestones;
    if (proposal.tasks.isNotEmpty && milestones.isEmpty) {
      final now = DateTime.now();
      milestones = [
        ProjectMilestone(
          id: 'milestone_${uuid.v7()}',
          title: 'Deliver the project outcome',
          objective: context.draftRefinedGoal,
          criterionIds: proposal.criteria.map((item) => item.id).toList(),
          status: ProjectMilestoneStatus.active,
          exitConditions: proposal.criteria
              .map((item) => item.statement)
              .toList(),
          order: 1,
          createdAt: now,
          updatedAt: now,
        ),
      ];
    }
    final defaultMilestoneId = milestones.firstOrNull?.id;
    final tasks = [
      for (final task in proposal.tasks)
        task.copyWith(milestoneId: task.milestoneId ?? defaultMilestoneId),
    ];
    return ProjectInitialisation(
      title: context.draftTitle.trim().isEmpty
          ? _titleFromGoal(originalGoal)
          : context.draftTitle,
      refinedGoal: context.draftRefinedGoal.trim().isEmpty
          ? originalGoal
          : context.draftRefinedGoal,
      criteria: proposal.criteria,
      constraints: context.draftConstraints,
      openQuestions: proposal.openQuestions,
      tasks: tasks,
      milestones: milestones,
      memory: proposal.memoryAdditions,
      planningMetrics: planningMetrics,
    );
  }

  Map<String, dynamic> _compactWorkspaceMetadata(
    Map<String, dynamic> metadata,
  ) {
    final profile = metadata['workspaceProfile'];
    if (profile is! Map) return metadata;
    final profileMap = Map<String, dynamic>.from(profile);
    List<String> strings(Object? value, {int limit = 80}) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ].take(limit).toList();
    final excerpts = <Map<String, dynamic>>[];
    final rawFiles = profileMap['highSignalFiles'];
    if (rawFiles is List) {
      for (final raw in rawFiles.take(8)) {
        if (raw is! Map) continue;
        final file = Map<String, dynamic>.from(raw);
        final content = file['content']?.toString() ?? '';
        excerpts.add({
          'path': file['path']?.toString() ?? '',
          'content': _boundedText(content, 2400),
          'truncated': file['truncated'] == true || content.length > 2400,
        });
      }
    }
    return {
      'workspaceName': metadata['workspaceName'],
      'commandExecutionApproved': metadata['commandExecutionApproved'],
      'rootEntries': strings(metadata['rootEntries']),
      'gitAvailable': metadata['gitAvailable'] == true,
      'changedFiles': strings(metadata['changedFiles']),
      'treePaths': strings(profileMap['treePaths'], limit: 200),
      'highSignalFiles': excerpts,
      'packageName': profileMap['packageName'],
      'scripts': profileMap['scripts'],
      'dependencies': strings(profileMap['dependencies']),
      'languages': strings(profileMap['languages']),
      'frameworks': strings(profileMap['frameworks']),
      'treeTruncated': profileMap['treeTruncated'] == true,
      'contentTruncated': profileMap['contentTruncated'] == true,
      'omittedPathCount': profileMap['omittedPathCount'],
    };
  }

  static String _boundedText(String value, int limit) {
    final text = value.trim();
    if (text.length <= limit) return text;
    return '${text.substring(0, limit - 1).trimRight()}…';
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

  ProjectInitialisation _initialisationFromJson(
    Map<String, dynamic> json, {
    required String originalGoal,
    PlanningMetrics planningMetrics = const PlanningMetrics(),
  }) {
    final refinedGoal = jsonString(
      json['refinedGoal'] ?? json['refined_goal'],
      fallback: originalGoal,
    );
    final structuredCriteria = _criteriaFromJson(json['criteria']);
    return ProjectInitialisation(
      title: jsonString(json['title'], fallback: _titleFromGoal(originalGoal)),
      refinedGoal: refinedGoal,
      criteria: structuredCriteria,
      constraints: jsonStringList(json['constraints']),
      openQuestions: _questionsFromJson(
        json['openQuestions'] ?? json['open_questions'],
      ),
      tasks: _bindTasksToCriteria(
        _tasksFromJson(json['tasks']),
        structuredCriteria,
      ),
      milestones: _milestonesFromJson(json['milestones']),
      memory: _memoryFromJson(json['memory']),
      planningMetrics: planningMetrics,
    );
  }

  Map<String, dynamic> _initialisationToMap(ProjectInitialisation value) => {
    'title': value.title,
    'refinedGoal': value.refinedGoal,
    'criteria': value.criteria.map(ModelJson.encode).toList(),
    'constraints': value.constraints,
    'openQuestions': value.openQuestions.map(ModelJson.encode).toList(),
    'tasks': value.tasks.map(ModelJson.encode).toList(),
    'milestones': value.milestones.map(ModelJson.encode).toList(),
    'memory': value.memory.map(ModelJson.encode).toList(),
  };

  ProjectInitialisation _fallbackInitialisation(String originalGoal) {
    return ProjectInitialisation(
      title: _titleFromGoal(originalGoal),
      refinedGoal: originalGoal,
      criteria: [
        ProjectCriterion(
          id: 'criterion_001',
          statement: 'Complete the stated project goal.',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      constraints: const ['Stay within the attached workspace.'],
      openQuestions: const [],
      tasks: const [],
    );
  }

  List<Task> _tasksFromJson(Object? value) {
    if (value is! List) return const [];
    final tasks = <Task>[];
    for (var i = 0; i < value.length; i++) {
      final raw = value[i];
      if (raw is! Map) continue;
      tasks.add(_taskFromMap(Map<String, dynamic>.from(raw), i));
    }
    return tasks;
  }

  Task _taskFromMap(Map<String, dynamic> map, int index) {
    map['id'] = jsonString(
      map['id'],
      fallback: 'project_task_${index + 1}_${uuid.v7()}',
    );
    map['status'] ??= TaskStatus.queued.wire;
    final task = ModelJson.decode<Task>(map);
    final expectedEvidence = task.expectedEvidence.isEmpty
        ? [
            TaskEvidenceExpectation(
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
      fingerprint: projectTaskFingerprint(task.objective, task.criterionIds),
    );
  }

  ProjectDesiredPlan _proposalFromJson(
    Map<String, dynamic> json, {
    required ProjectState project,
    required List<ProjectPlanRevisionTrigger> triggers,
  }) {
    final criteriaValue = json['criteria'];
    final criteriaComplete =
        criteriaValue is List && criteriaValue.every((item) => item is Map);
    final criteria = criteriaComplete
        ? _criteriaFromJson(json['criteria'])
        : project.criteria;
    final tasksValue = json['tasks'];
    final tasksComplete =
        tasksValue is List && tasksValue.every((item) => item is Map);
    final desiredTasks = tasksComplete
        ? _tasksFromJson(json['tasks'])
        : project.tasks
              .where(
                (task) =>
                    task.status != TaskStatus.completed &&
                    task.status != TaskStatus.failed &&
                    task.status != TaskStatus.rejected &&
                    task.status != TaskStatus.split &&
                    task.status != TaskStatus.cancelled,
              )
              .toList();
    final tasks = _bindTasksToCriteria(desiredTasks, criteria);
    final milestonesValue = json['milestones'];
    final milestonesComplete =
        milestonesValue is List && milestonesValue.every((item) => item is Map);
    final desiredMilestones = milestonesComplete
        ? _milestonesFromJson(json['milestones'])
        : project.milestones;
    final openQuestionsValue = json['openQuestions'] ?? json['open_questions'];
    final openQuestions =
        openQuestionsValue is List &&
            openQuestionsValue.every((item) => item is Map)
        ? _questionsFromJson(openQuestionsValue)
        : project.openQuestions;
    return ProjectDesiredPlan(
      revision: project.nextRevision,
      triggers: triggers.toSet().toList(),
      summary: jsonString(
        json['summary'],
        fallback: 'Revise the rolling plan.',
      ),
      rationale: jsonString(
        json['rationale'],
        fallback: 'Respond to the collected replanning triggers.',
      ),
      hasCompleteCollections:
          criteriaComplete && milestonesComplete && tasksComplete,
      assumptions: jsonStringList(json['assumptions']),
      criteria: criteria,
      milestones: desiredMilestones,
      tasks: tasks,
      // Split metadata is owned by the command builder; legacy JSON cannot
      // request a split by omitting a task from a replacement collection.
      splitTaskIds: const [],
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
      openQuestions: openQuestions,
      requiresApproval: jsonBool(
        json['requiresApproval'] ?? json['requires_approval'],
      ),
      approvalReason: jsonString(
        json['approvalReason'] ?? json['approval_reason'],
      ),
      createdAt: DateTime.now(),
    );
  }

  List<Task> _bindTasksToCriteria(
    List<Task> tasks,
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
              .map(resolveCriterion)
              .whereType<String>()
              .toSet()
              .toList();
          final boundIds = resolved;
          return task.copyWith(
            criterionIds: boundIds,
            expectedEvidence: [
              for (final expectation in task.expectedEvidence)
                TaskEvidenceExpectation(
                  id: expectation.id,
                  type: expectation.type,
                  criterionIds: expectation.criterionIds.isEmpty
                      ? boundIds
                      : expectation.criterionIds
                            .map(resolveCriterion)
                            .whereType<String>()
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
      map['sourceType'] = ProjectMemorySourceType.planner.name;
      map['confidence'] = ProjectMemoryConfidence.inferred.name;
      map['protected'] = false;
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
        'Finalize the complete structured project payload. Call this exactly once after any needed read-only workspace discovery.',
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
        'tasks': {
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
        'constraints': {
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
When revising a plan, return complete criteria, milestone, and task collections; include an explicit empty array when a collection should be cleared.
Never propose one task that completes the entire project unless the project has exactly one remaining narrow criterion.
''';
