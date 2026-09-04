// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'task_service.dart';

/// @nodoc
class TaskPlanningContextMapper extends ClassMapperBase<TaskPlanningContext> {
  TaskPlanningContextMapper._();

  static TaskPlanningContextMapper? _instance;
  static TaskPlanningContextMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskPlanningContextMapper._());
      TaskArtifactMapper.ensureInitialized();
      TaskGateMapper.ensureInitialized();
      TaskProjectCriterionMapper.ensureInitialized();
      TaskProjectEvidenceExpectationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskPlanningContext';

  static String _$projectGoal(TaskPlanningContext v) => v.projectGoal;
  static const Field<TaskPlanningContext, String> _f$projectGoal = Field(
    'projectGoal',
    _$projectGoal,
  );
  static String _$projectTaskTitle(TaskPlanningContext v) => v.projectTaskTitle;
  static const Field<TaskPlanningContext, String> _f$projectTaskTitle = Field(
    'projectTaskTitle',
    _$projectTaskTitle,
    opt: true,
    def: '',
  );
  static String _$projectTaskObjective(TaskPlanningContext v) =>
      v.projectTaskObjective;
  static const Field<TaskPlanningContext, String> _f$projectTaskObjective =
      Field('projectTaskObjective', _$projectTaskObjective);
  static List<String> _$knownFacts(TaskPlanningContext v) => v.knownFacts;
  static const Field<TaskPlanningContext, List<String>> _f$knownFacts = Field(
    'knownFacts',
    _$knownFacts,
    opt: true,
    def: const [],
  );
  static List<String> _$doneCriteria(TaskPlanningContext v) => v.doneCriteria;
  static const Field<TaskPlanningContext, List<String>> _f$doneCriteria = Field(
    'doneCriteria',
    _$doneCriteria,
    opt: true,
    def: const [],
  );
  static List<String> _$outOfScope(TaskPlanningContext v) => v.outOfScope;
  static const Field<TaskPlanningContext, List<String>> _f$outOfScope = Field(
    'outOfScope',
    _$outOfScope,
    opt: true,
    def: const [],
  );
  static List<TaskArtifact> _$expectedArtifacts(TaskPlanningContext v) =>
      v.expectedArtifacts;
  static const Field<TaskPlanningContext, List<TaskArtifact>>
  _f$expectedArtifacts = Field(
    'expectedArtifacts',
    _$expectedArtifacts,
    opt: true,
    def: const [],
  );
  static List<TaskGate> _$requiredGates(TaskPlanningContext v) =>
      v.requiredGates;
  static const Field<TaskPlanningContext, List<TaskGate>> _f$requiredGates =
      Field('requiredGates', _$requiredGates, opt: true, def: const []);
  static List<String> _$criterionIds(TaskPlanningContext v) => v.criterionIds;
  static const Field<TaskPlanningContext, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
  );
  static List<TaskProjectCriterion> _$criteria(TaskPlanningContext v) =>
      v.criteria;
  static const Field<TaskPlanningContext, List<TaskProjectCriterion>>
  _f$criteria = Field('criteria', _$criteria, opt: true, def: const []);
  static List<TaskProjectEvidenceExpectation> _$expectedEvidence(
    TaskPlanningContext v,
  ) => v.expectedEvidence;
  static const Field<TaskPlanningContext, List<TaskProjectEvidenceExpectation>>
  _f$expectedEvidence = Field(
    'expectedEvidence',
    _$expectedEvidence,
    opt: true,
    def: const [],
  );
  static List<String> _$readPaths(TaskPlanningContext v) => v.readPaths;
  static const Field<TaskPlanningContext, List<String>> _f$readPaths = Field(
    'readPaths',
    _$readPaths,
    opt: true,
    def: const [],
  );
  static List<String> _$writePaths(TaskPlanningContext v) => v.writePaths;
  static const Field<TaskPlanningContext, List<String>> _f$writePaths = Field(
    'writePaths',
    _$writePaths,
    opt: true,
    def: const [],
  );
  static bool _$legacyWriteAccess(TaskPlanningContext v) => v.legacyWriteAccess;
  static const Field<TaskPlanningContext, bool> _f$legacyWriteAccess = Field(
    'legacyWriteAccess',
    _$legacyWriteAccess,
    opt: true,
    def: false,
  );
  static int _$maxSteps(TaskPlanningContext v) => v.maxSteps;
  static const Field<TaskPlanningContext, int> _f$maxSteps = Field(
    'maxSteps',
    _$maxSteps,
    opt: true,
    def: 3,
  );

  @override
  final MappableFields<TaskPlanningContext> fields = const {
    #projectGoal: _f$projectGoal,
    #projectTaskTitle: _f$projectTaskTitle,
    #projectTaskObjective: _f$projectTaskObjective,
    #knownFacts: _f$knownFacts,
    #doneCriteria: _f$doneCriteria,
    #outOfScope: _f$outOfScope,
    #expectedArtifacts: _f$expectedArtifacts,
    #requiredGates: _f$requiredGates,
    #criterionIds: _f$criterionIds,
    #criteria: _f$criteria,
    #expectedEvidence: _f$expectedEvidence,
    #readPaths: _f$readPaths,
    #writePaths: _f$writePaths,
    #legacyWriteAccess: _f$legacyWriteAccess,
    #maxSteps: _f$maxSteps,
  };

  static TaskPlanningContext _instantiate(DecodingData data) {
    return TaskPlanningContext(
      projectGoal: data.dec(_f$projectGoal),
      projectTaskTitle: data.dec(_f$projectTaskTitle),
      projectTaskObjective: data.dec(_f$projectTaskObjective),
      knownFacts: data.dec(_f$knownFacts),
      doneCriteria: data.dec(_f$doneCriteria),
      outOfScope: data.dec(_f$outOfScope),
      expectedArtifacts: data.dec(_f$expectedArtifacts),
      requiredGates: data.dec(_f$requiredGates),
      criterionIds: data.dec(_f$criterionIds),
      criteria: data.dec(_f$criteria),
      expectedEvidence: data.dec(_f$expectedEvidence),
      readPaths: data.dec(_f$readPaths),
      writePaths: data.dec(_f$writePaths),
      legacyWriteAccess: data.dec(_f$legacyWriteAccess),
      maxSteps: data.dec(_f$maxSteps),
    );
  }

  @override
  final Function instantiate = _instantiate;
}

/// @nodoc
mixin TaskPlanningContextMappable {
  String toJson() {
    return TaskPlanningContextMapper.ensureInitialized()
        .encodeJson<TaskPlanningContext>(this as TaskPlanningContext);
  }

  Map<String, dynamic> toMap() {
    return TaskPlanningContextMapper.ensureInitialized()
        .encodeMap<TaskPlanningContext>(this as TaskPlanningContext);
  }
}

/// @nodoc
class WorkspaceMetadataMapper extends ClassMapperBase<WorkspaceMetadata> {
  WorkspaceMetadataMapper._();

  static WorkspaceMetadataMapper? _instance;
  static WorkspaceMetadataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceMetadataMapper._());
      WorkspaceDiscoveryProfileMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkspaceMetadata';

  static String? _$workspaceName(WorkspaceMetadata v) => v.workspaceName;
  static const Field<WorkspaceMetadata, String> _f$workspaceName = Field(
    'workspaceName',
    _$workspaceName,
    opt: true,
  );
  static List<String> _$rootFiles(WorkspaceMetadata v) => v.rootFiles;
  static const Field<WorkspaceMetadata, List<String>> _f$rootFiles = Field(
    'rootFiles',
    _$rootFiles,
    opt: true,
    def: const [],
  );
  static bool _$gitAvailable(WorkspaceMetadata v) => v.gitAvailable;
  static const Field<WorkspaceMetadata, bool> _f$gitAvailable = Field(
    'gitAvailable',
    _$gitAvailable,
    opt: true,
    def: false,
  );
  static bool _$commandExecutionApproved(WorkspaceMetadata v) =>
      v.commandExecutionApproved;
  static const Field<WorkspaceMetadata, bool> _f$commandExecutionApproved =
      Field(
        'commandExecutionApproved',
        _$commandExecutionApproved,
        opt: true,
        def: false,
      );
  static List<String> _$existingTaskIds(WorkspaceMetadata v) =>
      v.existingTaskIds;
  static const Field<WorkspaceMetadata, List<String>> _f$existingTaskIds =
      Field('existingTaskIds', _$existingTaskIds, opt: true, def: const []);
  static WorkspaceDiscoveryProfile? _$workspaceProfile(WorkspaceMetadata v) =>
      v.workspaceProfile;
  static const Field<WorkspaceMetadata, WorkspaceDiscoveryProfile>
  _f$workspaceProfile = Field(
    'workspaceProfile',
    _$workspaceProfile,
    opt: true,
  );

  @override
  final MappableFields<WorkspaceMetadata> fields = const {
    #workspaceName: _f$workspaceName,
    #rootFiles: _f$rootFiles,
    #gitAvailable: _f$gitAvailable,
    #commandExecutionApproved: _f$commandExecutionApproved,
    #existingTaskIds: _f$existingTaskIds,
    #workspaceProfile: _f$workspaceProfile,
  };
  @override
  final bool ignoreNull = true;

  static WorkspaceMetadata _instantiate(DecodingData data) {
    return WorkspaceMetadata(
      workspaceName: data.dec(_f$workspaceName),
      rootFiles: data.dec(_f$rootFiles),
      gitAvailable: data.dec(_f$gitAvailable),
      commandExecutionApproved: data.dec(_f$commandExecutionApproved),
      existingTaskIds: data.dec(_f$existingTaskIds),
      workspaceProfile: data.dec(_f$workspaceProfile),
    );
  }

  @override
  final Function instantiate = _instantiate;
}

/// @nodoc
mixin WorkspaceMetadataMappable {
  String toJson() {
    return WorkspaceMetadataMapper.ensureInitialized()
        .encodeJson<WorkspaceMetadata>(this as WorkspaceMetadata);
  }

  Map<String, dynamic> toMap() {
    return WorkspaceMetadataMapper.ensureInitialized()
        .encodeMap<WorkspaceMetadata>(this as WorkspaceMetadata);
  }
}

