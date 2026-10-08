import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

typedef ProjectWorkspaceGraphPersistence =
    Future<ProjectAggregate> Function(
      ProjectAggregate project,
      ProjectPersistenceCheckpoint checkpoint,
    );

typedef ProjectWorkspaceGraphReload = Future<ProjectAggregate?> Function();

class ProjectWorkspaceGraphMaintenanceResult {
  const ProjectWorkspaceGraphMaintenanceResult({
    required this.project,
    required this.evidence,
    required this.plannerAttempted,
    required this.plannerCommitted,
    this.error,
  });

  final ProjectAggregate project;
  final ProjectEvidenceSnapshot evidence;
  final bool plannerAttempted;
  final bool plannerCommitted;
  final String? error;
}

/// Coordinates the lifecycle-bound deterministic and semantic graph passes.
///
/// The deterministic reconciliation is persisted before the optional model
/// call. A failed or unavailable semantic pass therefore cannot discard fresh
/// workspace facts.
class ProjectWorkspaceGraphMaintenanceCoordinator {
  const ProjectWorkspaceGraphMaintenanceCoordinator({
    required ProjectDiscoveryService discovery,
    required ProjectPlanner planner,
  }) : _discovery = discovery,
       _planner = planner;

  final ProjectDiscoveryService _discovery;
  final ProjectPlanner _planner;

  Future<ProjectWorkspaceGraphMaintenanceResult> maintain({
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required String baseSystemPrompt,
    required ProjectWorkspaceGraphPersistence persist,
    ProjectWorkspaceGraphReload? reload,
    ModelConversationPort? client,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    int staleRetryCount = 0,
  }) async {
    ProjectEvidenceSnapshot? evidence;
    var working = project;
    try {
      evidence = await _discovery.collect(
        workspace: workspace,
        project: project,
        goalContext:
            'Original goal:\n${project.originalGoal}\n\nRefined goal:\n${project.refinedGoal}',
        cancellationToken: cancellationToken,
      );
      final reconciliation = evidence.workspaceGraphReconciliation;
      final graphTrigger = ProjectPlanRevisionTrigger.workspaceGraphMaintenance;
      final graphTriggerPending = project.pendingReplanTriggers.contains(
        graphTrigger,
      );
      final semanticRecommended =
          reconciliation?.plannerMaintenanceRecommended ?? false;
      if (reconciliation != null && reconciliation.changed) {
        working = project.copyWith(
          workspaceGraph: reconciliation.graph,
          pendingReplanTriggers: semanticRecommended || graphTriggerPending
              ? _withTrigger(project.pendingReplanTriggers, graphTrigger)
              : project.pendingReplanTriggers,
          diagnostics: project.diagnostics.copyWith(
            workspaceGraphDerivedUpdates:
                project.diagnostics.workspaceGraphDerivedUpdates +
                reconciliation.derivedUpdateCount,
          ),
          updatedAt: DateTime.now(),
        );
        working = await persist(
          working,
          ProjectPersistenceCheckpoint.workspaceGraphMaintenance,
        );
      }

      final needsSemanticMaintenance =
          graphTriggerPending || semanticRecommended;
      if (!needsSemanticMaintenance) {
        return ProjectWorkspaceGraphMaintenanceResult(
          project: working,
          evidence: evidence,
          plannerAttempted: false,
          plannerCommitted: false,
        );
      }

      if (client == null) {
        working = await persist(
          working.copyWith(
            diagnostics: working.diagnostics.copyWith(
              workspaceGraphMaintenanceAttempts:
                  working.diagnostics.workspaceGraphMaintenanceAttempts + 1,
            ),
            updatedAt: DateTime.now(),
          ),
          ProjectPersistenceCheckpoint.workspaceGraphMaintenance,
        );
        working = await _recordFailure(
          working,
          'Workspace graph semantic maintenance is pending because no planner client is available.',
          persist,
        );
        return ProjectWorkspaceGraphMaintenanceResult(
          project: working,
          evidence: evidence,
          plannerAttempted: false,
          plannerCommitted: false,
          error: 'No planner client is available.',
        );
      }

      working = await persist(
        working.copyWith(
          diagnostics: working.diagnostics.copyWith(
            workspaceGraphMaintenanceAttempts:
                working.diagnostics.workspaceGraphMaintenanceAttempts + 1,
          ),
          updatedAt: DateTime.now(),
        ),
        ProjectPersistenceCheckpoint.workspaceGraphMaintenance,
      );
      final plannerResult = await _planner.maintainWorkspaceGraph(
        client: client,
        baseSystemPrompt: baseSystemPrompt,
        workspace: workspace,
        project: working,
        evidenceSnapshot: evidence,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      );
      final graphCommitIsSafe =
          plannerResult.committed &&
          !plannerResult.awaitingApproval &&
          plannerResult.project.status == working.status &&
          plannerResult.project.activeTaskId == working.activeTaskId &&
          !plannerResult.project.pendingReplanTriggers.contains(graphTrigger);
      if (graphCommitIsSafe) {
        final committed = await persist(
          plannerResult.project,
          ProjectPersistenceCheckpoint.planRevision,
        );
        return ProjectWorkspaceGraphMaintenanceResult(
          project: committed,
          evidence: evidence,
          plannerAttempted: true,
          plannerCommitted: true,
        );
      }

      final failed = await _recordFailure(
        working,
        plannerResult.error ??
            (plannerResult.committed
                ? 'The graph-maintenance planner produced an unsafe project state.'
                : 'The graph-maintenance planner did not commit.'),
        persist,
      );
      return ProjectWorkspaceGraphMaintenanceResult(
        project: failed,
        evidence: evidence,
        plannerAttempted: true,
        plannerCommitted: false,
        error: plannerResult.error,
      );
    } on OperationCancelledException {
      rethrow;
    } on StaleSnapshotException catch (error) {
      if (reload != null && staleRetryCount < 1) {
        try {
          final latest = await reload();
          if (latest != null) {
            return maintain(
              workspace: workspace,
              project: latest,
              baseSystemPrompt: baseSystemPrompt,
              persist: persist,
              reload: reload,
              client: client,
              onModelOutput: onModelOutput,
              cancellationToken: cancellationToken,
              staleRetryCount: staleRetryCount + 1,
            );
          }
        } catch (_) {
          // The retry is best effort. The original stale write remains
          // recoverable at the next lifecycle boundary.
        }
      }
      return ProjectWorkspaceGraphMaintenanceResult(
        project: working,
        evidence:
            evidence ??
            ProjectEvidenceSnapshot(
              workspaceName: workspace.displayName,
              collectedAt: DateTime.now(),
            ),
        plannerAttempted: false,
        plannerCommitted: false,
        error: error.toString(),
      );
    } catch (error) {
      final failed = await _recordFailure(
        working,
        'Workspace graph maintenance failed: $error',
        persist,
      );
      return ProjectWorkspaceGraphMaintenanceResult(
        project: failed,
        evidence:
            evidence ??
            ProjectEvidenceSnapshot(
              workspaceName: workspace.displayName,
              collectedAt: DateTime.now(),
            ),
        plannerAttempted: false,
        plannerCommitted: false,
        error: error.toString(),
      );
    }
  }

  Future<ProjectAggregate> _recordFailure(
    ProjectAggregate project,
    String message,
    ProjectWorkspaceGraphPersistence persist,
  ) async {
    final trigger = ProjectPlanRevisionTrigger.workspaceGraphMaintenance;
    return persist(
      project.copyWith(
        pendingReplanTriggers: _withTrigger(
          project.pendingReplanTriggers,
          trigger,
        ),
        pendingReplanReason: project.pendingReplanReason ?? message,
        diagnostics: project.diagnostics.copyWith(
          workspaceGraphMaintenanceFailures:
              project.diagnostics.workspaceGraphMaintenanceFailures + 1,
        ),
        updatedAt: DateTime.now(),
      ),
      ProjectPersistenceCheckpoint.workspaceGraphMaintenance,
    );
  }

  static List<ProjectPlanRevisionTrigger> _withTrigger(
    Iterable<ProjectPlanRevisionTrigger> current,
    ProjectPlanRevisionTrigger trigger,
  ) => [...current, if (!current.contains(trigger)) trigger];
}
