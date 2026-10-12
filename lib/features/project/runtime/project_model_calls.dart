import 'dart:convert';

import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_errors.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/task/application/protocol/planning_structured_output.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/project/runtime/project_planning_frontier.dart';
import 'package:hermes/features/project/runtime/project_planning_tools.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/task/application/protocol/question_protocol_adapter.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/core/wire_case.dart';

export 'package:hermes/features/project/runtime/project_planning_gateway.dart'
    show
        ProjectCompletionAssessment,
        ProjectEvidenceSnapshot,
        ProjectIncrementalPlanResult,
        ProjectPlanner,
        ProjectCompletionEvaluator;

class ProjectModelCalls implements ProjectPlanner, ProjectCompletionEvaluator {
  ProjectModelCalls({
    PlanningToolCallRunner planningRunner = const PlanningToolCallRunner(),
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    this.persistProject,
    this.persistProjectWithTasks,
    this.loadTask,
  }) : _planningRunner = planningRunner,
       _structuredOutput = structuredOutput;

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');
  final PlanningToolCallRunner _planningRunner;
  final StructuredPlanningOutputService _structuredOutput;
  final Future<ProjectAggregate> Function(
    String workspaceRoot,
    ProjectAggregate project,
  )?
  persistProject;
  final Future<ProjectAggregate> Function(
    String workspaceRoot,
    ProjectAggregate project,
    Iterable<TaskAggregate> dirtyTasks,
  )?
  persistProjectWithTasks;
  final Future<TaskAggregate?> Function(
    WorkspaceAttachment workspace,
    String taskId,
  )?
  loadTask;

  Future<Map<String, dynamic>> _runPlanning({
    required ModelConversationPort client,
    required PlanningToolRegistry registry,
    required String label,
    required String system,
    required String user,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async => (await _planningRunner.complete(
    PlanningRunRequest(
      client: client,
      registry: registry,
      label: label,
      system: system,
      user: user,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    ),
  )).toMap();

  Map<String, dynamic> _planningFrontier(
    ProjectAggregate project, {
    ProjectEvidenceSnapshot? evidence,
    Iterable<String> triggers = const [],
    ProjectTaskNode? focusedTask,
  }) => ProjectPlanningFrontierBuilder.build(
    project: project,
    evidence: evidence,
    triggers: triggers,
    focusedTask: focusedTask,
  );

  @override
  Future<ProjectIncrementalPlanResult> maintainWorkspaceGraph({
    required ModelConversationPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final context = ProjectPlanningContext(
      project: project,
      workspaceRoot: workspace.rootPath,
      triggers: const [ProjectPlanRevisionTrigger.workspaceGraphMaintenance],
      summary: 'Enrich the workspace graph with supported semantic structure.',
      rationale:
          'Record only durable semantic concepts and relationships supported by the bounded evidence.',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
      planningPass: ProjectPlanningPass.graphMaintenance,
      planningLimits: ProjectPlanningLimits.graphMaintenance,
      persistProject: persistProject,
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      profile: ProjectPlanningToolProfile.graphMaintenance,
    );
    try {
      final result = await _runPlanning(
        client: client,
        registry: registry,
        label: 'Workspace Graph Maintenance',
        system:
            '''
$baseSystemPrompt

You are the dedicated workspace graph-maintenance planner. Enrich only the
workspace context graph using the graph tools and finish with plan_finalize.
This pass is graph-only: do not create, update, split, defer, obsolete, or
otherwise change tasks, criteria, milestones, dependencies, memory, project
details, user questions, or workspace files.

Semantic nodes and relationships must be supported by the supplied bounded
evidence. Add references to relevant workspace paths, URLs, chapters, or
documents whenever the evidence provides them. Do not modify, remove, or
protect managed or protected entries. Do not duplicate graph knowledge into
project memory. Omit concepts and relationships that remain ambiguous.
Workspace orientation is planner-owned and may be refined when the evidence
supports a durable orientation. The frontier contains graph summaries. Use
plan_read for full node or edge detail when needed; never guess omitted graph
metadata. Apply mutations immediately and finish with plan_finalize. A
successful plan_finalize is the only completion signal.
''',
        user:
            '''
Planning frontier:
${_encoder.convert(_planningFrontier(project, evidence: evidenceSnapshot, triggers: const ['workspace_graph_maintenance']))}

Deterministic graph reconciliation:
${_encoder.convert(evidenceSnapshot.workspaceGraphReconciliation?.toMap() ?? const {})}
''',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      return _incrementalPlanResult(context, result);
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      rethrow;
    } catch (error) {
      return _incrementalFailure(
        project,
        'Workspace graph maintenance failed: $error',
      );
    }
  }

  @override
  Future<ProjectIncrementalPlanResult> revisePlanWithCommands({
    required ModelConversationPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    required ProjectPlanApprovalPolicy approvalPolicy,
    ProjectPlanningPass planningPass = ProjectPlanningPass.maintenance,
    ProjectPlanningLimits planningLimits = ProjectPlanningLimits.maintenance,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final canonicalTasks = <String, TaskAggregate>{};
    if (loadTask != null) {
      for (final task in project.tasks) {
        final loaded = await loadTask!(workspace, task.id);
        if (loaded != null) canonicalTasks[task.id] = loaded;
      }
    }
    final context = ProjectPlanningContext(
      project: project,
      workspaceRoot: workspace.rootPath,
      triggers: triggers,
      summary: 'Apply the focused project plan revision.',
      rationale:
          'Keep completed history intact and change only what is needed.',
      approvalPolicy: approvalPolicy,
      planningPass: planningPass,
      planningLimits: planningLimits,
      persistProject: persistProject,
      persistProjectWithTasks: persistProjectWithTasks,
      canonicalTasks: canonicalTasks,
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      profile: planningPass == ProjectPlanningPass.bootstrap
          ? ProjectPlanningToolProfile.bootstrap
          : ProjectPlanningToolProfile.maintenance,
    );
    final planningInstructions = planningPass == ProjectPlanningPass.bootstrap
        ? '''
You are bootstrapping a new project frontier. Establish durable success
criteria, exactly one active milestone, and only the next one to three bounded
tasks that are credible from the supplied evidence. Do not inventory
speculative future work or build a complete roadmap. Use only the supplied
bounded workspace evidence.
'''
        : '''
You are maintaining an existing project frontier. Inspect current evidence and
the supplied triggers, make the smallest safe change, add no more than three
new tasks, and avoid recreating completed work or speculative future work.
''';
    try {
      final result = await _runPlanning(
        client: client,
        registry: registry,
        label: 'Incremental Project Plan Revision',
        system:
            '''
$baseSystemPrompt

You are the project plan revision agent. Use the project planning tools to
make a small, explicit update to the existing plan and finish by calling
plan_finalize. Do not return a plan as JSON text and do not invent persistent
IDs, statuses, timestamps, evidence, gates, or runtime state.

$planningInstructions

The planning frontier contains compact summaries. Omitted task, criterion,
milestone, and graph details are not known; use plan_read before relying on
them or editing them. Use task_add to create a complete bounded
task, task_update for a partial task update, task_remove to obsolete an active
task, and project_update for partial project, criterion, and milestone updates.
Omitted task_update fields stay unchanged. Within task_update, acceptance and
steps entries upsert by ref; remove individual entries with
remove_acceptance_refs or remove_step_refs. Use replace_acceptance or
replace_steps only when intentionally replacing that entire list. Read a task
before editing its steps so you can use the stable step refs shown in its
detail. Each supplied acceptance or step entry is a complete entry. For
project_update, omitted fields stay unchanged, constraints replaces the full
list, and criteria or milestone entries add or update only the referenced
records.
Numeric task, criterion, milestone, and dependency IDs are stable project-local
IDs. Completed, failed, split, rejected, cancelled, and running task history
is immutable.

Make the smallest safe diff that addresses all supplied triggers. Preserve
the original goal, accepted evidence, protected memory, and completed work.
Mutation responses include validation and the normalized persisted state. If a
genuinely blocking project decision is required, call
project_request_user_decision. Finish with plan_finalize. A successful
plan_finalize is the only completion signal.
''',
        user:
            '''
Revision triggers:
${_encoder.convert(triggers.map((item) => item.name).toList())}

Planning frontier:
${_encoder.convert(_planningFrontier(project, evidence: evidenceSnapshot, triggers: triggers.map((item) => item.name)))}
''',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      return _incrementalPlanResult(context, result);
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
    required ModelConversationPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required ProjectTaskNode oversizedTask,
    required List<String> violations,
    required ProjectPlanApprovalPolicy approvalPolicy,
    ProjectPlanningPass planningPass = ProjectPlanningPass.split,
    ProjectPlanningLimits planningLimits = ProjectPlanningLimits.split,
    ModelOutputSink? onModelOutput,
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
      planningPass: planningPass,
      planningLimits: planningLimits,
      persistProject: persistProject,
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      profile: ProjectPlanningToolProfile.split,
    );
    try {
      final result = await _runPlanning(
        client: client,
        registry: registry,
        label: 'Incremental Project Task Split',
        system:
            '''
$baseSystemPrompt

You are the project task-splitting agent. The supplied task is already in
context. Remove the parent with task_remove and add 2 or 3 bounded child tasks
with task_add, then call plan_finalize. Do not return JSON text. Do not reuse the parent's ID or
supply IDs, statuses, timestamps, evidence, gates, or runtime fields. The
builder creates fresh child IDs, preserves the invalid parent as split history,
and validates all criterion, dependency, and verification references. If the
split command reports a validation error, correct the child payload and retry
the split before committing; a failed split is atomic and leaves the draft
unchanged.

Each child must have one clear objective, explicit acceptance, out_of_scope,
read_paths, and write_paths.
Keep the children small enough to execute independently and address every
reported violation. Keep every parent criterion on at least one child. Each
deterministic criterion must be covered by a required child acceptance
verifier; reuse the parent command when it remains valid, or provide the narrowest
appropriate verification command. A successful plan_finalize is the only
completion signal.
''',
        user:
            '''
Task to split: ${project.taskAgentNumber(oversizedTask.id)}
Task title: ${oversizedTask.title}

Validation violations:
${_encoder.convert(violations)}

Planning frontier:
${_encoder.convert(_planningFrontier(project, focusedTask: oversizedTask, triggers: const ['task_replan_requested']))}
''',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      return _incrementalPlanResult(context, result);
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
    Map<String, dynamic> result,
  ) async {
    final committed = context.committedProject;
    if (committed != null && context.closed && result['ok'] == true) {
      return ProjectIncrementalPlanResult(
        project: committed,
        committed: true,
        changed: result['changed'] == true,
        awaitingApproval: result['awaiting_approval'] == true,
        modelCalls: (result['model_calls'] as num?)?.toInt() ?? 1,
        planningMetrics: _planningMetricsFromResult(result),
        patch: context.committedPatch,
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
    ProjectAggregate project,
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

  @override
  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ModelConversationPort client,
    required String baseSystemPrompt,
    required ProjectAggregate project,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    try {
      final json = await _completeJson(
        client: client,
        label: 'Project Completion Evaluator',
        system: '$baseSystemPrompt\n\n$_completionEvaluationSystemInstruction',
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        expectedShape:
            '{"complete":false,"final_summary":"...","remaining_criteria":["..."],"supported_criterion_ids":["criterion_001"],"open_questions":[{"question":"..."}]}',
        user:
            '''
Perform one bounded semantic review of the unresolved Project criteria and their persisted evidence.
Task completion alone is not evidence that a criterion is satisfied. Treat proposed task claims as advisory. List every criterion that still lacks adequate evidence in remaining_criteria, and list criterion IDs with credible partial support in supported_criterion_ids.
Only include a criterion in supported_criterion_ids when persisted proposed or accepted evidence provides meaningful support beyond merely reporting that work was attempted. Do not include deterministic criteria unless their deterministic evidence is present; do not include evidence that is only advisory.
Set complete only when every required criterion is adequately supported. Your decision will be persisted as an evidence-review rationale.
Do not add open_questions for prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences.
Add open_questions only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.

Return only JSON:
{
  "complete": false,
  "final_summary": "...",
  "remaining_criteria": ["..."],
  "supported_criterion_ids": ["criterion_001"],
  "open_questions": [{"question": "..."}]
}

Project state:
${_encoder.convert(snakeCaseWire(ModelJson.encode(project)))}
''',
      );
      final rawRemainingCriteria =
          json['remainingCriteria'] ?? json['remaining_criteria'];
      final rawSupportedCriterionIds =
          json['supportedCriterionIds'] ?? json['supported_criterion_ids'];
      if (json['complete'] is! bool ||
          rawRemainingCriteria is! List ||
          rawSupportedCriterionIds is! List) {
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
      return ProjectCompletionAssessment(
        complete: json['complete'] as bool,
        finalSummary: jsonString(json['finalSummary'] ?? json['final_summary']),
        remainingCriteria: jsonStringList(rawRemainingCriteria),
        supportedCriterionIds: jsonStringList(rawSupportedCriterionIds),
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
    required ModelConversationPort client,
    required String system,
    required String user,
    required String label,
    required String expectedShape,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final result = await _structuredOutput.completeObject(
      client: client,
      label: label,
      system: system,
      user: user,
      expectedShape: expectedShape,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    return result.value;
  }

  List<PendingProjectQuestion> _questionsFromJson(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((raw) {
      final map = Map<String, dynamic>.from(raw);
      map['id'] = jsonString(map['id'], fallback: 'question_${uuid.v7()}');
      map['createdAt'] ??= DateTime.now().toIso8601String();
      final agentQuestion = const QuestionProtocolAdapter().decode(map);
      if (agentQuestion != null) {
        map['question'] = agentQuestion.displayText;
      }
      return ModelJson.decode<PendingProjectQuestion>(map);
    }).toList();
  }
}

const String _completionEvaluationSystemInstruction = '''
You are a project completion evaluator.
Return only valid JSON for the requested semantic assessment.
Do not propose or mutate a plan. Treat persisted evidence as authoritative and
task claims as advisory.
''';
