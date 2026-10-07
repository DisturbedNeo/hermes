import 'dart:convert';

import 'package:hermes/features/project/application/contracts/project_task_models.dart'
    show ProjectTaskCheckSpec;
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/project/runtime/project_plan_builder.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/runtime/project_plan_validator.dart';
import 'package:hermes/features/project/runtime/project_planning_workspace_reader.dart';
import 'package:hermes/features/project/runtime/project_view_service.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';

part 'project_planning_tool_command_service.dart';
part 'project_planning_workspace_command_service.dart';
part 'project_plan_editing_command_service.dart';

/// The state and policy available to a single project-planning invocation.
///
/// Planning commands can only edit the in-memory [ProjectPlanBuilder] draft.
/// Initial planning may additionally receive a separately budgeted,
/// read-only workspace context reader.
class ProjectPlanningContext {
  ProjectPlanningContext({
    required this.project,
    required this.workspaceRoot,
    DateTime? now,
    Iterable<ProjectPlanRevisionTrigger> triggers = const [],
    String summary = 'Apply the incremental plan update.',
    String rationale = 'Keep the project plan bounded and actionable.',
    bool requiresApproval = false,
    String approvalReason = '',
    this.approvalPolicy = ProjectPlanApprovalPolicy.highRiskOnly,
    this.deferRevision = false,
    this.planningPass = ProjectPlanningPass.maintenance,
    this.planningLimits = ProjectPlanningLimits.maintenance,
    ProjectPlanRevisionService revisionService =
        const ProjectPlanRevisionService(),
    this.viewService = const ProjectViewService(),
    this.workspaceReader,
  }) : builder = ProjectPlanBuilder(
         project: project,
         now: now,
         triggers: triggers,
         summary: summary,
         rationale: rationale,
         requiresApproval: requiresApproval,
         approvalReason: approvalReason,
         planningLimits: planningLimits,
         revisionService: revisionService,
       ),
       baseRevision = project.nextRevision - 1,
       _draftTitle = project.title,
       _draftRefinedGoal = project.refinedGoal,
       _draftConstraints = [...project.constraints];

  final ProjectAggregate project;
  final String workspaceRoot;
  final int baseRevision;
  final ProjectPlanApprovalPolicy approvalPolicy;
  final bool deferRevision;
  final ProjectPlanningPass planningPass;
  final ProjectPlanningLimits planningLimits;
  final ProjectPlanBuilder builder;
  final ProjectViewService viewService;
  final ProjectPlanningWorkspaceReader? workspaceReader;

  String _draftTitle;
  String _draftRefinedGoal;
  List<String> _draftConstraints;
  ProjectDesiredPlan? committedProposal;
  ProjectPlanPatch? committedPatch;
  ProjectAggregate? committedProject;

  bool closed = false;

  String get draftTitle => _draftTitle;
  String get draftRefinedGoal => _draftRefinedGoal;
  List<String> get draftConstraints => List.unmodifiable(_draftConstraints);

  bool get projectDetailsChanged =>
      _draftTitle != project.title ||
      _draftRefinedGoal != project.refinedGoal ||
      !_sameStrings(_draftConstraints, project.constraints);

  void setProjectDetails({
    required String title,
    required String refinedGoal,
    List<String>? constraints,
  }) {
    _draftTitle = title;
    _draftRefinedGoal = refinedGoal;
    builder.setValidationRefinedGoal(refinedGoal);
    if (constraints != null) _draftConstraints = [...constraints];
  }

  static bool _sameStrings(Iterable<String> first, Iterable<String> second) {
    final left = first.toList();
    final right = second.toList();
    return left.length == right.length &&
        left.asMap().entries.every((entry) => entry.value == right[entry.key]);
  }
}

/// Model-facing project planning tools.
///
/// The registry is deliberately separate from [ToolService]. It returns
/// [ToolDefinition] values for a planner call and never exposes mutating
/// workspace tools or full domain objects in those schemas.
class ProjectPlanningToolRegistry extends PlanningToolRegistryBase {
  ProjectPlanningToolRegistry({
    required ProjectPlanningContext context,
    ProjectPlanningToolProfile profile = ProjectPlanningToolProfile.maintenance,
    bool includeProjectDetails = false,
  }) : _commands = ProjectPlanningToolCommandService(
         context: context,
         profile: profile,
         includeProjectDetails: includeProjectDetails,
       );

  final ProjectPlanningToolCommandService _commands;

  @override
  String get terminalToolId => _commands.terminalToolId;

  @override
  String get closedCode => _commands.closedCode;

  @override
  String get closedMessage => _commands.closedMessage;

  @override
  List<ToolDefinition> get toolDefinitions => _commands.toolDefinitions;

  @override
  bool get allowsWorkspaceMutation => _commands.allowsWorkspaceMutation;

  @override
  Future<PlanningResponse> dispatch(
    String toolId,
    PlanningArguments arguments, {
    String? commandId,
  }) => _commands.dispatch(toolId, arguments, commandId: commandId);

  @override
  Map<String, dynamic> domainError(Object error) =>
      _commands.domainError(error);
}

class _PlanningArgumentException extends PlanningToolArgumentException {
  const _PlanningArgumentException(
    super.code,
    super.path,
    super.message, {
    super.details,
  });
}

ToolSchema _schema({
  required Map<String, dynamic> properties,
  List<String> required = const [],
  List<Map<String, dynamic>> anyOf = const [],
}) => ToolSchema({
  'type': 'object',
  'properties': properties,
  'required': required,
  if (anyOf.isNotEmpty) 'anyOf': anyOf,
  'additionalProperties': false,
});

Map<String, dynamic> _stringArraySchema({int? minItems}) {
  final schema = <String, dynamic>{
    'type': 'array',
    'items': {'type': 'string'},
  };
  if (minItems != null) schema['minItems'] = minItems;
  return schema;
}

Map<String, dynamic> _workspaceStringArraySchema() => {
  'type': 'array',
  'maxItems': 20,
  'items': {'type': 'string', 'maxLength': 200},
};

Map<String, dynamic> _enumSchema(Iterable<String> values) => {
  'type': 'string',
  'enum': values.toList(),
};

final _taskSpecSchema = _schema(
  properties: {
    'ref': {'type': 'string', 'description': 'Optional temporary reference.'},
    'title': {'type': 'string'},
    'objective': {'type': 'string'},
    'criterion_refs': _stringArraySchema(minItems: 1),
    'dependency_refs': _stringArraySchema(),
    'milestone_ref': {'type': 'string'},
    'priority': {
      ..._enumSchema(TaskPriority.values.map((item) => item.name)),
      'default': TaskPriority.normal.name,
    },
    'risk': {
      ..._enumSchema(TaskRisk.values.map((item) => item.name)),
      'default': TaskRisk.unknown.name,
    },
    'risk_reduction': {
      ..._enumSchema(ProjectRiskReduction.values.map((item) => item.name)),
      'default': ProjectRiskReduction.none.name,
    },
    'effort': {
      ..._enumSchema(TaskEffort.values.map((item) => item.name)),
      'default': TaskEffort.small.name,
    },
    'selection_rationale': {'type': 'string'},
    'constraints': _stringArraySchema(),
    'read_paths': _stringArraySchema(),
    'write_paths': _stringArraySchema(),
    'done_criteria': _stringArraySchema(minItems: 1),
    'out_of_scope': _stringArraySchema(minItems: 1),
    'context': _stringArraySchema(),
    'expected_artifacts': {
      'type': 'array',
      'items': _schema(
        properties: {
          'path': {'type': 'string'},
          'description': {'type': 'string'},
          'kind': {'type': 'string'},
        },
        required: const ['path'],
      ),
    },
  },
  required: const ['criterion_refs', 'done_criteria', 'out_of_scope'],
  anyOf: const [
    {
      'required': ['title'],
    },
    {
      'required': ['objective'],
    },
  ],
);

final _taskCheckSpecSchema = _schema(
  properties: {
    'command': {'type': 'string'},
    'working_directory': {'type': 'string', 'default': '.'},
    'criterion_refs': _stringArraySchema(),
    'required': {'type': 'boolean', 'default': true},
    'description': {'type': 'string'},
  },
  required: const ['command'],
);

final _addTaskDefinition = ToolDefinition(
  id: 'plan_add_task',
  name: 'Add project task',
  description:
      'Create one bounded project task. Submit the complete task in this call; arguments from previous calls are not merged.',
  schema: _schema(
    properties: {
      'ref': {'type': 'string', 'description': 'Optional temporary reference.'},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'criterion_refs': _stringArraySchema(minItems: 1),
      'dependency_refs': _stringArraySchema(),
      'milestone_ref': {'type': 'string'},
      'done_criteria': _stringArraySchema(minItems: 1),
      'out_of_scope': _stringArraySchema(minItems: 1),
      'checks': {'type': 'array', 'items': _taskCheckSpecSchema},
    },
    required: const [
      'objective',
      'criterion_refs',
      'done_criteria',
      'out_of_scope',
    ],
  ),
);

final _projectDetailsDefinition = ToolDefinition(
  id: 'plan_set_project_details',
  name: 'Set project details',
  description:
      'Set the initial project title, refined goal, and workspace constraints.',
  schema: _schema(
    properties: {
      'title': {'type': 'string'},
      'refined_goal': {'type': 'string'},
      'constraints': _stringArraySchema(),
    },
    required: const ['title', 'refined_goal'],
  ),
);

final _projectViewDefinition = ToolDefinition(
  id: 'project_view',
  name: 'Project view',
  description:
      'Read a bounded project summary, readiness, failures, or one requested detail.',
  schema: _schema(
    properties: {
      'task_ref': {'type': 'string'},
      'criterion_ref': {'type': 'string'},
      'memory_query': {'type': 'string'},
      'workspace_query': {'type': 'string'},
      'max_items': {'type': 'integer', 'minimum': 1, 'maximum': 100},
      'section': {
        'type': 'string',
        'enum': ProjectViewService.viewSections,
        'description':
            'Optional collection to page. Use the next_cursor returned in navigation.pages.',
      },
      'cursor': {
        'type': 'string',
        'description':
            'Cursor returned in navigation.pages for the selected section.',
      },
    },
  ),
);

final _planningReadFileDefinition = ToolDefinition(
  id: 'planning_read_file',
  name: 'Read planning context file',
  description:
      'Read a bounded line window from one existing file in the discovered workspace. Repeat with next_start_line when has_more is true. This is read-only and cannot access files outside the discovery tree.',
  schema: _schema(
    properties: {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative file path from readableFiles.',
      },
      'start_line': {
        'type': 'integer',
        'minimum': 1,
        'description': 'First 1-based line to return. Defaults to 1.',
      },
      'end_line': {
        'type': 'integer',
        'minimum': 1,
        'maximum': ProjectPlanningWorkspaceReader.defaultMaxWindowLines,
        'description':
            'Optional inclusive line number. Each response is capped at a bounded window.',
      },
    },
    required: const ['path'],
  ),
);

final _addCriteriaDefinition = ToolDefinition(
  id: 'plan_add_criteria',
  name: 'Add project criteria',
  description:
      'Add criteria with generated IDs and optional temporary references.',
  schema: _schema(
    properties: {
      'criteria': {
        'type': 'array',
        'minItems': 1,
        'items': _schema(
          properties: {
            'ref': {'type': 'string'},
            'statement': {'type': 'string'},
            'required': {'type': 'boolean'},
            'verification_mode': _enumSchema(
              ProjectVerificationMode.values.map((item) => item.name),
            ),
          },
          required: const ['statement'],
        ),
      },
    },
    required: const ['criteria'],
  ),
);

final _addMilestonesDefinition = ToolDefinition(
  id: 'plan_add_milestones',
  name: 'Add project milestones',
  description: 'Add optional milestones linked to criterion references.',
  schema: _schema(
    properties: {
      'milestones': {
        'type': 'array',
        'minItems': 1,
        'items': _schema(
          properties: {
            'ref': {'type': 'string'},
            'title': {'type': 'string'},
            'objective': {'type': 'string'},
            'criterion_refs': _stringArraySchema(),
            'exit_conditions': _stringArraySchema(),
            'order': {'type': 'integer'},
          },
          required: const ['title', 'objective'],
        ),
      },
    },
    required: const ['milestones'],
  ),
);

final _updateTaskDefinition = ToolDefinition(
  id: 'plan_update_task',
  name: 'Update project task',
  description:
      'Patch one existing mutable task by reference; never creates a task.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
      'criterion_refs': _stringArraySchema(),
      'dependency_refs': _stringArraySchema(),
      'milestone_ref': {'type': 'string'},
      'clear_milestone': {'type': 'boolean'},
      'priority': _enumSchema(TaskPriority.values.map((item) => item.name)),
      'risk': _enumSchema(TaskRisk.values.map((item) => item.name)),
      'risk_reduction': _enumSchema(
        ProjectRiskReduction.values.map((item) => item.name),
      ),
      'effort': _enumSchema(TaskEffort.values.map((item) => item.name)),
      'selection_rationale': {'type': 'string'},
      'constraints': _stringArraySchema(),
      'read_paths': _stringArraySchema(),
      'write_paths': _stringArraySchema(),
      'done_criteria': _stringArraySchema(),
      'out_of_scope': _stringArraySchema(),
      'context': _stringArraySchema(),
      'expected_artifacts': _taskSpecSchema['properties'] is Map
          ? (_taskSpecSchema['properties'] as Map)['expected_artifacts']
          : _stringArraySchema(),
    },
    required: const ['task'],
  ),
);

final _setDependencyDefinition = ToolDefinition(
  id: 'plan_set_dependency',
  name: 'Set task dependency',
  description: 'Add or remove one dependency and reject cycles immediately.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'dependency': {'type': 'string'},
      'enabled': {'type': 'boolean'},
    },
    required: const ['task', 'dependency'],
  ),
);

final _setDispositionDefinition = ToolDefinition(
  id: 'plan_set_disposition',
  name: 'Set task disposition',
  description: 'Defer or obsolete one mutable task by reference.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'disposition': _enumSchema(
        ProjectPlanTaskDisposition.values.map((item) => item.name),
      ),
    },
    required: const ['task', 'disposition'],
  ),
);

final _splitTaskDefinition = ToolDefinition(
  id: 'plan_split_task',
  name: 'Split project task',
  description:
      'Replace one mutable oversized task with newly generated child tasks.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'children': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 5,
        'items': _taskSpecSchema,
      },
    },
    required: const ['task', 'children'],
  ),
);

final _retryTaskDefinition = ToolDefinition(
  id: 'plan_retry_task',
  name: 'Retry failed project task',
  description:
      'Create a fresh retry task while preserving the failed task history.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'ref': {'type': 'string'},
      'title': {'type': 'string'},
      'objective': {'type': 'string'},
    },
    required: const ['task'],
  ),
);

final _addCheckDefinition = ToolDefinition(
  id: 'plan_add_check',
  name: 'Add project check',
  description:
      'Add a command verification intent with generated gate and evidence IDs.',
  schema: _schema(
    properties: {
      'task': {'type': 'string'},
      'kind': {
        'type': 'string',
        'enum': const ['command'],
      },
      'command': {'type': 'string'},
      'working_directory': {'type': 'string'},
      'criterion_refs': _stringArraySchema(),
      'required': {'type': 'boolean'},
      'description': {'type': 'string'},
    },
    required: const ['task', 'kind', 'command'],
  ),
);

final _addNoteDefinition = ToolDefinition(
  id: 'plan_add_note',
  name: 'Add planning note',
  description:
      'Record a planner fact, assumption, risk, or decision with a generated ID.',
  schema: _schema(
    properties: {
      'kind': _enumSchema(ProjectMemoryKind.values.map((item) => item.name)),
      'content': {'type': 'string'},
      'source_id': {'type': 'string'},
    },
    required: const ['kind', 'content'],
  ),
);

final _setWorkspaceOrientationDefinition = ToolDefinition(
  id: 'plan_set_workspace_orientation',
  name: 'Set workspace orientation',
  description:
      'Set a concise, domain-neutral explanation of how the project workspace fits together.',
  schema: _schema(
    properties: {
      'orientation': {'type': 'string', 'maxLength': 4000},
    },
    required: const ['orientation'],
  ),
);

final _addWorkspaceNodesDefinition = ToolDefinition(
  id: 'plan_add_workspace_nodes',
  name: 'Add workspace nodes',
  description:
      'Add conceptual or artifact nodes such as components, characters, sources, requirements, or workflow stages.',
  schema: _schema(
    properties: {
      'nodes': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 20,
        'items': _schema(
          properties: {
            'ref': {'type': 'string', 'maxLength': 200},
            'type': {'type': 'string', 'maxLength': 200},
            'title': {'type': 'string', 'maxLength': 200},
            'description': {'type': 'string', 'maxLength': 2000},
            'aliases': _workspaceStringArraySchema(),
            'tags': _workspaceStringArraySchema(),
            'references': _workspaceStringArraySchema(),
          },
          required: const ['type', 'title'],
        ),
      },
    },
    required: const ['nodes'],
  ),
);

final _updateWorkspaceNodeDefinition = ToolDefinition(
  id: 'plan_update_workspace_node',
  name: 'Update workspace node',
  description: 'Update one existing, non-protected workspace node.',
  schema: _schema(
    properties: {
      'node': {'type': 'string'},
      'type': {'type': 'string', 'maxLength': 200},
      'title': {'type': 'string', 'maxLength': 200},
      'description': {'type': 'string', 'maxLength': 2000},
      'aliases': _workspaceStringArraySchema(),
      'tags': _workspaceStringArraySchema(),
      'references': _workspaceStringArraySchema(),
    },
    required: const ['node'],
  ),
);

final _addWorkspaceEdgesDefinition = ToolDefinition(
  id: 'plan_add_workspace_edges',
  name: 'Add workspace edges',
  description: 'Add labeled relationships between workspace node references.',
  schema: _schema(
    properties: {
      'edges': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 40,
        'items': _schema(
          properties: {
            'ref': {'type': 'string', 'maxLength': 200},
            'source_ref': {'type': 'string', 'maxLength': 200},
            'target_ref': {'type': 'string', 'maxLength': 200},
            'label': {'type': 'string', 'maxLength': 200},
            'description': {'type': 'string', 'maxLength': 1000},
          },
          required: const ['source_ref', 'target_ref', 'label'],
        ),
      },
    },
    required: const ['edges'],
  ),
);

final _updateWorkspaceEdgeDefinition = ToolDefinition(
  id: 'plan_update_workspace_edge',
  name: 'Update workspace edge',
  description: 'Update one existing, non-protected workspace relationship.',
  schema: _schema(
    properties: {
      'edge': {'type': 'string'},
      'source_ref': {'type': 'string'},
      'target_ref': {'type': 'string'},
      'label': {'type': 'string', 'maxLength': 200},
      'description': {'type': 'string', 'maxLength': 1000},
    },
    required: const ['edge'],
  ),
);

final _removeWorkspaceItemDefinition = ToolDefinition(
  id: 'plan_remove_workspace_item',
  name: 'Remove workspace item',
  description: 'Remove one non-protected workspace node or edge.',
  schema: _schema(
    properties: {
      'kind': {
        'type': 'string',
        'enum': const ['node', 'edge'],
      },
      'ref': {'type': 'string'},
    },
    required: const ['kind', 'ref'],
  ),
);

final _requestDecisionDefinition = ToolDefinition(
  id: 'plan_request_user_decision',
  name: 'Request user decision',
  description:
      'Ask one blocking question for a genuinely unsafe-to-assume decision.',
  schema: _schema(
    properties: {
      'question': {'type': 'string'},
    },
    required: const ['question'],
  ),
);

final _previewDefinition = ToolDefinition(
  id: 'plan_preview',
  name: 'Preview project plan',
  description:
      'Validate the draft and return a compact diff without committing it.',
  schema: _schema(
    properties: {
      'summary': {'type': 'string'},
      'rationale': {'type': 'string'},
    },
  ),
);

final _commitDefinition = ToolDefinition(
  id: 'plan_commit',
  name: 'Commit project plan',
  description:
      'Validate and apply the draft through the existing project revision service.',
  schema: _schema(
    properties: {
      'summary': {'type': 'string'},
      'rationale': {'type': 'string'},
    },
  ),
);
