import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_completion_port.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/runtime/project_planning_coordinator.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/shared_kernel/project_checkpoint.dart';
import 'package:hermes/shared_kernel/model_output.dart';

/// Planning use cases exposed to the workflow runtime.
///
/// This handler owns the planning protocol and reconciliation services as a
/// single narrow dependency. It does not know about persistence, execution,
/// UI, or task-run history.
class ProjectPlanningHandler {
  const ProjectPlanningHandler({
    required ProjectPlanningCoordinator coordinator,
    required ProjectPlanRevisionService revisionService,
  }) : _coordinator = coordinator,
       _revisionService = revisionService;

  final ProjectPlanningCoordinator _coordinator;
  final ProjectPlanRevisionService _revisionService;

  Future<ProjectPlanningResult> initialise({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ModelCompletionPort? client,
    required String baseSystemPrompt,
    required ProjectInitialPlanResult Function() fallback,
    required ProjectInitialPlanValidator validate,
    required ProjectContextIssuePolicy blocksContextIssue,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _coordinator.initialise(
    workspace: workspace,
    userPrompt: userPrompt,
    client: client,
    baseSystemPrompt: baseSystemPrompt,
    fallback: fallback,
    validate: validate,
    blocksContextIssue: blocksContextIssue,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );

  Future<ProjectPlanRevisionResult> prepareAndApplyPatch({
    required ProjectState project,
    required ProjectPlanPatch patch,
    required String workspaceRoot,
    ProjectPlanApprovalPolicy approvalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
    ProjectPlanRepair? repair,
  }) => _revisionService.prepareAndApplyPatch(
    project: project,
    patch: patch,
    workspaceRoot: workspaceRoot,
    approvalPolicy: approvalPolicy,
    repair: repair,
  );

  Future<ProjectPlanRevisionResult> prepareAndApply({
    required ProjectState project,
    required ProjectDesiredPlan proposal,
    required String workspaceRoot,
    ProjectPlanApprovalPolicy approvalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
    ProjectPlanRepair? repair,
    Iterable<String> splitTaskIds = const [],
  }) => _revisionService.prepareAndApply(
    project: project,
    proposal: proposal,
    workspaceRoot: workspaceRoot,
    approvalPolicy: approvalPolicy,
    repair: repair,
    splitTaskIds: splitTaskIds,
  );

  ProjectPlanRevisionResult approvePending({
    required ProjectState project,
    required String workspaceRoot,
  }) => _revisionService.approvePending(
    project: project,
    workspaceRoot: workspaceRoot,
  );
}

/// The only project persistence use case used by workflow phases.
///
/// Readiness refresh, canonical control-state synchronization, and aggregate
/// commit-intent creation live together here so individual handlers cannot
/// accidentally write repositories or skip a checkpoint.
class ProjectPersistenceHandler {
  const ProjectPersistenceHandler({
    required ProjectAggregateStore aggregateStore,
    required ProjectScheduler scheduler,
    required ProjectControlStateService controlState,
  }) : _aggregateStore = aggregateStore,
       _scheduler = scheduler,
       _controlState = controlState;

  final ProjectAggregateStore _aggregateStore;
  final ProjectScheduler _scheduler;
  final ProjectControlStateService _controlState;

  Future<ProjectDocument> persist(
    String workspaceRoot,
    ProjectDocument project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) {
    final synchronized = _controlState.synchronise(project);
    final refreshed = _scheduler
        .refreshReadiness(synchronized)
        .project
        .copyWith(
          taskIds: synchronized.tasks.isEmpty
              ? synchronized.taskIds
              : [for (final task in synchronized.tasks) task.id],
        );
    return _aggregateStore.commit(
      ProjectCommitIntent(
        workspaceRoot: workspaceRoot,
        project: refreshed,
        context: persistenceContext,
        checkpoint: checkpoint,
      ),
    );
  }
}

/// Recovery use cases are deliberately separate from command routing.
class ProjectRecoveryHandler {
  const ProjectRecoveryHandler(this._service);

  final ProjectRecoveryService _service;

  ProjectDocument reconcile({
    required ProjectDocument project,
    required Task recoveredTask,
    required DateTime now,
  }) => _service.reconcile(
    project: project,
    recoveredTask: recoveredTask,
    now: now,
  );
}
