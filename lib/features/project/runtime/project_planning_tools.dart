import 'package:hermes/features/project/application/contracts/project_task_models.dart'
    show
        AcceptanceItem,
        AcceptanceVerifier,
        AcceptanceVerifierKind,
        ProjectTaskArtifactSpec,
        ProjectTaskSpec,
        ProjectTaskStepSpec;
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/project/runtime/project_plan_builder.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_planning_frontier.dart';

part 'project_planning_tool_command_service.dart';
part 'project_planning_workspace_command_service.dart';
part 'project_plan_editing_command_service.dart';

/// The state and policy available to a single project-planning invocation.
///
/// Planning commands receive the complete persisted aggregate and may only
/// mutate it through the aggregate persistence callback.
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
    this.persistProject,
    this.persistProjectWithTasks,
    Map<String, TaskAggregate> canonicalTasks = const {},
    ProjectPlanRevisionService revisionService =
        const ProjectPlanRevisionService(),
  }) : baseRevision = project.nextRevision - 1,
       currentProject = project,
       canonicalTasks = {...canonicalTasks},
       _draftTitle = project.title,
       _draftRefinedGoal = project.refinedGoal,
       _draftConstraints = [...project.constraints] {
    builder = ProjectPlanBuilder(
      project: project,
      now: now,
      triggers: triggers,
      summary: summary,
      rationale: rationale,
      requiresApproval: requiresApproval,
      approvalReason: approvalReason,
      planningLimits: planningLimits,
      revisionService: revisionService,
    );
  }

  final ProjectAggregate project;
  ProjectAggregate currentProject;
  final String workspaceRoot;
  final int baseRevision;
  final ProjectPlanApprovalPolicy approvalPolicy;
  final bool deferRevision;
  final ProjectPlanningPass planningPass;
  final ProjectPlanningLimits planningLimits;
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
  final Map<String, TaskAggregate> canonicalTasks;
  final Map<String, List<ProjectTaskStepSpec>> _taskSteps = {};
  late ProjectPlanBuilder builder;

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
    if (constraints != null) _draftConstraints = [...constraints];
    builder.setValidationProjectDetails(
      title: title,
      refinedGoal: refinedGoal,
      constraints: constraints,
    );
  }

  void rebase(ProjectAggregate next) {
    currentProject = next;
    _draftTitle = next.title;
    _draftRefinedGoal = next.refinedGoal;
    _draftConstraints = [...next.constraints];
    builder = ProjectPlanBuilder(
      project: next,
      triggers: const [],
      summary: 'Apply the immediate planning update.',
      rationale: 'Keep the project plan bounded and actionable.',
      planningLimits: planningLimits,
    );
  }

  void setTaskSteps(String taskId, List<ProjectTaskStepSpec> steps) {
    _taskSteps[taskId] = List.unmodifiable(steps);
  }

  List<ProjectTaskStepSpec>? taskStepsFor(String taskId) => _taskSteps[taskId];

  void restoreTaskSteps(Map<String, List<ProjectTaskStepSpec>> steps) {
    _taskSteps
      ..clear()
      ..addAll({
        for (final entry in steps.entries)
          entry.key: List.unmodifiable(entry.value),
      });
  }

  List<TaskAggregate> _executableTaskUpdates(ProjectAggregate project) {
    final updates = <TaskAggregate>[];
    for (final entry in _taskSteps.entries) {
      final node = project.tasks
          .where((task) => task.id == entry.key)
          .firstOrNull;
      if (node == null) continue;
      final acceptanceRefs = {for (final item in node.acceptance) item.ref};
      for (var stepIndex = 0; stepIndex < entry.value.length; stepIndex++) {
        for (final acceptanceRef in entry.value[stepIndex].acceptanceRefs) {
          if (!acceptanceRefs.contains(acceptanceRef)) {
            throw ProjectPlanBuilderException(
              code: 'unknown_reference',
              path: 'steps[$stepIndex].acceptance_refs',
              message:
                  'Unknown acceptance reference $acceptanceRef for task ${node.id}.',
            );
          }
        }
      }
      final existing = canonicalTasks[node.id];
      final base =
          existing ??
          TaskAggregate(
            id: node.id,
            title: node.title,
            originalPrompt: node.objective,
            objective: node.objective,
            status: node.status,
            constraints: node.constraints,
            acceptance: node.acceptance,
            milestoneId: node.milestoneId,
            dependsOnTaskIds: node.dependsOnTaskIds,
            priority: node.priority,
            risk: node.risk,
            riskReduction: node.riskReduction,
            effort: node.effort,
            selectionRationale: node.selectionRationale,
            revisionIntroduced: node.revisionIntroduced,
            revisionUpdated: node.revisionUpdated,
            readPaths: node.readPaths,
            writePaths: node.writePaths,
            outOfScope: node.outOfScope,
            context: node.context,
            fingerprint: node.fingerprint,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
          );
      final steps = [
        for (final step in entry.value)
          TaskStep(
            id: 'step_${uuid.v7()}',
            title: step.title.trim().isEmpty
                ? step.objective.trim()
                : step.title.trim(),
            objective: step.objective.trim(),
            instructions: step.instructions,
            mayEditFiles: step.mayEditFiles,
            artifacts: [
              for (final artifact in step.artifacts)
                TaskArtifact(
                  path: artifact.path,
                  description: artifact.description,
                  kind: artifact.kind,
                ),
            ],
            acceptanceRefs: step.acceptanceRefs,
            status: TaskStepStatus.pending,
          ),
      ];
      updates.add(
        base.copyWith(
          title: node.title,
          originalPrompt: node.objective,
          objective: node.objective,
          constraints: node.constraints,
          steps: steps,
          currentStepId: steps.firstOrNull?.id,
          acceptance: node.acceptance,
          milestoneId: node.milestoneId,
          dependsOnTaskIds: node.dependsOnTaskIds,
          priority: node.priority,
          risk: node.risk,
          riskReduction: node.riskReduction,
          effort: node.effort,
          selectionRationale: node.selectionRationale,
          revisionIntroduced: node.revisionIntroduced,
          revisionUpdated: node.revisionUpdated,
          readPaths: node.readPaths,
          writePaths: node.writePaths,
          outOfScope: node.outOfScope,
          context: node.context,
          status: node.status,
          updatedAt: node.updatedAt,
        ),
      );
    }
    return updates;
  }

  Future<ProjectAggregate> persistDraft() async {
    final previous = currentProject;
    final previousTaskSteps = {
      for (final entry in _taskSteps.entries)
        entry.key: List<ProjectTaskStepSpec>.from(entry.value),
    };
    try {
      final preview = builder.preview(workspaceRoot: workspaceRoot);
      if (!preview.validation.valid) {
        final issue =
            preview.validation.errors.firstOrNull ??
            preview.validation.issues.first;
        throw ProjectPlanBuilderException(
          code: issue.code,
          path: issue.path,
          message: issue.message,
        );
      }
      final committed = await builder.commit(
        workspaceRoot: workspaceRoot,
        approvalPolicy: approvalPolicy,
      );
      if (!committed.validation.valid) {
        final issue =
            committed.validation.errors.firstOrNull ??
            committed.validation.issues.first;
        throw ProjectPlanBuilderException(
          code: issue.code,
          path: issue.path,
          message: issue.message,
        );
      }
      final dirtyTasks = _executableTaskUpdates(committed.project);
      final persisted = persistProjectWithTasks != null
          ? await persistProjectWithTasks!(
              workspaceRoot,
              committed.project,
              dirtyTasks,
            )
          : persistProject == null
          ? committed.project
          : await persistProject!(workspaceRoot, committed.project);
      for (final task in dirtyTasks) {
        canonicalTasks[task.id] = task;
      }
      _taskSteps.clear();
      committedProposal = committed.proposal;
      committedPatch = committed.patch;
      committedProject = persisted;
      rebase(persisted);
      return persisted;
    } catch (_) {
      // The builder is mutable, so persistence errors must roll its draft back
      // as well as leaving the canonical aggregate untouched.
      rebase(previous);
      _taskSteps
        ..clear()
        ..addAll(previousTaskSteps);
      rethrow;
    }
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
  }) : _commands = ProjectPlanningToolCommandService(
         context: context,
         profile: profile,
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

Map<String, dynamic> _intArraySchema({int? minItems}) {
  final schema = <String, dynamic>{
    'type': 'array',
    'items': {'type': 'integer', 'minimum': 1},
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

final _acceptanceVerifierSchema = _schema(
  properties: {
    'kind': _enumSchema(AcceptanceVerifierKind.values.map((item) => item.name)),
    'required': {'type': 'boolean', 'default': true},
    'command': {'type': 'string'},
    'working_directory': {'type': 'string', 'default': '.'},
    'path': {'type': 'string'},
    'artifact_kind': {'type': 'string', 'default': 'file'},
    'description': {'type': 'string'},
  },
  required: const ['kind'],
);

final _acceptanceSchema = _schema(
  properties: {
    'ref': {'type': 'string'},
    'statement': {'type': 'string'},
    'criterion_ids': _intArraySchema(),
    'verifiers': {
      'type': 'array',
      'minItems': 1,
      'items': _acceptanceVerifierSchema,
    },
  },
  required: const ['ref', 'statement', 'criterion_ids', 'verifiers'],
);

final _taskStepSchema = _schema(
  properties: {
    'ref': {'type': 'string'},
    'title': {'type': 'string'},
    'objective': {'type': 'string'},
    'instructions': _stringArraySchema(),
    'may_edit_files': {'type': 'boolean', 'default': false},
    'artifacts': {
      'type': 'array',
      'items': _schema(
        properties: {
          'path': {'type': 'string'},
          'description': {'type': 'string'},
          'kind': {'type': 'string', 'default': 'file'},
        },
        required: const ['path'],
      ),
    },
    'acceptance_refs': _stringArraySchema(),
  },
  required: const ['objective'],
);

final _agentTaskSchemaProperties = <String, dynamic>{
  'task_id': {'type': 'integer', 'minimum': 1},
  'title': {'type': 'string'},
  'objective': {'type': 'string'},
  'acceptance': {'type': 'array', 'minItems': 1, 'items': _acceptanceSchema},
  'dependency_task_ids': _intArraySchema(),
  'milestone_id': {'type': 'integer', 'minimum': 1},
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
  'out_of_scope': _stringArraySchema(minItems: 1),
  'context': _stringArraySchema(),
  'steps': {'type': 'array', 'minItems': 1, 'items': _taskStepSchema},
  'disposition': _enumSchema(
    ProjectPlanTaskDisposition.values.map((item) => item.name),
  ),
};

final _taskAddSchemaProperties =
    Map<String, dynamic>.from(_agentTaskSchemaProperties)
      ..remove('task_id')
      ..remove('clear_milestone')
      ..remove('disposition');

final _taskUpdateSchemaProperties = Map<String, dynamic>.from(
  _agentTaskSchemaProperties,
)..remove('disposition');

final _planReadDefinition = ToolDefinition(
  id: 'plan_read',
  name: 'Read planning detail',
  description:
      'Read one omitted project planning record. Use a numeric agent ID for a task, criterion, or milestone, or a graph ref for workspace_graph. This tool is read-only.',
  schema: _schema(
    properties: {
      'resource': _enumSchema(const [
        'task',
        'criterion',
        'milestone',
        'workspace_graph',
      ]),
      'id': {'type': 'integer', 'minimum': 1},
      'ref': {'type': 'string', 'maxLength': 200},
    },
    required: const ['resource'],
  ),
);

final _projectUpdateDefinition = ToolDefinition(
  id: 'project_update',
  name: 'Update project',
  description: 'Add or update project metadata, criteria, and milestones.',
  schema: _schema(
    properties: {
      'project_id': {'type': 'string'},
      'title': {'type': 'string'},
      'refined_goal': {'type': 'string'},
      'constraints': _stringArraySchema(),
      'criteria': {
        'type': 'array',
        'items': _schema(
          properties: {
            'criterion_id': {'type': 'integer', 'minimum': 1},
            'statement': {'type': 'string'},
            'required': {'type': 'boolean'},
            'verification_mode': _enumSchema(
              ProjectVerificationMode.values.map((item) => item.name),
            ),
          },
          anyOf: const [
            {
              'required': ['statement'],
            },
            {
              'required': ['criterion_id'],
            },
          ],
        ),
      },
      'milestones': {
        'type': 'array',
        'items': _schema(
          properties: {
            'milestone_id': {'type': 'integer', 'minimum': 1},
            'title': {'type': 'string'},
            'objective': {'type': 'string'},
            'criterion_ids': _intArraySchema(),
            'exit_conditions': _stringArraySchema(),
            'order': {'type': 'integer'},
          },
          anyOf: const [
            {
              'required': ['title', 'objective'],
            },
            {
              'required': ['milestone_id'],
            },
          ],
        ),
      },
    },
    required: const ['project_id'],
  ),
);

final _taskAddDefinition = ToolDefinition(
  id: 'task_add',
  name: 'Add task',
  description:
      'Create one bounded task with canonical acceptance and project criterion links.',
  schema: _schema(
    properties: _taskAddSchemaProperties,
    required: const ['objective', 'acceptance', 'out_of_scope', 'steps'],
  ),
);

final _taskUpdateDefinition = ToolDefinition(
  id: 'task_update',
  name: 'Update task',
  description: 'Partially update one task. Omitted fields remain unchanged.',
  schema: _schema(
    properties: {
      'task_id': {'type': 'integer', 'minimum': 1},
      ..._taskUpdateSchemaProperties,
    },
    required: const ['task_id'],
  ),
);

final _taskRemoveDefinition = ToolDefinition(
  id: 'task_remove',
  name: 'Remove task',
  description: 'Remove one active task while preserving its execution history.',
  schema: _schema(
    properties: {
      'task_id': {'type': 'integer', 'minimum': 1},
    },
    required: const ['task_id'],
  ),
);

final _projectRequestDecisionDefinition = ToolDefinition(
  id: 'project_request_user_decision',
  name: 'Request project decision',
  description: 'Pause project planning with one genuinely blocking question.',
  schema: _schema(
    properties: {
      'question': {'type': 'string'},
    },
    required: const ['question'],
  ),
);

final _projectFinalizeDefinition = ToolDefinition(
  id: 'plan_finalize',
  name: 'Finalize plan',
  description:
      'Move the validated project plan from planning into implementation.',
  schema: _schema(properties: const {}),
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
