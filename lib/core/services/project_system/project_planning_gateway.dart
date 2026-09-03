import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';

/// Pure result of creating the initial planning state for a project.
class ProjectInitialisation {
  final String title;
  final String refinedGoal;
  final List<String> successCriteria;
  final List<String> constraints;
  final List<String> knownFacts;
  final List<PendingProjectQuestion> openQuestions;
  final List<ProjectTask> backlog;
  final List<ProjectCriterion> criteria;
  final List<ProjectMilestone> milestones;
  final List<ProjectMemoryEntry> memory;

  const ProjectInitialisation({
    required this.title,
    required this.refinedGoal,
    required this.successCriteria,
    required this.constraints,
    required this.knownFacts,
    required this.openQuestions,
    required this.backlog,
    this.criteria = const [],
    this.milestones = const [],
    this.memory = const [],
  });
}

/// Bounded, read-only planning context collected before a plan model call.
class ProjectEvidenceSnapshot {
  final String workspaceName;
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
  final DateTime collectedAt;

  const ProjectEvidenceSnapshot({
    required this.workspaceName,
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
    required this.collectedAt,
  });

  Map<String, dynamic> toMap() => {
    'workspaceName': workspaceName,
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
    'collectedAt': collectedAt.toIso8601String(),
  };
}

/// Pure result of evaluating whether the persisted project state is complete.
class ProjectCompletionAssessment {
  final bool complete;
  final String finalSummary;
  final List<String> remainingCriteria;
  final List<PendingProjectQuestion> openQuestions;

  const ProjectCompletionAssessment({
    required this.complete,
    required this.finalSummary,
    required this.remainingCriteria,
    required this.openQuestions,
  });
}

/// Boundary between deterministic project orchestration and model-backed
/// planning decisions.
///
/// Implementations return proposed data only. [ProjectService] remains
/// responsible for validation, state transitions, and persistence.
abstract interface class ProjectPlanningGateway {
  Future<ProjectInitialisation> initializeProject({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required String originalGoal,
    required Map<String, dynamic> workspaceMetadata,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<ProjectPlanProposal> revisePlan({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectEvidenceSnapshot evidenceSnapshot,
    required List<ProjectPlanRevisionTrigger> triggers,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  /// Performs the sole model repair pass allowed for an invalid proposal.
  Future<ProjectPlanProposal?> repairPlanProposal({
    required ChatClient client,
    required String baseSystemPrompt,
    required WorkspaceAttachment workspace,
    required ProjectState project,
    required ProjectPlanProposal proposal,
    required List<Map<String, String>> validationIssues,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<List<ProjectTask>> splitTask({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    required ProjectTask oversizedTask,
    required List<String> violations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<ProjectCompletionAssessment> evaluateCompletion({
    required ChatClient client,
    required String baseSystemPrompt,
    required ProjectState project,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}
