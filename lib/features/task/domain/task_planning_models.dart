import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/shared_kernel/workspace_discovery_profile.dart';
import 'package:hermes/features/task/domain/task.dart';

part 'task_planning_models.mapper.dart';

typedef TaskCompactionStatusSink = void Function(String status);

/// Typed planning context exchanged between the project and task boundaries.
@MappableClass(generateMethods: GenerateMethods.encode)
class TaskPlanningContext with TaskPlanningContextMappable {
  final String projectGoal;
  final String projectTaskTitle;
  final String projectTaskObjective;
  final List<String> knownFacts;
  final String workspaceOrientation;
  final List<String> workspaceContext;
  final List<String> doneCriteria;
  final List<String> outOfScope;
  final List<TaskArtifact> expectedArtifacts;
  final List<TaskGate> requiredGates;
  final List<String> criterionIds;
  final List<TaskProjectCriterion> criteria;
  final List<TaskProjectEvidenceExpectation> expectedEvidence;
  final List<String> readPaths;
  final List<String> writePaths;
  final int maxSteps;

  const TaskPlanningContext({
    required this.projectGoal,
    this.projectTaskTitle = '',
    required this.projectTaskObjective,
    this.knownFacts = const [],
    this.workspaceOrientation = '',
    this.workspaceContext = const [],
    this.doneCriteria = const [],
    this.outOfScope = const [],
    this.expectedArtifacts = const [],
    this.requiredGates = const [],
    this.criterionIds = const [],
    this.criteria = const [],
    this.expectedEvidence = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.maxSteps = 3,
  });
}

/// Transient project evidence used while executing one task document.
class TaskExecutionRequest {
  final List<String> criterionIds;
  final List<TaskProjectCriterion> criteria;
  final List<TaskProjectEvidenceExpectation> expectedEvidence;

  const TaskExecutionRequest({
    this.criterionIds = const [],
    this.criteria = const [],
    this.expectedEvidence = const [],
  });

  factory TaskExecutionRequest.fromPlanningContext(
    TaskPlanningContext context,
  ) => TaskExecutionRequest(
    criterionIds: context.criterionIds,
    criteria: context.criteria,
    expectedEvidence: context.expectedEvidence,
  );
}

/// Immutable workspace facts captured for task planning and recovery.
@MappableClass(generateMethods: GenerateMethods.encode, ignoreNull: true)
class WorkspaceMetadata with WorkspaceMetadataMappable {
  final String? workspaceName;
  final List<String> rootFiles;
  final bool gitAvailable;
  final bool commandExecutionApproved;
  final List<String> existingTaskIds;
  final WorkspaceDiscoveryProfile? workspaceProfile;

  const WorkspaceMetadata({
    this.workspaceName,
    this.rootFiles = const [],
    this.gitAvailable = false,
    this.commandExecutionApproved = false,
    this.existingTaskIds = const [],
    this.workspaceProfile,
  });
}
