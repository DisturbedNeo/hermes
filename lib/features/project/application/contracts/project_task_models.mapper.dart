// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project_task_models.dart';

/// @nodoc
class ProjectTaskNodeMapper extends ClassMapperBase<ProjectTaskNode> {
  ProjectTaskNodeMapper._();

  static ProjectTaskNodeMapper? _instance;
  static ProjectTaskNodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskNodeMapper._());
      TaskStatusMapper.ensureInitialized();
      TaskGateMapper.ensureInitialized();
      TaskPriorityMapper.ensureInitialized();
      TaskRiskMapper.ensureInitialized();
      ProjectRiskReductionMapper.ensureInitialized();
      TaskEffortMapper.ensureInitialized();
      TaskEvidenceExpectationMapper.ensureInitialized();
      TaskArtifactMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTaskNode';

  static String _$id(ProjectTaskNode v) => v.id;
  static const Field<ProjectTaskNode, String> _f$id = Field('id', _$id);
  static String _$title(ProjectTaskNode v) => v.title;
  static const Field<ProjectTaskNode, String> _f$title = Field(
    'title',
    _$title,
  );
  static String _$objective(ProjectTaskNode v) => v.objective;
  static const Field<ProjectTaskNode, String> _f$objective = Field(
    'objective',
    _$objective,
  );
  static TaskStatus _$status(ProjectTaskNode v) => v.status;
  static const Field<ProjectTaskNode, TaskStatus> _f$status = Field(
    'status',
    _$status,
  );
  static List<TaskGate> _$gates(ProjectTaskNode v) => v.gates;
  static const Field<ProjectTaskNode, List<TaskGate>> _f$gates = Field(
    'gates',
    _$gates,
    opt: true,
    def: const [],
  );
  static List<String> _$constraints(ProjectTaskNode v) => v.constraints;
  static const Field<ProjectTaskNode, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    opt: true,
    def: const [],
  );
  static List<String> _$successCriteria(ProjectTaskNode v) => v.successCriteria;
  static const Field<ProjectTaskNode, List<String>> _f$successCriteria = Field(
    'successCriteria',
    _$successCriteria,
    opt: true,
    def: const [],
  );
  static List<String> _$criterionIds(ProjectTaskNode v) => v.criterionIds;
  static const Field<ProjectTaskNode, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
  );
  static String? _$milestoneId(ProjectTaskNode v) => v.milestoneId;
  static const Field<ProjectTaskNode, String> _f$milestoneId = Field(
    'milestoneId',
    _$milestoneId,
    opt: true,
  );
  static List<String> _$dependsOnTaskIds(ProjectTaskNode v) =>
      v.dependsOnTaskIds;
  static const Field<ProjectTaskNode, List<String>> _f$dependsOnTaskIds = Field(
    'dependsOnTaskIds',
    _$dependsOnTaskIds,
    opt: true,
    def: const [],
  );
  static TaskPriority _$priority(ProjectTaskNode v) => v.priority;
  static const Field<ProjectTaskNode, TaskPriority> _f$priority = Field(
    'priority',
    _$priority,
    opt: true,
    def: TaskPriority.normal,
  );
  static TaskRisk _$risk(ProjectTaskNode v) => v.risk;
  static const Field<ProjectTaskNode, TaskRisk> _f$risk = Field(
    'risk',
    _$risk,
    opt: true,
    def: TaskRisk.unknown,
  );
  static ProjectRiskReduction _$riskReduction(ProjectTaskNode v) =>
      v.riskReduction;
  static const Field<ProjectTaskNode, ProjectRiskReduction> _f$riskReduction =
      Field(
        'riskReduction',
        _$riskReduction,
        opt: true,
        def: ProjectRiskReduction.none,
      );
  static TaskEffort _$effort(ProjectTaskNode v) => v.effort;
  static const Field<ProjectTaskNode, TaskEffort> _f$effort = Field(
    'effort',
    _$effort,
    opt: true,
    def: TaskEffort.small,
  );
  static String _$selectionRationale(ProjectTaskNode v) => v.selectionRationale;
  static const Field<ProjectTaskNode, String> _f$selectionRationale = Field(
    'selectionRationale',
    _$selectionRationale,
    opt: true,
    def: '',
  );
  static int _$revisionIntroduced(ProjectTaskNode v) => v.revisionIntroduced;
  static const Field<ProjectTaskNode, int> _f$revisionIntroduced = Field(
    'revisionIntroduced',
    _$revisionIntroduced,
    opt: true,
    def: 1,
  );
  static int _$revisionUpdated(ProjectTaskNode v) => v.revisionUpdated;
  static const Field<ProjectTaskNode, int> _f$revisionUpdated = Field(
    'revisionUpdated',
    _$revisionUpdated,
    opt: true,
    def: 1,
  );
  static List<TaskEvidenceExpectation> _$expectedEvidence(ProjectTaskNode v) =>
      v.expectedEvidence;
  static const Field<ProjectTaskNode, List<TaskEvidenceExpectation>>
  _f$expectedEvidence = Field(
    'expectedEvidence',
    _$expectedEvidence,
    opt: true,
    def: const [],
  );
  static List<String> _$readPaths(ProjectTaskNode v) => v.readPaths;
  static const Field<ProjectTaskNode, List<String>> _f$readPaths = Field(
    'readPaths',
    _$readPaths,
    opt: true,
    def: const [],
  );
  static List<String> _$writePaths(ProjectTaskNode v) => v.writePaths;
  static const Field<ProjectTaskNode, List<String>> _f$writePaths = Field(
    'writePaths',
    _$writePaths,
    opt: true,
    def: const [],
  );
  static List<String> _$doneCriteria(ProjectTaskNode v) => v.doneCriteria;
  static const Field<ProjectTaskNode, List<String>> _f$doneCriteria = Field(
    'doneCriteria',
    _$doneCriteria,
    opt: true,
    def: const [],
  );
  static List<String> _$outOfScope(ProjectTaskNode v) => v.outOfScope;
  static const Field<ProjectTaskNode, List<String>> _f$outOfScope = Field(
    'outOfScope',
    _$outOfScope,
    opt: true,
    def: const [],
  );
  static List<String> _$context(ProjectTaskNode v) => v.context;
  static const Field<ProjectTaskNode, List<String>> _f$context = Field(
    'context',
    _$context,
    opt: true,
    def: const [],
  );
  static List<TaskArtifact> _$expectedArtifacts(ProjectTaskNode v) =>
      v.expectedArtifacts;
  static const Field<ProjectTaskNode, List<TaskArtifact>> _f$expectedArtifacts =
      Field('expectedArtifacts', _$expectedArtifacts, opt: true, def: const []);
  static String? _$recoveryIncidentId(ProjectTaskNode v) =>
      v.recoveryIncidentId;
  static const Field<ProjectTaskNode, String> _f$recoveryIncidentId = Field(
    'recoveryIncidentId',
    _$recoveryIncidentId,
    opt: true,
  );
  static String _$fingerprint(ProjectTaskNode v) => v.fingerprint;
  static const Field<ProjectTaskNode, String> _f$fingerprint = Field(
    'fingerprint',
    _$fingerprint,
    opt: true,
    def: '',
  );
  static String? _$rejectionReason(ProjectTaskNode v) => v.rejectionReason;
  static const Field<ProjectTaskNode, String> _f$rejectionReason = Field(
    'rejectionReason',
    _$rejectionReason,
    opt: true,
  );
  static String? _$failureKey(ProjectTaskNode v) => v.failureKey;
  static const Field<ProjectTaskNode, String> _f$failureKey = Field(
    'failureKey',
    _$failureKey,
    opt: true,
  );
  static String? _$failureGateId(ProjectTaskNode v) => v.failureGateId;
  static const Field<ProjectTaskNode, String> _f$failureGateId = Field(
    'failureGateId',
    _$failureGateId,
    opt: true,
  );
  static List<String> _$failureErrorCodes(ProjectTaskNode v) =>
      v.failureErrorCodes;
  static const Field<ProjectTaskNode, List<String>> _f$failureErrorCodes =
      Field('failureErrorCodes', _$failureErrorCodes, opt: true, def: const []);
  static int _$unresolvedErrorCount(ProjectTaskNode v) =>
      v.unresolvedErrorCount;
  static const Field<ProjectTaskNode, int> _f$unresolvedErrorCount = Field(
    'unresolvedErrorCount',
    _$unresolvedErrorCount,
    opt: true,
    def: 0,
  );
  static String? _$planningError(ProjectTaskNode v) => v.planningError;
  static const Field<ProjectTaskNode, String> _f$planningError = Field(
    'planningError',
    _$planningError,
    opt: true,
  );
  static DateTime _$createdAt(ProjectTaskNode v) => v.createdAt;
  static const Field<ProjectTaskNode, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(ProjectTaskNode v) => v.updatedAt;
  static const Field<ProjectTaskNode, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<ProjectTaskNode> fields = const {
    #id: _f$id,
    #title: _f$title,
    #objective: _f$objective,
    #status: _f$status,
    #gates: _f$gates,
    #constraints: _f$constraints,
    #successCriteria: _f$successCriteria,
    #criterionIds: _f$criterionIds,
    #milestoneId: _f$milestoneId,
    #dependsOnTaskIds: _f$dependsOnTaskIds,
    #priority: _f$priority,
    #risk: _f$risk,
    #riskReduction: _f$riskReduction,
    #effort: _f$effort,
    #selectionRationale: _f$selectionRationale,
    #revisionIntroduced: _f$revisionIntroduced,
    #revisionUpdated: _f$revisionUpdated,
    #expectedEvidence: _f$expectedEvidence,
    #readPaths: _f$readPaths,
    #writePaths: _f$writePaths,
    #doneCriteria: _f$doneCriteria,
    #outOfScope: _f$outOfScope,
    #context: _f$context,
    #expectedArtifacts: _f$expectedArtifacts,
    #recoveryIncidentId: _f$recoveryIncidentId,
    #fingerprint: _f$fingerprint,
    #rejectionReason: _f$rejectionReason,
    #failureKey: _f$failureKey,
    #failureGateId: _f$failureGateId,
    #failureErrorCodes: _f$failureErrorCodes,
    #unresolvedErrorCount: _f$unresolvedErrorCount,
    #planningError: _f$planningError,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectTaskNode _instantiate(DecodingData data) {
    return ProjectTaskNode(
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      objective: data.dec(_f$objective),
      status: data.dec(_f$status),
      gates: data.dec(_f$gates),
      constraints: data.dec(_f$constraints),
      successCriteria: data.dec(_f$successCriteria),
      criterionIds: data.dec(_f$criterionIds),
      milestoneId: data.dec(_f$milestoneId),
      dependsOnTaskIds: data.dec(_f$dependsOnTaskIds),
      priority: data.dec(_f$priority),
      risk: data.dec(_f$risk),
      riskReduction: data.dec(_f$riskReduction),
      effort: data.dec(_f$effort),
      selectionRationale: data.dec(_f$selectionRationale),
      revisionIntroduced: data.dec(_f$revisionIntroduced),
      revisionUpdated: data.dec(_f$revisionUpdated),
      expectedEvidence: data.dec(_f$expectedEvidence),
      readPaths: data.dec(_f$readPaths),
      writePaths: data.dec(_f$writePaths),
      doneCriteria: data.dec(_f$doneCriteria),
      outOfScope: data.dec(_f$outOfScope),
      context: data.dec(_f$context),
      expectedArtifacts: data.dec(_f$expectedArtifacts),
      recoveryIncidentId: data.dec(_f$recoveryIncidentId),
      fingerprint: data.dec(_f$fingerprint),
      rejectionReason: data.dec(_f$rejectionReason),
      failureKey: data.dec(_f$failureKey),
      failureGateId: data.dec(_f$failureGateId),
      failureErrorCodes: data.dec(_f$failureErrorCodes),
      unresolvedErrorCount: data.dec(_f$unresolvedErrorCount),
      planningError: data.dec(_f$planningError),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTaskNode fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTaskNode>(map);
  }

  static ProjectTaskNode fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTaskNode>(json);
  }
}

/// @nodoc
mixin ProjectTaskNodeMappable {
  String toJson() {
    return ProjectTaskNodeMapper.ensureInitialized()
        .encodeJson<ProjectTaskNode>(this as ProjectTaskNode);
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskNodeMapper.ensureInitialized().encodeMap<ProjectTaskNode>(
      this as ProjectTaskNode,
    );
  }
}
