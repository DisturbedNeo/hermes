import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/project/runtime/project_workspace_graph_reconciler.dart';
import 'package:hermes/core/wire_case.dart';

export 'package:hermes/features/project/runtime/project_plan_validator.dart'
    show ProjectPlanValidationIssue, ProjectPlanValidationSeverity;

/// Canonical result of initial planning.
///
/// The patch is ready for application to the real project. Core project
/// creation consumes this result directly and does not first materialize a
/// temporary project or convert the plan into a second DTO.
class ProjectInitialPlanResult {
  const ProjectInitialPlanResult({
    required this.patch,
    this.planningMetrics = const PlanningMetrics(),
    this.planningError,
  });

  final ProjectPlanPatch patch;
  final PlanningMetrics planningMetrics;
  final String? planningError;
}

/// Bounded, read-only planning context collected before a plan model call.
class ProjectEvidenceSnapshot {
  final String workspaceName;
  final WorkspaceDiscoveryProfile workspaceProfile;
  final List<String> rootEntries;
  final bool gitAvailable;
  final List<String> changedFiles;
  final List<String> projectArtifactPaths;
  final List<String> taskArtifactIds;
  final List<String> recentTaskResults;
  final List<String> recentGateFailures;
  final List<String> criterionSummaries;
  final List<String> milestoneSummaries;
  final List<String> activeMemory;
  final List<String> unresolvedQuestions;
  final List<String> readyTasks;
  final List<String> blockedTasks;
  final List<String> recentlyCompletedTasks;
  final List<String> verificationCommands;
  final ProjectWorkspaceGraph workspaceGraph;
  final ProjectWorkspaceGraphReconciliation? workspaceGraphReconciliation;
  final ProjectWorkspaceContextSelection workspaceContext;
  final DateTime collectedAt;

  ProjectEvidenceSnapshot({
    required this.workspaceName,
    WorkspaceDiscoveryProfile? workspaceProfile,
    this.rootEntries = const [],
    this.gitAvailable = false,
    this.changedFiles = const [],
    this.projectArtifactPaths = const [],
    this.taskArtifactIds = const [],
    this.recentTaskResults = const [],
    this.recentGateFailures = const [],
    this.criterionSummaries = const [],
    this.milestoneSummaries = const [],
    this.activeMemory = const [],
    this.unresolvedQuestions = const [],
    this.readyTasks = const [],
    this.blockedTasks = const [],
    this.recentlyCompletedTasks = const [],
    this.verificationCommands = const [],
    ProjectWorkspaceGraph? workspaceGraph,
    this.workspaceGraphReconciliation,
    ProjectWorkspaceContextSelection? workspaceContext,
    required this.collectedAt,
  }) : workspaceProfile =
           workspaceProfile ??
           WorkspaceDiscoveryProfile(workspaceName: workspaceName),
       workspaceGraph = workspaceGraph ?? ProjectWorkspaceGraph.empty(),
       workspaceContext =
           workspaceContext ??
           const ProjectWorkspaceContextSelection(
             orientation: '',
             nodes: [],
             edges: [],
             maxCharacters: 0,
             usedCharacters: 0,
             truncated: false,
           );

  Map<String, dynamic> toMap() => snakeCaseMap({
    'workspaceName': workspaceName,
    'workspaceProfile': workspaceProfile.toMap(),
    'rootEntries': rootEntries,
    'gitAvailable': gitAvailable,
    'changedFiles': changedFiles,
    'projectArtifactPaths': projectArtifactPaths,
    'taskArtifactIds': taskArtifactIds,
    'recentTaskResults': recentTaskResults,
    'recentGateFailures': recentGateFailures,
    'criterionSummaries': criterionSummaries,
    'milestoneSummaries': milestoneSummaries,
    'activeMemory': activeMemory,
    'unresolvedQuestions': unresolvedQuestions,
    'readyTasks': readyTasks,
    'blockedTasks': blockedTasks,
    'recentlyCompletedTasks': recentlyCompletedTasks,
    'verificationCommands': verificationCommands,
    'workspaceGraph': workspaceGraph.toMap(),
    'workspaceGraphReconciliation': workspaceGraphReconciliation?.toMap(),
    'workspaceContext': workspaceContext.toMap(),
    'collectedAt': collectedAt.toIso8601String(),
  });
}

/// Typed planning metadata passed from discovery to a model planner.
/// Wire conversion is intentionally local to the planning protocol adapter.
class ProjectPlanningWorkspaceMetadata {
  ProjectPlanningWorkspaceMetadata({
    required this.evidence,
    required this.commandExecutionApproved,
  }) : _wireOverride = null;

  ProjectPlanningWorkspaceMetadata.fromWire(Map<String, Object?> wire)
    : evidence = null,
      commandExecutionApproved =
          wire['command_execution_approved'] == true ||
          wire['commandExecutionApproved'] == true,
      _wireOverride = Map.unmodifiable(wire);

  final ProjectEvidenceSnapshot? evidence;
  final bool commandExecutionApproved;
  final Map<String, Object?>? _wireOverride;

  Map<String, Object?> toWire() => snakeCaseMap(
    _wireOverride ??
        <String, Object?>{
          ...evidence!.toMap(),
          'commandExecutionApproved': commandExecutionApproved,
        },
  );
}

/// Pure result of evaluating whether the persisted project state is complete.
class ProjectCompletionAssessment {
  final bool complete;
  final String finalSummary;
  final List<String> remainingCriteria;
  final List<String> supportedCriterionIds;
  final List<PendingProjectQuestion> openQuestions;

  const ProjectCompletionAssessment({
    required this.complete,
    required this.finalSummary,
    required this.remainingCriteria,
    this.supportedCriterionIds = const [],
    required this.openQuestions,
  });
}

/// Result of a planner invocation that edits a draft through incremental
/// commands and commits it through the planning registry.
class ProjectIncrementalPlanResult {
  final ProjectAggregate project;
  final bool committed;
  final bool changed;
  final bool awaitingApproval;
  final int modelCalls;
  final PlanningMetrics planningMetrics;
  final String? error;
  final ProjectPlanPatch? patch;

  const ProjectIncrementalPlanResult({
    required this.project,
    required this.committed,
    required this.changed,
    required this.awaitingApproval,
    required this.modelCalls,
    this.planningMetrics = const PlanningMetrics(),
    this.error,
    this.patch,
  });
}

/// Boundary between deterministic project orchestration and model-backed
/// project planning decisions. Incremental revision is the normal planning
/// protocol; legacy initial-plan DTOs remain above only for wire compatibility.
abstract interface class ProjectPlanner {
  Future<ProjectIncrementalPlanResult> maintainWorkspaceGraph({
    required ModelConversationPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

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
  });

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
  });
}

/// Domain-specific structured evaluator used by project completion.
abstract interface class ProjectCompletionEvaluator {
  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ModelConversationPort client,
    required String baseSystemPrompt,
    required ProjectAggregate project,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}
