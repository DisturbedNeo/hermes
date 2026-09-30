import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/shared_kernel/planning_metrics.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_completion_port.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/shared_kernel/workspace_discovery_service.dart';

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

  Map<String, dynamic> toMap() => {
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
    'workspaceContext': workspaceContext.toMap(),
    'collectedAt': collectedAt.toIso8601String(),
  };
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
  final ProjectState project;
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
/// project planning decisions. All planning modes return the same typed patch
/// protocol; there is no legacy initial-plan branch.
abstract interface class ProjectPlanner {
  Future<ProjectInitialPlanResult> initializePlan({
    required ModelCompletionPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<ProjectInitialPlanResult?> repairInitialPlan({
    required ModelCompletionPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    required ProjectInitialPlanResult initialPlan,
    required List<Map<String, String>> validationIssues,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
  Future<ProjectIncrementalPlanResult> revisePlanWithCommands({
    required ModelCompletionPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    required ProjectPlanApprovalPolicy approvalPolicy,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<ProjectIncrementalPlanResult> splitTaskWithCommands({
    required ModelCompletionPort client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectTaskNode oversizedTask,
    required List<String> violations,
    required ProjectPlanApprovalPolicy approvalPolicy,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}

/// Domain-specific structured evaluator used by project completion.
abstract interface class ProjectCompletionEvaluator {
  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ModelCompletionPort client,
    required String baseSystemPrompt,
    required ProjectState project,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}
