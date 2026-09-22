import 'dart:convert';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/project_system/project_planning_gateway.dart';
import 'package:hermes/core/services/project_system/project_planning_tools.dart';
import 'package:hermes/core/services/project_system/project_planning_workspace_reader.dart';
import 'package:hermes/core/services/project_system/project_view_service.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/tool_service.dart';

export 'package:hermes/core/services/project_system/project_planning_gateway.dart'
    show
        ProjectCompletionAssessment,
        ProjectEvidenceSnapshot,
        ProjectInitialisation,
        ProjectIncrementalPlanResult,
        ProjectPlanner,
        ProjectCompletionEvaluator;

class ProjectModelCalls implements ProjectPlanner, ProjectCompletionEvaluator {
  ProjectModelCalls({
    required ToolService toolService,
    ProjectViewService projectViewService = const ProjectViewService(),
    PlanningToolCallRunner planningRunner = const PlanningToolCallRunner(),
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
  }) : _toolService = toolService,
       _projectViewService = projectViewService,
       _planningRunner = planningRunner,
       _structuredOutput = structuredOutput;

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');
  final ToolService _toolService;
  final ProjectViewService _projectViewService;
  final PlanningToolCallRunner _planningRunner;
  final StructuredPlanningOutputService _structuredOutput;

  Future<Map<String, dynamic>> _runPlanning({
    required ChatClient client,
    required PlanningToolRegistry registry,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
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
      return await _completeInitialPlanning(
        client: client,
        baseSystemPrompt: baseSystemPrompt,
        workspace: workspace,
        originalGoal: originalGoal,
        workspaceMetadata: workspaceMetadata,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        additionalInstruction:
            '''
Repair the previous draft by resolving every structured validation issue below.
Preserve the user's original outcome and do not invent workspace state. Build
the corrected draft through the planning commands and commit it with
plan_commit.

Validation issues:
${_encoder.convert(validationIssues)}

Previous draft:
${_encoder.convert(_initialisationToMap(initialisation))}
''',
      );
    } on OperationCancelledException {
      rethrow;
    } on ChatTransportException {
      return null;
    } catch (_) {
      return null;
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
      final result = await _runPlanning(
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
      final result = await _runPlanning(
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
        system: '$baseSystemPrompt\n\n$_completionEvaluationSystemInstruction',
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
    required ChatClient client,
    required String system,
    required String user,
    required String label,
    required String expectedShape,
    TaskModelOutputSink? onModelOutput,
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
      workspaceReader: ProjectPlanningWorkspaceReader(
        workspace: workspace,
        sandbox: _toolService.workspaceSandbox,
        allowedPaths: _workspaceFilesFromMetadata(workspaceMetadata),
        cancellationToken: cancellationToken,
      ),
    );
    final registry = ProjectPlanningToolRegistry(
      context: context,
      includeProjectDetails: true,
    );
    final result = await _runPlanning(
      client: client,
      registry: registry,
      label: 'Project Initial Planning',
      system:
          '''
$baseSystemPrompt

You are planning a new project through explicit planning commands. Do not return a complete project JSON document and do not execute workspace changes. The planning registry is the only tool surface available.
Tool arguments must follow their schemas, but the plan itself must be built through tool calls rather than returned as a large JSON document.
Your job is to create and commit the roadmap, not to solve or implement its
tasks during planning. Read workspace files only when they resolve a planning
uncertainty, then express implementation and verification work as bounded
tasks. Once there is enough context for an executable task list, stop exploring
and commit the plan.
The workspace profile below is a compact bootstrap map. When the goal depends
on a file, especially a design, specification, requirements, architecture, or
instruction document, use planning_read_file to read that existing file before
deriving requirements.
The reader is read-only, limited to files in the discovery tree, and has a
finite byte budget. If a result has has_more=true, continue at its next_start_line.
Do not use it to inspect unrelated files; use the tree and the goal to choose
only the smallest set of files needed for the initial plan.
Use plan_set_project_details first to set a concise title, a useful refined goal, and the constraints that must remain true. Add one or more success criteria with plan_add_criteria. Milestones are optional; add one or more with plan_add_milestones when they clarify delivery, otherwise Hermes will create a default milestone for executable work.
Use plan_add_tasks for a small batch of bounded near-term tasks, normally no more than seven queued tasks. Each task needs an objective or title, at least one criterion reference, done criteria, and an explicit out-of-scope boundary. Use temporary refs such as scaffold and verify to link tasks and dependencies; Hermes generates canonical IDs.
Add command checks with plan_add_check when a task needs verification. Add notes with plan_add_note for sourced facts, assumptions, risks, or decisions. Ask a user decision only for genuinely irreversible, high-risk, credential, scope, or otherwise unsafe-to-assume ambiguity.
When a note is based on a workspace file, set source_id to workspace:<relative-path>.
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
    final readableFiles = strings(
      profileMap['treePaths'],
      limit: 400,
    ).where((item) => !item.endsWith('/')).toList();
    return {
      'workspaceName': metadata['workspaceName'],
      'commandExecutionApproved': metadata['commandExecutionApproved'],
      'rootEntries': strings(metadata['rootEntries']),
      'gitAvailable': metadata['gitAvailable'] == true,
      'changedFiles': strings(metadata['changedFiles']),
      'treePaths': strings(profileMap['treePaths'], limit: 200),
      'readableFiles': readableFiles,
      'packageName': profileMap['packageName'],
      'scripts': profileMap['scripts'],
      'dependencies': strings(profileMap['dependencies']),
      'languages': strings(profileMap['languages']),
      'frameworks': strings(profileMap['frameworks']),
      'treeTruncated': profileMap['treeTruncated'] == true,
      'omittedPathCount': profileMap['omittedPathCount'],
      'contextWarnings': strings(
        (profileMap['requiredContextIssues'] is List)
            ? (profileMap['requiredContextIssues'] as List)
                  .whereType<Map>()
                  .map(
                    (item) => '${item['path'] ?? ''}: ${item['message'] ?? ''}',
                  )
                  .toList()
            : const [],
        limit: 20,
      ),
    };
  }

  List<String> _workspaceFilesFromMetadata(Map<String, dynamic> metadata) {
    final profile = metadata['workspaceProfile'];
    if (profile is! Map) return const [];
    final treePaths = profile['treePaths'];
    if (treePaths is! List) return const [];
    return [
      for (final item in treePaths)
        if (item is String && !item.endsWith('/')) item,
    ];
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

const String _completionEvaluationSystemInstruction = '''
You are a project completion evaluator.
Return only valid JSON for the requested semantic assessment.
Do not propose or mutate a plan. Treat persisted evidence as authoritative and
task claims as advisory.
''';
