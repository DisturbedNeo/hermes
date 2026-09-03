// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project.dart';

/// @nodoc

class ProjectStatusMapper extends EnumMapper<ProjectStatus> {
  ProjectStatusMapper._();

  static ProjectStatusMapper? _instance;
  static ProjectStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectStatusMapper._());
    }
    return _instance!;
  }

  static ProjectStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectStatus decode(dynamic value) {
    switch (value) {
      case r'initializing':
        return ProjectStatus.initializing;
      case r'active':
        return ProjectStatus.active;
      case r'paused':
        return ProjectStatus.paused;
      case 'running_task':
        return ProjectStatus.runningTask;
      case 'reviewing_task':
        return ProjectStatus.reviewingTask;
      case 'waiting_for_user':
        return ProjectStatus.waitingForUser;
      case r'blocked':
        return ProjectStatus.blocked;
      case r'completed':
        return ProjectStatus.completed;
      case r'failed':
        return ProjectStatus.failed;
      case r'cancelled':
        return ProjectStatus.cancelled;
      default:
        return ProjectStatus.values[1];
    }
  }

  @override
  dynamic encode(ProjectStatus self) {
    switch (self) {
      case ProjectStatus.initializing:
        return r'initializing';
      case ProjectStatus.active:
        return r'active';
      case ProjectStatus.paused:
        return r'paused';
      case ProjectStatus.runningTask:
        return 'running_task';
      case ProjectStatus.reviewingTask:
        return 'reviewing_task';
      case ProjectStatus.waitingForUser:
        return 'waiting_for_user';
      case ProjectStatus.blocked:
        return r'blocked';
      case ProjectStatus.completed:
        return r'completed';
      case ProjectStatus.failed:
        return r'failed';
      case ProjectStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension ProjectStatusMapperExtension on ProjectStatus {
  dynamic toValue() {
    ProjectStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectStatus>(this);
  }
}

/// @nodoc

class ProjectPhaseMapper extends EnumMapper<ProjectPhase> {
  ProjectPhaseMapper._();

  static ProjectPhaseMapper? _instance;
  static ProjectPhaseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectPhaseMapper._());
    }
    return _instance!;
  }

  static ProjectPhase fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectPhase decode(dynamic value) {
    switch (value) {
      case r'discovery':
        return ProjectPhase.discovery;
      case r'planning':
        return ProjectPhase.planning;
      case r'execution':
        return ProjectPhase.execution;
      case r'verification':
        return ProjectPhase.verification;
      case r'finalization':
        return ProjectPhase.finalization;
      default:
        return ProjectPhase.values[0];
    }
  }

  @override
  dynamic encode(ProjectPhase self) {
    switch (self) {
      case ProjectPhase.discovery:
        return r'discovery';
      case ProjectPhase.planning:
        return r'planning';
      case ProjectPhase.execution:
        return r'execution';
      case ProjectPhase.verification:
        return r'verification';
      case ProjectPhase.finalization:
        return r'finalization';
    }
  }
}

/// @nodoc

extension ProjectPhaseMapperExtension on ProjectPhase {
  String toValue() {
    ProjectPhaseMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectPhase>(this) as String;
  }
}

/// @nodoc

class ProjectTaskStatusMapper extends EnumMapper<ProjectTaskStatus> {
  ProjectTaskStatusMapper._();

  static ProjectTaskStatusMapper? _instance;
  static ProjectTaskStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskStatusMapper._());
    }
    return _instance!;
  }

  static ProjectTaskStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectTaskStatus decode(dynamic value) {
    switch (value) {
      case r'queued':
        return ProjectTaskStatus.queued;
      case r'proposed':
        return ProjectTaskStatus.proposed;
      case r'approved':
        return ProjectTaskStatus.approved;
      case r'running':
        return ProjectTaskStatus.running;
      case r'completed':
        return ProjectTaskStatus.completed;
      case r'failed':
        return ProjectTaskStatus.failed;
      case r'rejected':
        return ProjectTaskStatus.rejected;
      case r'split':
        return ProjectTaskStatus.split;
      case r'deferred':
        return ProjectTaskStatus.deferred;
      case r'obsolete':
        return ProjectTaskStatus.obsolete;
      case r'cancelled':
        return ProjectTaskStatus.cancelled;
      default:
        return ProjectTaskStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectTaskStatus self) {
    switch (self) {
      case ProjectTaskStatus.queued:
        return r'queued';
      case ProjectTaskStatus.proposed:
        return r'proposed';
      case ProjectTaskStatus.approved:
        return r'approved';
      case ProjectTaskStatus.running:
        return r'running';
      case ProjectTaskStatus.completed:
        return r'completed';
      case ProjectTaskStatus.failed:
        return r'failed';
      case ProjectTaskStatus.rejected:
        return r'rejected';
      case ProjectTaskStatus.split:
        return r'split';
      case ProjectTaskStatus.deferred:
        return r'deferred';
      case ProjectTaskStatus.obsolete:
        return r'obsolete';
      case ProjectTaskStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension ProjectTaskStatusMapperExtension on ProjectTaskStatus {
  String toValue() {
    ProjectTaskStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectTaskStatus>(this) as String;
  }
}

/// @nodoc

class ProjectCriterionStatusMapper extends EnumMapper<ProjectCriterionStatus> {
  ProjectCriterionStatusMapper._();

  static ProjectCriterionStatusMapper? _instance;
  static ProjectCriterionStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectCriterionStatusMapper._());
    }
    return _instance!;
  }

  static ProjectCriterionStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectCriterionStatus decode(dynamic value) {
    switch (value) {
      case r'unsatisfied':
        return ProjectCriterionStatus.unsatisfied;
      case r'partial':
        return ProjectCriterionStatus.partial;
      case r'satisfied':
        return ProjectCriterionStatus.satisfied;
      case r'invalidated':
        return ProjectCriterionStatus.invalidated;
      default:
        return ProjectCriterionStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectCriterionStatus self) {
    switch (self) {
      case ProjectCriterionStatus.unsatisfied:
        return r'unsatisfied';
      case ProjectCriterionStatus.partial:
        return r'partial';
      case ProjectCriterionStatus.satisfied:
        return r'satisfied';
      case ProjectCriterionStatus.invalidated:
        return r'invalidated';
    }
  }
}

/// @nodoc

extension ProjectCriterionStatusMapperExtension on ProjectCriterionStatus {
  String toValue() {
    ProjectCriterionStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectCriterionStatus>(this)
        as String;
  }
}

/// @nodoc

class ProjectVerificationModeMapper
    extends EnumMapper<ProjectVerificationMode> {
  ProjectVerificationModeMapper._();

  static ProjectVerificationModeMapper? _instance;
  static ProjectVerificationModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectVerificationModeMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectVerificationMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectVerificationMode decode(dynamic value) {
    switch (value) {
      case r'deterministic':
        return ProjectVerificationMode.deterministic;
      case 'model_review':
        return ProjectVerificationMode.modelReview;
      case 'human_approval':
        return ProjectVerificationMode.humanApproval;
      case r'mixed':
        return ProjectVerificationMode.mixed;
      default:
        return ProjectVerificationMode.values[3];
    }
  }

  @override
  dynamic encode(ProjectVerificationMode self) {
    switch (self) {
      case ProjectVerificationMode.deterministic:
        return r'deterministic';
      case ProjectVerificationMode.modelReview:
        return 'model_review';
      case ProjectVerificationMode.humanApproval:
        return 'human_approval';
      case ProjectVerificationMode.mixed:
        return r'mixed';
    }
  }
}

/// @nodoc

extension ProjectVerificationModeMapperExtension on ProjectVerificationMode {
  dynamic toValue() {
    ProjectVerificationModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectVerificationMode>(this);
  }
}

/// @nodoc

class ProjectEvidenceTypeMapper extends EnumMapper<ProjectEvidenceType> {
  ProjectEvidenceTypeMapper._();

  static ProjectEvidenceTypeMapper? _instance;
  static ProjectEvidenceTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectEvidenceTypeMapper._());
    }
    return _instance!;
  }

  static ProjectEvidenceType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectEvidenceType decode(dynamic value) {
    switch (value) {
      case r'gate':
        return ProjectEvidenceType.gate;
      case r'artifact':
        return ProjectEvidenceType.artifact;
      case r'command':
        return ProjectEvidenceType.command;
      case 'task_claim':
        return ProjectEvidenceType.taskClaim;
      case 'user_approval':
        return ProjectEvidenceType.userApproval;
      case r'migrated':
        return ProjectEvidenceType.migrated;
      default:
        return ProjectEvidenceType.values[3];
    }
  }

  @override
  dynamic encode(ProjectEvidenceType self) {
    switch (self) {
      case ProjectEvidenceType.gate:
        return r'gate';
      case ProjectEvidenceType.artifact:
        return r'artifact';
      case ProjectEvidenceType.command:
        return r'command';
      case ProjectEvidenceType.taskClaim:
        return 'task_claim';
      case ProjectEvidenceType.userApproval:
        return 'user_approval';
      case ProjectEvidenceType.migrated:
        return r'migrated';
    }
  }
}

/// @nodoc

extension ProjectEvidenceTypeMapperExtension on ProjectEvidenceType {
  dynamic toValue() {
    ProjectEvidenceTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectEvidenceType>(this);
  }
}

/// @nodoc

class ProjectEvidenceStatusMapper extends EnumMapper<ProjectEvidenceStatus> {
  ProjectEvidenceStatusMapper._();

  static ProjectEvidenceStatusMapper? _instance;
  static ProjectEvidenceStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectEvidenceStatusMapper._());
    }
    return _instance!;
  }

  static ProjectEvidenceStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectEvidenceStatus decode(dynamic value) {
    switch (value) {
      case r'proposed':
        return ProjectEvidenceStatus.proposed;
      case r'accepted':
        return ProjectEvidenceStatus.accepted;
      case r'rejected':
        return ProjectEvidenceStatus.rejected;
      case r'stale':
        return ProjectEvidenceStatus.stale;
      default:
        return ProjectEvidenceStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectEvidenceStatus self) {
    switch (self) {
      case ProjectEvidenceStatus.proposed:
        return r'proposed';
      case ProjectEvidenceStatus.accepted:
        return r'accepted';
      case ProjectEvidenceStatus.rejected:
        return r'rejected';
      case ProjectEvidenceStatus.stale:
        return r'stale';
    }
  }
}

/// @nodoc

extension ProjectEvidenceStatusMapperExtension on ProjectEvidenceStatus {
  String toValue() {
    ProjectEvidenceStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectEvidenceStatus>(this)
        as String;
  }
}

/// @nodoc

class ProjectEvidenceStrengthMapper
    extends EnumMapper<ProjectEvidenceStrength> {
  ProjectEvidenceStrengthMapper._();

  static ProjectEvidenceStrengthMapper? _instance;
  static ProjectEvidenceStrengthMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectEvidenceStrengthMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectEvidenceStrength fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectEvidenceStrength decode(dynamic value) {
    switch (value) {
      case r'advisory':
        return ProjectEvidenceStrength.advisory;
      case r'supporting':
        return ProjectEvidenceStrength.supporting;
      case r'conclusive':
        return ProjectEvidenceStrength.conclusive;
      default:
        return ProjectEvidenceStrength.values[0];
    }
  }

  @override
  dynamic encode(ProjectEvidenceStrength self) {
    switch (self) {
      case ProjectEvidenceStrength.advisory:
        return r'advisory';
      case ProjectEvidenceStrength.supporting:
        return r'supporting';
      case ProjectEvidenceStrength.conclusive:
        return r'conclusive';
    }
  }
}

/// @nodoc

extension ProjectEvidenceStrengthMapperExtension on ProjectEvidenceStrength {
  String toValue() {
    ProjectEvidenceStrengthMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectEvidenceStrength>(this)
        as String;
  }
}

/// @nodoc

class ProjectMilestoneStatusMapper extends EnumMapper<ProjectMilestoneStatus> {
  ProjectMilestoneStatusMapper._();

  static ProjectMilestoneStatusMapper? _instance;
  static ProjectMilestoneStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMilestoneStatusMapper._());
    }
    return _instance!;
  }

  static ProjectMilestoneStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectMilestoneStatus decode(dynamic value) {
    switch (value) {
      case r'planned':
        return ProjectMilestoneStatus.planned;
      case r'active':
        return ProjectMilestoneStatus.active;
      case r'completed':
        return ProjectMilestoneStatus.completed;
      case r'blocked':
        return ProjectMilestoneStatus.blocked;
      case r'cancelled':
        return ProjectMilestoneStatus.cancelled;
      default:
        return ProjectMilestoneStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectMilestoneStatus self) {
    switch (self) {
      case ProjectMilestoneStatus.planned:
        return r'planned';
      case ProjectMilestoneStatus.active:
        return r'active';
      case ProjectMilestoneStatus.completed:
        return r'completed';
      case ProjectMilestoneStatus.blocked:
        return r'blocked';
      case ProjectMilestoneStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension ProjectMilestoneStatusMapperExtension on ProjectMilestoneStatus {
  String toValue() {
    ProjectMilestoneStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectMilestoneStatus>(this)
        as String;
  }
}

/// @nodoc

class ProjectTaskPriorityMapper extends EnumMapper<ProjectTaskPriority> {
  ProjectTaskPriorityMapper._();

  static ProjectTaskPriorityMapper? _instance;
  static ProjectTaskPriorityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskPriorityMapper._());
    }
    return _instance!;
  }

  static ProjectTaskPriority fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectTaskPriority decode(dynamic value) {
    switch (value) {
      case r'critical':
        return ProjectTaskPriority.critical;
      case r'high':
        return ProjectTaskPriority.high;
      case r'normal':
        return ProjectTaskPriority.normal;
      case r'low':
        return ProjectTaskPriority.low;
      default:
        return ProjectTaskPriority.values[2];
    }
  }

  @override
  dynamic encode(ProjectTaskPriority self) {
    switch (self) {
      case ProjectTaskPriority.critical:
        return r'critical';
      case ProjectTaskPriority.high:
        return r'high';
      case ProjectTaskPriority.normal:
        return r'normal';
      case ProjectTaskPriority.low:
        return r'low';
    }
  }
}

/// @nodoc

extension ProjectTaskPriorityMapperExtension on ProjectTaskPriority {
  String toValue() {
    ProjectTaskPriorityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectTaskPriority>(this) as String;
  }
}

/// @nodoc

class ProjectTaskRiskMapper extends EnumMapper<ProjectTaskRisk> {
  ProjectTaskRiskMapper._();

  static ProjectTaskRiskMapper? _instance;
  static ProjectTaskRiskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskRiskMapper._());
    }
    return _instance!;
  }

  static ProjectTaskRisk fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectTaskRisk decode(dynamic value) {
    switch (value) {
      case r'high':
        return ProjectTaskRisk.high;
      case r'medium':
        return ProjectTaskRisk.medium;
      case r'low':
        return ProjectTaskRisk.low;
      case r'unknown':
        return ProjectTaskRisk.unknown;
      default:
        return ProjectTaskRisk.values[3];
    }
  }

  @override
  dynamic encode(ProjectTaskRisk self) {
    switch (self) {
      case ProjectTaskRisk.high:
        return r'high';
      case ProjectTaskRisk.medium:
        return r'medium';
      case ProjectTaskRisk.low:
        return r'low';
      case ProjectTaskRisk.unknown:
        return r'unknown';
    }
  }
}

/// @nodoc

extension ProjectTaskRiskMapperExtension on ProjectTaskRisk {
  String toValue() {
    ProjectTaskRiskMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectTaskRisk>(this) as String;
  }
}

/// @nodoc

class ProjectRiskReductionMapper extends EnumMapper<ProjectRiskReduction> {
  ProjectRiskReductionMapper._();

  static ProjectRiskReductionMapper? _instance;
  static ProjectRiskReductionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectRiskReductionMapper._());
    }
    return _instance!;
  }

  static ProjectRiskReduction fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectRiskReduction decode(dynamic value) {
    switch (value) {
      case r'high':
        return ProjectRiskReduction.high;
      case r'medium':
        return ProjectRiskReduction.medium;
      case r'low':
        return ProjectRiskReduction.low;
      case r'none':
        return ProjectRiskReduction.none;
      default:
        return ProjectRiskReduction.values[3];
    }
  }

  @override
  dynamic encode(ProjectRiskReduction self) {
    switch (self) {
      case ProjectRiskReduction.high:
        return r'high';
      case ProjectRiskReduction.medium:
        return r'medium';
      case ProjectRiskReduction.low:
        return r'low';
      case ProjectRiskReduction.none:
        return r'none';
    }
  }
}

/// @nodoc

extension ProjectRiskReductionMapperExtension on ProjectRiskReduction {
  String toValue() {
    ProjectRiskReductionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectRiskReduction>(this)
        as String;
  }
}

/// @nodoc

class ProjectTaskEffortMapper extends EnumMapper<ProjectTaskEffort> {
  ProjectTaskEffortMapper._();

  static ProjectTaskEffortMapper? _instance;
  static ProjectTaskEffortMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskEffortMapper._());
    }
    return _instance!;
  }

  static ProjectTaskEffort fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectTaskEffort decode(dynamic value) {
    switch (value) {
      case r'small':
        return ProjectTaskEffort.small;
      case r'medium':
        return ProjectTaskEffort.medium;
      case r'large':
        return ProjectTaskEffort.large;
      default:
        return ProjectTaskEffort.values[0];
    }
  }

  @override
  dynamic encode(ProjectTaskEffort self) {
    switch (self) {
      case ProjectTaskEffort.small:
        return r'small';
      case ProjectTaskEffort.medium:
        return r'medium';
      case ProjectTaskEffort.large:
        return r'large';
    }
  }
}

/// @nodoc

extension ProjectTaskEffortMapperExtension on ProjectTaskEffort {
  String toValue() {
    ProjectTaskEffortMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectTaskEffort>(this) as String;
  }
}

/// @nodoc

class ProjectTaskReadinessMapper extends EnumMapper<ProjectTaskReadiness> {
  ProjectTaskReadinessMapper._();

  static ProjectTaskReadinessMapper? _instance;
  static ProjectTaskReadinessMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskReadinessMapper._());
    }
    return _instance!;
  }

  static ProjectTaskReadiness fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectTaskReadiness decode(dynamic value) {
    switch (value) {
      case r'ready':
        return ProjectTaskReadiness.ready;
      case 'waiting_dependency':
        return ProjectTaskReadiness.waitingDependency;
      case 'waiting_input':
        return ProjectTaskReadiness.waitingInput;
      case 'not_eligible':
        return ProjectTaskReadiness.notEligible;
      default:
        return ProjectTaskReadiness.values[0];
    }
  }

  @override
  dynamic encode(ProjectTaskReadiness self) {
    switch (self) {
      case ProjectTaskReadiness.ready:
        return r'ready';
      case ProjectTaskReadiness.waitingDependency:
        return 'waiting_dependency';
      case ProjectTaskReadiness.waitingInput:
        return 'waiting_input';
      case ProjectTaskReadiness.notEligible:
        return 'not_eligible';
    }
  }
}

/// @nodoc

extension ProjectTaskReadinessMapperExtension on ProjectTaskReadiness {
  dynamic toValue() {
    ProjectTaskReadinessMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectTaskReadiness>(this);
  }
}

/// @nodoc

class ProjectMemoryKindMapper extends EnumMapper<ProjectMemoryKind> {
  ProjectMemoryKindMapper._();

  static ProjectMemoryKindMapper? _instance;
  static ProjectMemoryKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMemoryKindMapper._());
    }
    return _instance!;
  }

  static ProjectMemoryKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectMemoryKind decode(dynamic value) {
    switch (value) {
      case r'requirement':
        return ProjectMemoryKind.requirement;
      case r'fact':
        return ProjectMemoryKind.fact;
      case r'assumption':
        return ProjectMemoryKind.assumption;
      case r'decision':
        return ProjectMemoryKind.decision;
      case r'risk':
        return ProjectMemoryKind.risk;
      case r'summary':
        return ProjectMemoryKind.summary;
      default:
        return ProjectMemoryKind.values[1];
    }
  }

  @override
  dynamic encode(ProjectMemoryKind self) {
    switch (self) {
      case ProjectMemoryKind.requirement:
        return r'requirement';
      case ProjectMemoryKind.fact:
        return r'fact';
      case ProjectMemoryKind.assumption:
        return r'assumption';
      case ProjectMemoryKind.decision:
        return r'decision';
      case ProjectMemoryKind.risk:
        return r'risk';
      case ProjectMemoryKind.summary:
        return r'summary';
    }
  }
}

/// @nodoc

extension ProjectMemoryKindMapperExtension on ProjectMemoryKind {
  String toValue() {
    ProjectMemoryKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectMemoryKind>(this) as String;
  }
}

/// @nodoc

class ProjectMemorySourceTypeMapper
    extends EnumMapper<ProjectMemorySourceType> {
  ProjectMemorySourceTypeMapper._();

  static ProjectMemorySourceTypeMapper? _instance;
  static ProjectMemorySourceTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectMemorySourceTypeMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectMemorySourceType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectMemorySourceType decode(dynamic value) {
    switch (value) {
      case r'user':
        return ProjectMemorySourceType.user;
      case r'planner':
        return ProjectMemorySourceType.planner;
      case r'task':
        return ProjectMemorySourceType.task;
      case r'gate':
        return ProjectMemorySourceType.gate;
      case r'migration':
        return ProjectMemorySourceType.migration;
      case r'system':
        return ProjectMemorySourceType.system;
      default:
        return ProjectMemorySourceType.values[5];
    }
  }

  @override
  dynamic encode(ProjectMemorySourceType self) {
    switch (self) {
      case ProjectMemorySourceType.user:
        return r'user';
      case ProjectMemorySourceType.planner:
        return r'planner';
      case ProjectMemorySourceType.task:
        return r'task';
      case ProjectMemorySourceType.gate:
        return r'gate';
      case ProjectMemorySourceType.migration:
        return r'migration';
      case ProjectMemorySourceType.system:
        return r'system';
    }
  }
}

/// @nodoc

extension ProjectMemorySourceTypeMapperExtension on ProjectMemorySourceType {
  String toValue() {
    ProjectMemorySourceTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectMemorySourceType>(this)
        as String;
  }
}

/// @nodoc

class ProjectMemoryConfidenceMapper
    extends EnumMapper<ProjectMemoryConfidence> {
  ProjectMemoryConfidenceMapper._();

  static ProjectMemoryConfidenceMapper? _instance;
  static ProjectMemoryConfidenceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectMemoryConfidenceMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectMemoryConfidence fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectMemoryConfidence decode(dynamic value) {
    switch (value) {
      case r'confirmed':
        return ProjectMemoryConfidence.confirmed;
      case r'inferred':
        return ProjectMemoryConfidence.inferred;
      case r'uncertain':
        return ProjectMemoryConfidence.uncertain;
      default:
        return ProjectMemoryConfidence.values[1];
    }
  }

  @override
  dynamic encode(ProjectMemoryConfidence self) {
    switch (self) {
      case ProjectMemoryConfidence.confirmed:
        return r'confirmed';
      case ProjectMemoryConfidence.inferred:
        return r'inferred';
      case ProjectMemoryConfidence.uncertain:
        return r'uncertain';
    }
  }
}

/// @nodoc

extension ProjectMemoryConfidenceMapperExtension on ProjectMemoryConfidence {
  String toValue() {
    ProjectMemoryConfidenceMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectMemoryConfidence>(this)
        as String;
  }
}

/// @nodoc

class ProjectPlanRevisionTriggerMapper
    extends EnumMapper<ProjectPlanRevisionTrigger> {
  ProjectPlanRevisionTriggerMapper._();

  static ProjectPlanRevisionTriggerMapper? _instance;
  static ProjectPlanRevisionTriggerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectPlanRevisionTriggerMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectPlanRevisionTrigger fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectPlanRevisionTrigger decode(dynamic value) {
    switch (value) {
      case r'initialization':
        return ProjectPlanRevisionTrigger.initialization;
      case r'migration':
        return ProjectPlanRevisionTrigger.migration;
      case 'task_completed':
        return ProjectPlanRevisionTrigger.taskCompleted;
      case 'task_failed':
        return ProjectPlanRevisionTrigger.taskFailed;
      case 'new_context':
        return ProjectPlanRevisionTrigger.newContext;
      case 'no_ready_task':
        return ProjectPlanRevisionTrigger.noReadyTask;
      case 'milestone_completed':
        return ProjectPlanRevisionTrigger.milestoneCompleted;
      case r'manual':
        return ProjectPlanRevisionTrigger.manual;
      case 'workspace_changed':
        return ProjectPlanRevisionTrigger.workspaceChanged;
      case 'evidence_rejected':
        return ProjectPlanRevisionTrigger.evidenceRejected;
      case 'task_replan_requested':
        return ProjectPlanRevisionTrigger.taskReplanRequested;
      default:
        return ProjectPlanRevisionTrigger.values[0];
    }
  }

  @override
  dynamic encode(ProjectPlanRevisionTrigger self) {
    switch (self) {
      case ProjectPlanRevisionTrigger.initialization:
        return r'initialization';
      case ProjectPlanRevisionTrigger.migration:
        return r'migration';
      case ProjectPlanRevisionTrigger.taskCompleted:
        return 'task_completed';
      case ProjectPlanRevisionTrigger.taskFailed:
        return 'task_failed';
      case ProjectPlanRevisionTrigger.newContext:
        return 'new_context';
      case ProjectPlanRevisionTrigger.noReadyTask:
        return 'no_ready_task';
      case ProjectPlanRevisionTrigger.milestoneCompleted:
        return 'milestone_completed';
      case ProjectPlanRevisionTrigger.manual:
        return r'manual';
      case ProjectPlanRevisionTrigger.workspaceChanged:
        return 'workspace_changed';
      case ProjectPlanRevisionTrigger.evidenceRejected:
        return 'evidence_rejected';
      case ProjectPlanRevisionTrigger.taskReplanRequested:
        return 'task_replan_requested';
    }
  }
}

/// @nodoc

extension ProjectPlanRevisionTriggerMapperExtension
    on ProjectPlanRevisionTrigger {
  dynamic toValue() {
    ProjectPlanRevisionTriggerMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectPlanRevisionTrigger>(this);
  }
}

/// @nodoc

class ProjectPlanApprovalPolicyMapper
    extends EnumMapper<ProjectPlanApprovalPolicy> {
  ProjectPlanApprovalPolicyMapper._();

  static ProjectPlanApprovalPolicyMapper? _instance;
  static ProjectPlanApprovalPolicyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectPlanApprovalPolicyMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectPlanApprovalPolicy fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectPlanApprovalPolicy decode(dynamic value) {
    switch (value) {
      case r'never':
        return ProjectPlanApprovalPolicy.never;
      case r'highRiskOnly':
        return ProjectPlanApprovalPolicy.highRiskOnly;
      case r'everyRevision':
        return ProjectPlanApprovalPolicy.everyRevision;
      default:
        return ProjectPlanApprovalPolicy.values[1];
    }
  }

  @override
  dynamic encode(ProjectPlanApprovalPolicy self) {
    switch (self) {
      case ProjectPlanApprovalPolicy.never:
        return r'never';
      case ProjectPlanApprovalPolicy.highRiskOnly:
        return r'highRiskOnly';
      case ProjectPlanApprovalPolicy.everyRevision:
        return r'everyRevision';
    }
  }
}

/// @nodoc

extension ProjectPlanApprovalPolicyMapperExtension
    on ProjectPlanApprovalPolicy {
  String toValue() {
    ProjectPlanApprovalPolicyMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectPlanApprovalPolicy>(this)
        as String;
  }
}

/// @nodoc

class ProjectPlanRevisionApproverMapper
    extends EnumMapper<ProjectPlanRevisionApprover> {
  ProjectPlanRevisionApproverMapper._();

  static ProjectPlanRevisionApproverMapper? _instance;
  static ProjectPlanRevisionApproverMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectPlanRevisionApproverMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectPlanRevisionApprover fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectPlanRevisionApprover decode(dynamic value) {
    switch (value) {
      case r'automatic':
        return ProjectPlanRevisionApprover.automatic;
      case r'user':
        return ProjectPlanRevisionApprover.user;
      default:
        return ProjectPlanRevisionApprover.values[0];
    }
  }

  @override
  dynamic encode(ProjectPlanRevisionApprover self) {
    switch (self) {
      case ProjectPlanRevisionApprover.automatic:
        return r'automatic';
      case ProjectPlanRevisionApprover.user:
        return r'user';
    }
  }
}

/// @nodoc

extension ProjectPlanRevisionApproverMapperExtension
    on ProjectPlanRevisionApprover {
  String toValue() {
    ProjectPlanRevisionApproverMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectPlanRevisionApprover>(this)
        as String;
  }
}

/// @nodoc

class ProjectBlockerTypeMapper extends EnumMapper<ProjectBlockerType> {
  ProjectBlockerTypeMapper._();

  static ProjectBlockerTypeMapper? _instance;
  static ProjectBlockerTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectBlockerTypeMapper._());
    }
    return _instance!;
  }

  static ProjectBlockerType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectBlockerType decode(dynamic value) {
    switch (value) {
      case r'question':
        return ProjectBlockerType.question;
      case 'task_approval':
        return ProjectBlockerType.taskApproval;
      case 'task_blocked':
        return ProjectBlockerType.taskBlocked;
      case 'task_failed':
        return ProjectBlockerType.taskFailed;
      case 'recovery_failed':
        return ProjectBlockerType.recoveryFailed;
      case r'budget':
        return ProjectBlockerType.budget;
      case r'validation':
        return ProjectBlockerType.validation;
      case 'duplicate_task':
        return ProjectBlockerType.duplicateTask;
      case 'oversized_task':
        return ProjectBlockerType.oversizedTask;
      case 'max_failures':
        return ProjectBlockerType.maxFailures;
      case 'plan_approval':
        return ProjectBlockerType.planApproval;
      case r'stagnation':
        return ProjectBlockerType.stagnation;
      case r'error':
        return ProjectBlockerType.error;
      default:
        return ProjectBlockerType.values[12];
    }
  }

  @override
  dynamic encode(ProjectBlockerType self) {
    switch (self) {
      case ProjectBlockerType.question:
        return r'question';
      case ProjectBlockerType.taskApproval:
        return 'task_approval';
      case ProjectBlockerType.taskBlocked:
        return 'task_blocked';
      case ProjectBlockerType.taskFailed:
        return 'task_failed';
      case ProjectBlockerType.recoveryFailed:
        return 'recovery_failed';
      case ProjectBlockerType.budget:
        return r'budget';
      case ProjectBlockerType.validation:
        return r'validation';
      case ProjectBlockerType.duplicateTask:
        return 'duplicate_task';
      case ProjectBlockerType.oversizedTask:
        return 'oversized_task';
      case ProjectBlockerType.maxFailures:
        return 'max_failures';
      case ProjectBlockerType.planApproval:
        return 'plan_approval';
      case ProjectBlockerType.stagnation:
        return r'stagnation';
      case ProjectBlockerType.error:
        return r'error';
    }
  }
}

/// @nodoc

extension ProjectBlockerTypeMapperExtension on ProjectBlockerType {
  dynamic toValue() {
    ProjectBlockerTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectBlockerType>(this);
  }
}

/// @nodoc

class ProjectDecisionTypeMapper extends EnumMapper<ProjectDecisionType> {
  ProjectDecisionTypeMapper._();

  static ProjectDecisionTypeMapper? _instance;
  static ProjectDecisionTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectDecisionTypeMapper._());
    }
    return _instance!;
  }

  static ProjectDecisionType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectDecisionType decode(dynamic value) {
    switch (value) {
      case 'create_task':
        return ProjectDecisionType.createTask;
      case 'create_recovery_task':
        return ProjectDecisionType.createRecoveryTask;
      case r'complete':
        return ProjectDecisionType.complete;
      case r'blocked':
        return ProjectDecisionType.blocked;
      case 'reject_task':
        return ProjectDecisionType.rejectTask;
      case 'split_task':
        return ProjectDecisionType.splitTask;
      case 'evaluate_task':
        return ProjectDecisionType.evaluateTask;
      case 'refresh_backlog':
        return ProjectDecisionType.refreshBacklog;
      case 'retry_recovery':
        return ProjectDecisionType.retryRecovery;
      case 'apply_plan_revision':
        return ProjectDecisionType.applyPlanRevision;
      case 'approve_plan_revision':
        return ProjectDecisionType.approvePlanRevision;
      case 'reject_plan_revision':
        return ProjectDecisionType.rejectPlanRevision;
      default:
        return ProjectDecisionType.values[3];
    }
  }

  @override
  dynamic encode(ProjectDecisionType self) {
    switch (self) {
      case ProjectDecisionType.createTask:
        return 'create_task';
      case ProjectDecisionType.createRecoveryTask:
        return 'create_recovery_task';
      case ProjectDecisionType.complete:
        return r'complete';
      case ProjectDecisionType.blocked:
        return r'blocked';
      case ProjectDecisionType.rejectTask:
        return 'reject_task';
      case ProjectDecisionType.splitTask:
        return 'split_task';
      case ProjectDecisionType.evaluateTask:
        return 'evaluate_task';
      case ProjectDecisionType.refreshBacklog:
        return 'refresh_backlog';
      case ProjectDecisionType.retryRecovery:
        return 'retry_recovery';
      case ProjectDecisionType.applyPlanRevision:
        return 'apply_plan_revision';
      case ProjectDecisionType.approvePlanRevision:
        return 'approve_plan_revision';
      case ProjectDecisionType.rejectPlanRevision:
        return 'reject_plan_revision';
    }
  }
}

/// @nodoc

extension ProjectDecisionTypeMapperExtension on ProjectDecisionType {
  dynamic toValue() {
    ProjectDecisionTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectDecisionType>(this);
  }
}

/// @nodoc

class ProjectRecoveryIncidentStatusMapper
    extends EnumMapper<ProjectRecoveryIncidentStatus> {
  ProjectRecoveryIncidentStatusMapper._();

  static ProjectRecoveryIncidentStatusMapper? _instance;
  static ProjectRecoveryIncidentStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectRecoveryIncidentStatusMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectRecoveryIncidentStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectRecoveryIncidentStatus decode(dynamic value) {
    switch (value) {
      case r'active':
        return ProjectRecoveryIncidentStatus.active;
      case r'resolved':
        return ProjectRecoveryIncidentStatus.resolved;
      case r'exhausted':
        return ProjectRecoveryIncidentStatus.exhausted;
      default:
        return ProjectRecoveryIncidentStatus.values[0];
    }
  }

  @override
  dynamic encode(ProjectRecoveryIncidentStatus self) {
    switch (self) {
      case ProjectRecoveryIncidentStatus.active:
        return r'active';
      case ProjectRecoveryIncidentStatus.resolved:
        return r'resolved';
      case ProjectRecoveryIncidentStatus.exhausted:
        return r'exhausted';
    }
  }
}

/// @nodoc

extension ProjectRecoveryIncidentStatusMapperExtension
    on ProjectRecoveryIncidentStatus {
  String toValue() {
    ProjectRecoveryIncidentStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectRecoveryIncidentStatus>(this)
        as String;
  }
}

/// @nodoc
class ProjectDiagnosticsMapper extends ClassMapperBase<ProjectDiagnostics> {
  ProjectDiagnosticsMapper._();

  static ProjectDiagnosticsMapper? _instance;
  static ProjectDiagnosticsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectDiagnosticsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectDiagnostics';

  static int _$projectModelCalls(ProjectDiagnostics v) => v.projectModelCalls;
  static const Field<ProjectDiagnostics, int> _f$projectModelCalls = Field(
    'projectModelCalls',
    _$projectModelCalls,
    opt: true,
    def: 0,
  );
  static int _$planRevisionAttempts(ProjectDiagnostics v) =>
      v.planRevisionAttempts;
  static const Field<ProjectDiagnostics, int> _f$planRevisionAttempts = Field(
    'planRevisionAttempts',
    _$planRevisionAttempts,
    opt: true,
    def: 0,
  );
  static int _$invalidPlanProposals(ProjectDiagnostics v) =>
      v.invalidPlanProposals;
  static const Field<ProjectDiagnostics, int> _f$invalidPlanProposals = Field(
    'invalidPlanProposals',
    _$invalidPlanProposals,
    opt: true,
    def: 0,
  );
  static int _$taskExecutions(ProjectDiagnostics v) => v.taskExecutions;
  static const Field<ProjectDiagnostics, int> _f$taskExecutions = Field(
    'taskExecutions',
    _$taskExecutions,
    opt: true,
    def: 0,
  );
  static int _$completedTaskExecutions(ProjectDiagnostics v) =>
      v.completedTaskExecutions;
  static const Field<ProjectDiagnostics, int> _f$completedTaskExecutions =
      Field(
        'completedTaskExecutions',
        _$completedTaskExecutions,
        opt: true,
        def: 0,
      );
  static int _$completedTasksWithoutCriterionProgress(ProjectDiagnostics v) =>
      v.completedTasksWithoutCriterionProgress;
  static const Field<ProjectDiagnostics, int>
  _f$completedTasksWithoutCriterionProgress = Field(
    'completedTasksWithoutCriterionProgress',
    _$completedTasksWithoutCriterionProgress,
    opt: true,
    def: 0,
  );
  static int _$criterionReversals(ProjectDiagnostics v) => v.criterionReversals;
  static const Field<ProjectDiagnostics, int> _f$criterionReversals = Field(
    'criterionReversals',
    _$criterionReversals,
    opt: true,
    def: 0,
  );
  static int _$noReadyTaskBlocks(ProjectDiagnostics v) => v.noReadyTaskBlocks;
  static const Field<ProjectDiagnostics, int> _f$noReadyTaskBlocks = Field(
    'noReadyTaskBlocks',
    _$noReadyTaskBlocks,
    opt: true,
    def: 0,
  );
  static int _$userApprovals(ProjectDiagnostics v) => v.userApprovals;
  static const Field<ProjectDiagnostics, int> _f$userApprovals = Field(
    'userApprovals',
    _$userApprovals,
    opt: true,
    def: 0,
  );
  static int _$userQuestions(ProjectDiagnostics v) => v.userQuestions;
  static const Field<ProjectDiagnostics, int> _f$userQuestions = Field(
    'userQuestions',
    _$userQuestions,
    opt: true,
    def: 0,
  );
  static int _$consecutiveNoProgressIterations(ProjectDiagnostics v) =>
      v.consecutiveNoProgressIterations;
  static const Field<ProjectDiagnostics, int>
  _f$consecutiveNoProgressIterations = Field(
    'consecutiveNoProgressIterations',
    _$consecutiveNoProgressIterations,
    opt: true,
    def: 0,
  );
  static List<String> _$recentNoProgressTaskIds(ProjectDiagnostics v) =>
      v.recentNoProgressTaskIds;
  static const Field<ProjectDiagnostics, List<String>>
  _f$recentNoProgressTaskIds = Field(
    'recentNoProgressTaskIds',
    _$recentNoProgressTaskIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );

  @override
  final MappableFields<ProjectDiagnostics> fields = const {
    #projectModelCalls: _f$projectModelCalls,
    #planRevisionAttempts: _f$planRevisionAttempts,
    #invalidPlanProposals: _f$invalidPlanProposals,
    #taskExecutions: _f$taskExecutions,
    #completedTaskExecutions: _f$completedTaskExecutions,
    #completedTasksWithoutCriterionProgress:
        _f$completedTasksWithoutCriterionProgress,
    #criterionReversals: _f$criterionReversals,
    #noReadyTaskBlocks: _f$noReadyTaskBlocks,
    #userApprovals: _f$userApprovals,
    #userQuestions: _f$userQuestions,
    #consecutiveNoProgressIterations: _f$consecutiveNoProgressIterations,
    #recentNoProgressTaskIds: _f$recentNoProgressTaskIds,
  };
  @override
  final bool ignoreNull = true;

  static ProjectDiagnostics _instantiate(DecodingData data) {
    return ProjectDiagnostics(
      projectModelCalls: data.dec(_f$projectModelCalls),
      planRevisionAttempts: data.dec(_f$planRevisionAttempts),
      invalidPlanProposals: data.dec(_f$invalidPlanProposals),
      taskExecutions: data.dec(_f$taskExecutions),
      completedTaskExecutions: data.dec(_f$completedTaskExecutions),
      completedTasksWithoutCriterionProgress: data.dec(
        _f$completedTasksWithoutCriterionProgress,
      ),
      criterionReversals: data.dec(_f$criterionReversals),
      noReadyTaskBlocks: data.dec(_f$noReadyTaskBlocks),
      userApprovals: data.dec(_f$userApprovals),
      userQuestions: data.dec(_f$userQuestions),
      consecutiveNoProgressIterations: data.dec(
        _f$consecutiveNoProgressIterations,
      ),
      recentNoProgressTaskIds: data.dec(_f$recentNoProgressTaskIds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectDiagnostics fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectDiagnostics>(map);
  }

  static ProjectDiagnostics fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectDiagnostics>(json);
  }
}

/// @nodoc
mixin ProjectDiagnosticsMappable {
  String toJson() {
    return ProjectDiagnosticsMapper.ensureInitialized()
        .encodeJson<ProjectDiagnostics>(this as ProjectDiagnostics);
  }

  Map<String, dynamic> toMap() {
    return ProjectDiagnosticsMapper.ensureInitialized()
        .encodeMap<ProjectDiagnostics>(this as ProjectDiagnostics);
  }
}

/// @nodoc
class ProjectCriterionMapper extends ClassMapperBase<ProjectCriterion> {
  ProjectCriterionMapper._();

  static ProjectCriterionMapper? _instance;
  static ProjectCriterionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectCriterionMapper._());
      ProjectCriterionStatusMapper.ensureInitialized();
      ProjectVerificationModeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectCriterion';

  static String _$id(ProjectCriterion v) => v.id;
  static const Field<ProjectCriterion, String> _f$id = Field('id', _$id);
  static String _$statement(ProjectCriterion v) => v.statement;
  static const Field<ProjectCriterion, String> _f$statement = Field(
    'statement',
    _$statement,
  );
  static bool _$required(ProjectCriterion v) => v.required;
  static const Field<ProjectCriterion, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
  );
  static ProjectCriterionStatus _$status(ProjectCriterion v) => v.status;
  static const Field<ProjectCriterion, ProjectCriterionStatus> _f$status =
      Field(
        'status',
        _$status,
        opt: true,
        def: ProjectCriterionStatus.unsatisfied,
      );
  static ProjectVerificationMode _$verificationMode(ProjectCriterion v) =>
      v.verificationMode;
  static const Field<ProjectCriterion, ProjectVerificationMode>
  _f$verificationMode = Field(
    'verificationMode',
    _$verificationMode,
    opt: true,
    def: ProjectVerificationMode.mixed,
  );
  static List<String> _$evidenceIds(ProjectCriterion v) => v.evidenceIds;
  static const Field<ProjectCriterion, List<String>> _f$evidenceIds = Field(
    'evidenceIds',
    _$evidenceIds,
    opt: true,
    def: const [],
  );
  static String _$notes(ProjectCriterion v) => v.notes;
  static const Field<ProjectCriterion, String> _f$notes = Field(
    'notes',
    _$notes,
    opt: true,
    def: '',
  );
  static DateTime _$createdAt(ProjectCriterion v) => v.createdAt;
  static const Field<ProjectCriterion, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(ProjectCriterion v) => v.updatedAt;
  static const Field<ProjectCriterion, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static DateTime? _$verifiedAt(ProjectCriterion v) => v.verifiedAt;
  static const Field<ProjectCriterion, DateTime> _f$verifiedAt = Field(
    'verifiedAt',
    _$verifiedAt,
    opt: true,
  );

  @override
  final MappableFields<ProjectCriterion> fields = const {
    #id: _f$id,
    #statement: _f$statement,
    #required: _f$required,
    #status: _f$status,
    #verificationMode: _f$verificationMode,
    #evidenceIds: _f$evidenceIds,
    #notes: _f$notes,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #verifiedAt: _f$verifiedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectCriterion _instantiate(DecodingData data) {
    return ProjectCriterion(
      id: data.dec(_f$id),
      statement: data.dec(_f$statement),
      required: data.dec(_f$required),
      status: data.dec(_f$status),
      verificationMode: data.dec(_f$verificationMode),
      evidenceIds: data.dec(_f$evidenceIds),
      notes: data.dec(_f$notes),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      verifiedAt: data.dec(_f$verifiedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectCriterion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectCriterion>(map);
  }

  static ProjectCriterion fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectCriterion>(json);
  }
}

/// @nodoc
mixin ProjectCriterionMappable {
  String toJson() {
    return ProjectCriterionMapper.ensureInitialized()
        .encodeJson<ProjectCriterion>(this as ProjectCriterion);
  }

  Map<String, dynamic> toMap() {
    return ProjectCriterionMapper.ensureInitialized()
        .encodeMap<ProjectCriterion>(this as ProjectCriterion);
  }
}

/// @nodoc
class ProjectEvidenceMapper extends ClassMapperBase<ProjectEvidence> {
  ProjectEvidenceMapper._();

  static ProjectEvidenceMapper? _instance;
  static ProjectEvidenceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectEvidenceMapper._());
      ProjectEvidenceTypeMapper.ensureInitialized();
      ProjectEvidenceStatusMapper.ensureInitialized();
      ProjectEvidenceStrengthMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectEvidence';

  static String _$id(ProjectEvidence v) => v.id;
  static const Field<ProjectEvidence, String> _f$id = Field('id', _$id);
  static ProjectEvidenceType _$type(ProjectEvidence v) => v.type;
  static const Field<ProjectEvidence, ProjectEvidenceType> _f$type = Field(
    'type',
    _$type,
  );
  static List<String> _$criterionIds(ProjectEvidence v) => v.criterionIds;
  static const Field<ProjectEvidence, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
  );
  static String? _$projectTaskId(ProjectEvidence v) => v.projectTaskId;
  static const Field<ProjectEvidence, String> _f$projectTaskId = Field(
    'projectTaskId',
    _$projectTaskId,
    opt: true,
  );
  static String? _$taskDocumentId(ProjectEvidence v) => v.taskDocumentId;
  static const Field<ProjectEvidence, String> _f$taskDocumentId = Field(
    'taskDocumentId',
    _$taskDocumentId,
    opt: true,
  );
  static String? _$taskRunId(ProjectEvidence v) => v.taskRunId;
  static const Field<ProjectEvidence, String> _f$taskRunId = Field(
    'taskRunId',
    _$taskRunId,
    opt: true,
  );
  static String _$sourceRef(ProjectEvidence v) => v.sourceRef;
  static const Field<ProjectEvidence, String> _f$sourceRef = Field(
    'sourceRef',
    _$sourceRef,
  );
  static String? _$sourceFingerprint(ProjectEvidence v) => v.sourceFingerprint;
  static const Field<ProjectEvidence, String> _f$sourceFingerprint = Field(
    'sourceFingerprint',
    _$sourceFingerprint,
    opt: true,
  );
  static String _$summary(ProjectEvidence v) => v.summary;
  static const Field<ProjectEvidence, String> _f$summary = Field(
    'summary',
    _$summary,
  );
  static ProjectEvidenceStatus _$status(ProjectEvidence v) => v.status;
  static const Field<ProjectEvidence, ProjectEvidenceStatus> _f$status = Field(
    'status',
    _$status,
    opt: true,
    def: ProjectEvidenceStatus.proposed,
  );
  static ProjectEvidenceStrength _$strength(ProjectEvidence v) => v.strength;
  static const Field<ProjectEvidence, ProjectEvidenceStrength> _f$strength =
      Field(
        'strength',
        _$strength,
        opt: true,
        def: ProjectEvidenceStrength.advisory,
      );
  static Map<String, dynamic> _$details(ProjectEvidence v) => v.details;
  static const Field<ProjectEvidence, Map<String, dynamic>> _f$details = Field(
    'details',
    _$details,
    opt: true,
    def: const {},
  );
  static DateTime _$createdAt(ProjectEvidence v) => v.createdAt;
  static const Field<ProjectEvidence, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime? _$evaluatedAt(ProjectEvidence v) => v.evaluatedAt;
  static const Field<ProjectEvidence, DateTime> _f$evaluatedAt = Field(
    'evaluatedAt',
    _$evaluatedAt,
    opt: true,
  );

  @override
  final MappableFields<ProjectEvidence> fields = const {
    #id: _f$id,
    #type: _f$type,
    #criterionIds: _f$criterionIds,
    #projectTaskId: _f$projectTaskId,
    #taskDocumentId: _f$taskDocumentId,
    #taskRunId: _f$taskRunId,
    #sourceRef: _f$sourceRef,
    #sourceFingerprint: _f$sourceFingerprint,
    #summary: _f$summary,
    #status: _f$status,
    #strength: _f$strength,
    #details: _f$details,
    #createdAt: _f$createdAt,
    #evaluatedAt: _f$evaluatedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectEvidence _instantiate(DecodingData data) {
    return ProjectEvidence(
      id: data.dec(_f$id),
      type: data.dec(_f$type),
      criterionIds: data.dec(_f$criterionIds),
      projectTaskId: data.dec(_f$projectTaskId),
      taskDocumentId: data.dec(_f$taskDocumentId),
      taskRunId: data.dec(_f$taskRunId),
      sourceRef: data.dec(_f$sourceRef),
      sourceFingerprint: data.dec(_f$sourceFingerprint),
      summary: data.dec(_f$summary),
      status: data.dec(_f$status),
      strength: data.dec(_f$strength),
      details: data.dec(_f$details),
      createdAt: data.dec(_f$createdAt),
      evaluatedAt: data.dec(_f$evaluatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectEvidence fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectEvidence>(map);
  }

  static ProjectEvidence fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectEvidence>(json);
  }
}

/// @nodoc
mixin ProjectEvidenceMappable {
  String toJson() {
    return ProjectEvidenceMapper.ensureInitialized()
        .encodeJson<ProjectEvidence>(this as ProjectEvidence);
  }

  Map<String, dynamic> toMap() {
    return ProjectEvidenceMapper.ensureInitialized().encodeMap<ProjectEvidence>(
      this as ProjectEvidence,
    );
  }
}

/// @nodoc
class ProjectMilestoneMapper extends ClassMapperBase<ProjectMilestone> {
  ProjectMilestoneMapper._();

  static ProjectMilestoneMapper? _instance;
  static ProjectMilestoneMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMilestoneMapper._());
      ProjectMilestoneStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectMilestone';

  static String _$id(ProjectMilestone v) => v.id;
  static const Field<ProjectMilestone, String> _f$id = Field('id', _$id);
  static String _$title(ProjectMilestone v) => v.title;
  static const Field<ProjectMilestone, String> _f$title = Field(
    'title',
    _$title,
  );
  static String _$objective(ProjectMilestone v) => v.objective;
  static const Field<ProjectMilestone, String> _f$objective = Field(
    'objective',
    _$objective,
  );
  static List<String> _$criterionIds(ProjectMilestone v) => v.criterionIds;
  static const Field<ProjectMilestone, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    def: const [],
  );
  static ProjectMilestoneStatus _$status(ProjectMilestone v) => v.status;
  static const Field<ProjectMilestone, ProjectMilestoneStatus> _f$status =
      Field('status', _$status, opt: true, def: ProjectMilestoneStatus.planned);
  static List<String> _$exitConditions(ProjectMilestone v) => v.exitConditions;
  static const Field<ProjectMilestone, List<String>> _f$exitConditions = Field(
    'exitConditions',
    _$exitConditions,
    opt: true,
    def: const [],
  );
  static List<String> _$taskIds(ProjectMilestone v) => v.taskIds;
  static const Field<ProjectMilestone, List<String>> _f$taskIds = Field(
    'taskIds',
    _$taskIds,
    opt: true,
    def: const [],
  );
  static int _$order(ProjectMilestone v) => v.order;
  static const Field<ProjectMilestone, int> _f$order = Field('order', _$order);
  static DateTime _$createdAt(ProjectMilestone v) => v.createdAt;
  static const Field<ProjectMilestone, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(ProjectMilestone v) => v.updatedAt;
  static const Field<ProjectMilestone, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static DateTime? _$completedAt(ProjectMilestone v) => v.completedAt;
  static const Field<ProjectMilestone, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
  );

  @override
  final MappableFields<ProjectMilestone> fields = const {
    #id: _f$id,
    #title: _f$title,
    #objective: _f$objective,
    #criterionIds: _f$criterionIds,
    #status: _f$status,
    #exitConditions: _f$exitConditions,
    #taskIds: _f$taskIds,
    #order: _f$order,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectMilestone _instantiate(DecodingData data) {
    return ProjectMilestone(
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      objective: data.dec(_f$objective),
      criterionIds: data.dec(_f$criterionIds),
      status: data.dec(_f$status),
      exitConditions: data.dec(_f$exitConditions),
      taskIds: data.dec(_f$taskIds),
      order: data.dec(_f$order),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectMilestone fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectMilestone>(map);
  }

  static ProjectMilestone fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectMilestone>(json);
  }
}

/// @nodoc
mixin ProjectMilestoneMappable {
  String toJson() {
    return ProjectMilestoneMapper.ensureInitialized()
        .encodeJson<ProjectMilestone>(this as ProjectMilestone);
  }

  Map<String, dynamic> toMap() {
    return ProjectMilestoneMapper.ensureInitialized()
        .encodeMap<ProjectMilestone>(this as ProjectMilestone);
  }
}

/// @nodoc
class ProjectEvidenceExpectationMapper
    extends ClassMapperBase<ProjectEvidenceExpectation> {
  ProjectEvidenceExpectationMapper._();

  static ProjectEvidenceExpectationMapper? _instance;
  static ProjectEvidenceExpectationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectEvidenceExpectationMapper._(),
      );
      ProjectEvidenceTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectEvidenceExpectation';

  static String _$id(ProjectEvidenceExpectation v) => v.id;
  static const Field<ProjectEvidenceExpectation, String> _f$id = Field(
    'id',
    _$id,
  );
  static ProjectEvidenceType _$type(ProjectEvidenceExpectation v) => v.type;
  static const Field<ProjectEvidenceExpectation, ProjectEvidenceType> _f$type =
      Field('type', _$type);
  static List<String> _$criterionIds(ProjectEvidenceExpectation v) =>
      v.criterionIds;
  static const Field<ProjectEvidenceExpectation, List<String>> _f$criterionIds =
      Field('criterionIds', _$criterionIds, opt: true, def: const []);
  static String _$description(ProjectEvidenceExpectation v) => v.description;
  static const Field<ProjectEvidenceExpectation, String> _f$description = Field(
    'description',
    _$description,
  );
  static bool _$required(ProjectEvidenceExpectation v) => v.required;
  static const Field<ProjectEvidenceExpectation, bool> _f$required = Field(
    'required',
    _$required,
    opt: true,
    def: true,
  );
  static String? _$sourceRef(ProjectEvidenceExpectation v) => v.sourceRef;
  static const Field<ProjectEvidenceExpectation, String> _f$sourceRef = Field(
    'sourceRef',
    _$sourceRef,
    opt: true,
  );
  static Map<String, dynamic> _$details(ProjectEvidenceExpectation v) =>
      v.details;
  static const Field<ProjectEvidenceExpectation, Map<String, dynamic>>
  _f$details = Field('details', _$details, opt: true, def: const {});

  @override
  final MappableFields<ProjectEvidenceExpectation> fields = const {
    #id: _f$id,
    #type: _f$type,
    #criterionIds: _f$criterionIds,
    #description: _f$description,
    #required: _f$required,
    #sourceRef: _f$sourceRef,
    #details: _f$details,
  };
  @override
  final bool ignoreNull = true;

  static ProjectEvidenceExpectation _instantiate(DecodingData data) {
    return ProjectEvidenceExpectation(
      id: data.dec(_f$id),
      type: data.dec(_f$type),
      criterionIds: data.dec(_f$criterionIds),
      description: data.dec(_f$description),
      required: data.dec(_f$required),
      sourceRef: data.dec(_f$sourceRef),
      details: data.dec(_f$details),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectEvidenceExpectation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectEvidenceExpectation>(map);
  }

  static ProjectEvidenceExpectation fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectEvidenceExpectation>(json);
  }
}

/// @nodoc
mixin ProjectEvidenceExpectationMappable {
  String toJson() {
    return ProjectEvidenceExpectationMapper.ensureInitialized()
        .encodeJson<ProjectEvidenceExpectation>(
          this as ProjectEvidenceExpectation,
        );
  }

  Map<String, dynamic> toMap() {
    return ProjectEvidenceExpectationMapper.ensureInitialized()
        .encodeMap<ProjectEvidenceExpectation>(
          this as ProjectEvidenceExpectation,
        );
  }
}

/// @nodoc
class ProjectMemoryEntryMapper extends ClassMapperBase<ProjectMemoryEntry> {
  ProjectMemoryEntryMapper._();

  static ProjectMemoryEntryMapper? _instance;
  static ProjectMemoryEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMemoryEntryMapper._());
      ProjectMemoryKindMapper.ensureInitialized();
      ProjectMemorySourceTypeMapper.ensureInitialized();
      ProjectMemoryConfidenceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectMemoryEntry';

  static String _$id(ProjectMemoryEntry v) => v.id;
  static const Field<ProjectMemoryEntry, String> _f$id = Field('id', _$id);
  static ProjectMemoryKind _$kind(ProjectMemoryEntry v) => v.kind;
  static const Field<ProjectMemoryEntry, ProjectMemoryKind> _f$kind = Field(
    'kind',
    _$kind,
  );
  static String _$content(ProjectMemoryEntry v) => v.content;
  static const Field<ProjectMemoryEntry, String> _f$content = Field(
    'content',
    _$content,
  );
  static ProjectMemorySourceType _$sourceType(ProjectMemoryEntry v) =>
      v.sourceType;
  static const Field<ProjectMemoryEntry, ProjectMemorySourceType>
  _f$sourceType = Field('sourceType', _$sourceType);
  static String? _$sourceId(ProjectMemoryEntry v) => v.sourceId;
  static const Field<ProjectMemoryEntry, String> _f$sourceId = Field(
    'sourceId',
    _$sourceId,
    opt: true,
  );
  static ProjectMemoryConfidence _$confidence(ProjectMemoryEntry v) =>
      v.confidence;
  static const Field<ProjectMemoryEntry, ProjectMemoryConfidence>
  _f$confidence = Field('confidence', _$confidence);
  static bool _$protected(ProjectMemoryEntry v) => v.protected;
  static const Field<ProjectMemoryEntry, bool> _f$protected = Field(
    'protected',
    _$protected,
    opt: true,
    def: false,
  );
  static bool _$active(ProjectMemoryEntry v) => v.active;
  static const Field<ProjectMemoryEntry, bool> _f$active = Field(
    'active',
    _$active,
    opt: true,
    def: true,
  );
  static String? _$supersedesId(ProjectMemoryEntry v) => v.supersedesId;
  static const Field<ProjectMemoryEntry, String> _f$supersedesId = Field(
    'supersedesId',
    _$supersedesId,
    opt: true,
  );
  static List<String> _$coveredEntryIds(ProjectMemoryEntry v) =>
      v.coveredEntryIds;
  static const Field<ProjectMemoryEntry, List<String>> _f$coveredEntryIds =
      Field(
        'coveredEntryIds',
        _$coveredEntryIds,
        opt: true,
        def: const [],
        hook: JsonStringListHook(),
      );
  static DateTime _$createdAt(ProjectMemoryEntry v) => v.createdAt;
  static const Field<ProjectMemoryEntry, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(ProjectMemoryEntry v) => v.updatedAt;
  static const Field<ProjectMemoryEntry, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<ProjectMemoryEntry> fields = const {
    #id: _f$id,
    #kind: _f$kind,
    #content: _f$content,
    #sourceType: _f$sourceType,
    #sourceId: _f$sourceId,
    #confidence: _f$confidence,
    #protected: _f$protected,
    #active: _f$active,
    #supersedesId: _f$supersedesId,
    #coveredEntryIds: _f$coveredEntryIds,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectMemoryEntry _instantiate(DecodingData data) {
    return ProjectMemoryEntry(
      id: data.dec(_f$id),
      kind: data.dec(_f$kind),
      content: data.dec(_f$content),
      sourceType: data.dec(_f$sourceType),
      sourceId: data.dec(_f$sourceId),
      confidence: data.dec(_f$confidence),
      protected: data.dec(_f$protected),
      active: data.dec(_f$active),
      supersedesId: data.dec(_f$supersedesId),
      coveredEntryIds: data.dec(_f$coveredEntryIds),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectMemoryEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectMemoryEntry>(map);
  }

  static ProjectMemoryEntry fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectMemoryEntry>(json);
  }
}

/// @nodoc
mixin ProjectMemoryEntryMappable {
  String toJson() {
    return ProjectMemoryEntryMapper.ensureInitialized()
        .encodeJson<ProjectMemoryEntry>(this as ProjectMemoryEntry);
  }

  Map<String, dynamic> toMap() {
    return ProjectMemoryEntryMapper.ensureInitialized()
        .encodeMap<ProjectMemoryEntry>(this as ProjectMemoryEntry);
  }
}

/// @nodoc
class ProjectMemorySupersessionMapper
    extends ClassMapperBase<ProjectMemorySupersession> {
  ProjectMemorySupersessionMapper._();

  static ProjectMemorySupersessionMapper? _instance;
  static ProjectMemorySupersessionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectMemorySupersessionMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectMemorySupersession';

  static String _$entryId(ProjectMemorySupersession v) => v.entryId;
  static const Field<ProjectMemorySupersession, String> _f$entryId = Field(
    'entryId',
    _$entryId,
  );
  static String _$supersededById(ProjectMemorySupersession v) =>
      v.supersededById;
  static const Field<ProjectMemorySupersession, String> _f$supersededById =
      Field('supersededById', _$supersededById);

  @override
  final MappableFields<ProjectMemorySupersession> fields = const {
    #entryId: _f$entryId,
    #supersededById: _f$supersededById,
  };
  @override
  final bool ignoreNull = true;

  static ProjectMemorySupersession _instantiate(DecodingData data) {
    return ProjectMemorySupersession(
      entryId: data.dec(_f$entryId),
      supersededById: data.dec(_f$supersededById),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectMemorySupersession fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectMemorySupersession>(map);
  }

  static ProjectMemorySupersession fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectMemorySupersession>(json);
  }
}

/// @nodoc
mixin ProjectMemorySupersessionMappable {
  String toJson() {
    return ProjectMemorySupersessionMapper.ensureInitialized()
        .encodeJson<ProjectMemorySupersession>(
          this as ProjectMemorySupersession,
        );
  }

  Map<String, dynamic> toMap() {
    return ProjectMemorySupersessionMapper.ensureInitialized()
        .encodeMap<ProjectMemorySupersession>(
          this as ProjectMemorySupersession,
        );
  }
}

/// @nodoc
class ProjectPlanProposalMapper extends ClassMapperBase<ProjectPlanProposal> {
  ProjectPlanProposalMapper._();

  static ProjectPlanProposalMapper? _instance;
  static ProjectPlanProposalMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectPlanProposalMapper._());
      ProjectPlanRevisionTriggerMapper.ensureInitialized();
      ProjectCriterionMapper.ensureInitialized();
      ProjectMilestoneMapper.ensureInitialized();
      ProjectTaskMapper.ensureInitialized();
      ProjectMemoryEntryMapper.ensureInitialized();
      ProjectMemorySupersessionMapper.ensureInitialized();
      PendingProjectQuestionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectPlanProposal';

  static int _$revision(ProjectPlanProposal v) => v.revision;
  static const Field<ProjectPlanProposal, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static List<ProjectPlanRevisionTrigger> _$triggers(ProjectPlanProposal v) =>
      v.triggers;
  static const Field<ProjectPlanProposal, List<ProjectPlanRevisionTrigger>>
  _f$triggers = Field('triggers', _$triggers, opt: true, def: const []);
  static String _$summary(ProjectPlanProposal v) => v.summary;
  static const Field<ProjectPlanProposal, String> _f$summary = Field(
    'summary',
    _$summary,
  );
  static String _$rationale(ProjectPlanProposal v) => v.rationale;
  static const Field<ProjectPlanProposal, String> _f$rationale = Field(
    'rationale',
    _$rationale,
  );
  static List<String> _$assumptions(ProjectPlanProposal v) => v.assumptions;
  static const Field<ProjectPlanProposal, List<String>> _f$assumptions = Field(
    'assumptions',
    _$assumptions,
    opt: true,
    def: const [],
  );
  static List<ProjectCriterion> _$criterionUpserts(ProjectPlanProposal v) =>
      v.criterionUpserts;
  static const Field<ProjectPlanProposal, List<ProjectCriterion>>
  _f$criterionUpserts = Field(
    'criterionUpserts',
    _$criterionUpserts,
    opt: true,
    def: const [],
  );
  static List<String> _$removedCriterionIds(ProjectPlanProposal v) =>
      v.removedCriterionIds;
  static const Field<ProjectPlanProposal, List<String>> _f$removedCriterionIds =
      Field(
        'removedCriterionIds',
        _$removedCriterionIds,
        opt: true,
        def: const [],
      );
  static List<ProjectMilestone> _$milestoneUpserts(ProjectPlanProposal v) =>
      v.milestoneUpserts;
  static const Field<ProjectPlanProposal, List<ProjectMilestone>>
  _f$milestoneUpserts = Field(
    'milestoneUpserts',
    _$milestoneUpserts,
    opt: true,
    def: const [],
  );
  static List<String> _$removedMilestoneIds(ProjectPlanProposal v) =>
      v.removedMilestoneIds;
  static const Field<ProjectPlanProposal, List<String>> _f$removedMilestoneIds =
      Field(
        'removedMilestoneIds',
        _$removedMilestoneIds,
        opt: true,
        def: const [],
      );
  static List<ProjectTask> _$taskAdditions(ProjectPlanProposal v) =>
      v.taskAdditions;
  static const Field<ProjectPlanProposal, List<ProjectTask>> _f$taskAdditions =
      Field('taskAdditions', _$taskAdditions, opt: true, def: const []);
  static List<ProjectTask> _$taskUpdates(ProjectPlanProposal v) =>
      v.taskUpdates;
  static const Field<ProjectPlanProposal, List<ProjectTask>> _f$taskUpdates =
      Field('taskUpdates', _$taskUpdates, opt: true, def: const []);
  static List<String> _$deferredTaskIds(ProjectPlanProposal v) =>
      v.deferredTaskIds;
  static const Field<ProjectPlanProposal, List<String>> _f$deferredTaskIds =
      Field('deferredTaskIds', _$deferredTaskIds, opt: true, def: const []);
  static List<String> _$obsoleteTaskIds(ProjectPlanProposal v) =>
      v.obsoleteTaskIds;
  static const Field<ProjectPlanProposal, List<String>> _f$obsoleteTaskIds =
      Field('obsoleteTaskIds', _$obsoleteTaskIds, opt: true, def: const []);
  static List<ProjectMemoryEntry> _$memoryAdditions(ProjectPlanProposal v) =>
      v.memoryAdditions;
  static const Field<ProjectPlanProposal, List<ProjectMemoryEntry>>
  _f$memoryAdditions = Field(
    'memoryAdditions',
    _$memoryAdditions,
    opt: true,
    def: const [],
  );
  static List<ProjectMemorySupersession> _$memorySupersessions(
    ProjectPlanProposal v,
  ) => v.memorySupersessions;
  static const Field<ProjectPlanProposal, List<ProjectMemorySupersession>>
  _f$memorySupersessions = Field(
    'memorySupersessions',
    _$memorySupersessions,
    opt: true,
    def: const [],
  );
  static List<PendingProjectQuestion> _$openQuestions(ProjectPlanProposal v) =>
      v.openQuestions;
  static const Field<ProjectPlanProposal, List<PendingProjectQuestion>>
  _f$openQuestions = Field(
    'openQuestions',
    _$openQuestions,
    opt: true,
    def: const [],
  );
  static bool _$requiresApproval(ProjectPlanProposal v) => v.requiresApproval;
  static const Field<ProjectPlanProposal, bool> _f$requiresApproval = Field(
    'requiresApproval',
    _$requiresApproval,
    opt: true,
    def: false,
  );
  static String _$approvalReason(ProjectPlanProposal v) => v.approvalReason;
  static const Field<ProjectPlanProposal, String> _f$approvalReason = Field(
    'approvalReason',
    _$approvalReason,
    opt: true,
    def: '',
  );
  static DateTime _$createdAt(ProjectPlanProposal v) => v.createdAt;
  static const Field<ProjectPlanProposal, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );

  @override
  final MappableFields<ProjectPlanProposal> fields = const {
    #revision: _f$revision,
    #triggers: _f$triggers,
    #summary: _f$summary,
    #rationale: _f$rationale,
    #assumptions: _f$assumptions,
    #criterionUpserts: _f$criterionUpserts,
    #removedCriterionIds: _f$removedCriterionIds,
    #milestoneUpserts: _f$milestoneUpserts,
    #removedMilestoneIds: _f$removedMilestoneIds,
    #taskAdditions: _f$taskAdditions,
    #taskUpdates: _f$taskUpdates,
    #deferredTaskIds: _f$deferredTaskIds,
    #obsoleteTaskIds: _f$obsoleteTaskIds,
    #memoryAdditions: _f$memoryAdditions,
    #memorySupersessions: _f$memorySupersessions,
    #openQuestions: _f$openQuestions,
    #requiresApproval: _f$requiresApproval,
    #approvalReason: _f$approvalReason,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectPlanProposal _instantiate(DecodingData data) {
    return ProjectPlanProposal(
      revision: data.dec(_f$revision),
      triggers: data.dec(_f$triggers),
      summary: data.dec(_f$summary),
      rationale: data.dec(_f$rationale),
      assumptions: data.dec(_f$assumptions),
      criterionUpserts: data.dec(_f$criterionUpserts),
      removedCriterionIds: data.dec(_f$removedCriterionIds),
      milestoneUpserts: data.dec(_f$milestoneUpserts),
      removedMilestoneIds: data.dec(_f$removedMilestoneIds),
      taskAdditions: data.dec(_f$taskAdditions),
      taskUpdates: data.dec(_f$taskUpdates),
      deferredTaskIds: data.dec(_f$deferredTaskIds),
      obsoleteTaskIds: data.dec(_f$obsoleteTaskIds),
      memoryAdditions: data.dec(_f$memoryAdditions),
      memorySupersessions: data.dec(_f$memorySupersessions),
      openQuestions: data.dec(_f$openQuestions),
      requiresApproval: data.dec(_f$requiresApproval),
      approvalReason: data.dec(_f$approvalReason),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectPlanProposal fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectPlanProposal>(map);
  }

  static ProjectPlanProposal fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectPlanProposal>(json);
  }
}

/// @nodoc
mixin ProjectPlanProposalMappable {
  String toJson() {
    return ProjectPlanProposalMapper.ensureInitialized()
        .encodeJson<ProjectPlanProposal>(this as ProjectPlanProposal);
  }

  Map<String, dynamic> toMap() {
    return ProjectPlanProposalMapper.ensureInitialized()
        .encodeMap<ProjectPlanProposal>(this as ProjectPlanProposal);
  }
}

/// @nodoc
class ProjectTaskMapper extends ClassMapperBase<ProjectTask> {
  ProjectTaskMapper._();

  static ProjectTaskMapper? _instance;
  static ProjectTaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskMapper._());
      ProjectTaskPriorityMapper.ensureInitialized();
      ProjectTaskRiskMapper.ensureInitialized();
      ProjectRiskReductionMapper.ensureInitialized();
      ProjectTaskEffortMapper.ensureInitialized();
      ProjectTaskReadinessMapper.ensureInitialized();
      ProjectEvidenceExpectationMapper.ensureInitialized();
      ProjectArtifactMapper.ensureInitialized();
      ProjectTaskStatusMapper.ensureInitialized();
      ProjectTaskFailureMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTask';

  static String _$id(ProjectTask v) => v.id;
  static const Field<ProjectTask, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(fallback: 'project_task'),
  );
  static String _$title(ProjectTask v) => v.title;
  static const Field<ProjectTask, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static String _$objective(ProjectTask v) => v.objective;
  static const Field<ProjectTask, String> _f$objective = Field(
    'objective',
    _$objective,
    hook: JsonStringHook(),
  );
  static List<String> _$criterionIds(ProjectTask v) => v.criterionIds;
  static const Field<ProjectTask, List<String>> _f$criterionIds = Field(
    'criterionIds',
    _$criterionIds,
    opt: true,
    hook: JsonStringListHook(),
  );
  static List<String> _$relevantSuccessCriteria(ProjectTask v) =>
      v.relevantSuccessCriteria;
  static const Field<ProjectTask, List<String>> _f$relevantSuccessCriteria =
      Field('relevantSuccessCriteria', _$relevantSuccessCriteria, opt: true);
  static String? _$milestoneId(ProjectTask v) => v.milestoneId;
  static const Field<ProjectTask, String> _f$milestoneId = Field(
    'milestoneId',
    _$milestoneId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static List<String> _$dependsOnTaskIds(ProjectTask v) => v.dependsOnTaskIds;
  static const Field<ProjectTask, List<String>> _f$dependsOnTaskIds = Field(
    'dependsOnTaskIds',
    _$dependsOnTaskIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static ProjectTaskPriority _$priority(ProjectTask v) => v.priority;
  static const Field<ProjectTask, ProjectTaskPriority> _f$priority = Field(
    'priority',
    _$priority,
    opt: true,
    def: ProjectTaskPriority.normal,
  );
  static ProjectTaskRisk _$risk(ProjectTask v) => v.risk;
  static const Field<ProjectTask, ProjectTaskRisk> _f$risk = Field(
    'risk',
    _$risk,
    opt: true,
    def: ProjectTaskRisk.unknown,
  );
  static ProjectRiskReduction _$riskReduction(ProjectTask v) => v.riskReduction;
  static const Field<ProjectTask, ProjectRiskReduction> _f$riskReduction =
      Field(
        'riskReduction',
        _$riskReduction,
        opt: true,
        def: ProjectRiskReduction.none,
      );
  static ProjectTaskEffort _$effort(ProjectTask v) => v.effort;
  static const Field<ProjectTask, ProjectTaskEffort> _f$effort = Field(
    'effort',
    _$effort,
    opt: true,
    def: ProjectTaskEffort.small,
  );
  static ProjectTaskReadiness _$readiness(ProjectTask v) => v.readiness;
  static const Field<ProjectTask, ProjectTaskReadiness> _f$readiness = Field(
    'readiness',
    _$readiness,
    opt: true,
    def: ProjectTaskReadiness.ready,
  );
  static List<String> _$readinessReasons(ProjectTask v) => v.readinessReasons;
  static const Field<ProjectTask, List<String>> _f$readinessReasons = Field(
    'readinessReasons',
    _$readinessReasons,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static String _$selectionRationale(ProjectTask v) => v.selectionRationale;
  static const Field<ProjectTask, String> _f$selectionRationale = Field(
    'selectionRationale',
    _$selectionRationale,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static int _$revisionIntroduced(ProjectTask v) => v.revisionIntroduced;
  static const Field<ProjectTask, int> _f$revisionIntroduced = Field(
    'revisionIntroduced',
    _$revisionIntroduced,
    opt: true,
    def: 1,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static int _$revisionUpdated(ProjectTask v) => v.revisionUpdated;
  static const Field<ProjectTask, int> _f$revisionUpdated = Field(
    'revisionUpdated',
    _$revisionUpdated,
    opt: true,
    def: 1,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static List<ProjectEvidenceExpectation> _$expectedEvidence(ProjectTask v) =>
      v.expectedEvidence;
  static const Field<ProjectTask, List<ProjectEvidenceExpectation>>
  _f$expectedEvidence = Field(
    'expectedEvidence',
    _$expectedEvidence,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static List<String> _$readPaths(ProjectTask v) => v.readPaths;
  static const Field<ProjectTask, List<String>> _f$readPaths = Field(
    'readPaths',
    _$readPaths,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$writePaths(ProjectTask v) => v.writePaths;
  static const Field<ProjectTask, List<String>> _f$writePaths = Field(
    'writePaths',
    _$writePaths,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$doneCriteria(ProjectTask v) => v.doneCriteria;
  static const Field<ProjectTask, List<String>> _f$doneCriteria = Field(
    'doneCriteria',
    _$doneCriteria,
    hook: JsonStringListHook(),
  );
  static List<String> _$outOfScope(ProjectTask v) => v.outOfScope;
  static const Field<ProjectTask, List<String>> _f$outOfScope = Field(
    'outOfScope',
    _$outOfScope,
    hook: JsonStringListHook(),
  );
  static List<String> _$context(ProjectTask v) => v.context;
  static const Field<ProjectTask, List<String>> _f$context = Field(
    'context',
    _$context,
    hook: JsonStringListHook(),
  );
  static List<ProjectArtifact> _$expectedArtifacts(ProjectTask v) =>
      v.expectedArtifacts;
  static const Field<ProjectTask, List<ProjectArtifact>> _f$expectedArtifacts =
      Field(
        'expectedArtifacts',
        _$expectedArtifacts,
        hook: JsonObjectListHook(),
      );
  static ProjectTaskStatus _$status(ProjectTask v) => v.status;
  static const Field<ProjectTask, ProjectTaskStatus> _f$status = Field(
    'status',
    _$status,
    hook: EnumAliasHook({}),
  );
  static String? _$taskDocumentId(ProjectTask v) => v.taskDocumentId;
  static const Field<ProjectTask, String> _f$taskDocumentId = Field(
    'taskDocumentId',
    _$taskDocumentId,
    hook: JsonNullableStringHook(),
  );
  static String? _$recoveryIncidentId(ProjectTask v) => v.recoveryIncidentId;
  static const Field<ProjectTask, String> _f$recoveryIncidentId = Field(
    'recoveryIncidentId',
    _$recoveryIncidentId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$fingerprint(ProjectTask v) => v.fingerprint;
  static const Field<ProjectTask, String> _f$fingerprint = Field(
    'fingerprint',
    _$fingerprint,
    hook: JsonStringHook(),
  );
  static String? _$rejectionReason(ProjectTask v) => v.rejectionReason;
  static const Field<ProjectTask, String> _f$rejectionReason = Field(
    'rejectionReason',
    _$rejectionReason,
    hook: JsonNullableStringHook(),
  );
  static ProjectTaskFailure? _$failure(ProjectTask v) => v.failure;
  static const Field<ProjectTask, ProjectTaskFailure> _f$failure = Field(
    'failure',
    _$failure,
    opt: true,
  );
  static DateTime _$createdAt(ProjectTask v) => v.createdAt;
  static const Field<ProjectTask, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectTask v) => v.updatedAt;
  static const Field<ProjectTask, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<ProjectTask> fields = const {
    #id: _f$id,
    #title: _f$title,
    #objective: _f$objective,
    #criterionIds: _f$criterionIds,
    #relevantSuccessCriteria: _f$relevantSuccessCriteria,
    #milestoneId: _f$milestoneId,
    #dependsOnTaskIds: _f$dependsOnTaskIds,
    #priority: _f$priority,
    #risk: _f$risk,
    #riskReduction: _f$riskReduction,
    #effort: _f$effort,
    #readiness: _f$readiness,
    #readinessReasons: _f$readinessReasons,
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
    #status: _f$status,
    #taskDocumentId: _f$taskDocumentId,
    #recoveryIncidentId: _f$recoveryIncidentId,
    #fingerprint: _f$fingerprint,
    #rejectionReason: _f$rejectionReason,
    #failure: _f$failure,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const ProjectTaskJsonHook();
  static ProjectTask _instantiate(DecodingData data) {
    return ProjectTask(
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      objective: data.dec(_f$objective),
      criterionIds: data.dec(_f$criterionIds),
      relevantSuccessCriteria: data.dec(_f$relevantSuccessCriteria),
      milestoneId: data.dec(_f$milestoneId),
      dependsOnTaskIds: data.dec(_f$dependsOnTaskIds),
      priority: data.dec(_f$priority),
      risk: data.dec(_f$risk),
      riskReduction: data.dec(_f$riskReduction),
      effort: data.dec(_f$effort),
      readiness: data.dec(_f$readiness),
      readinessReasons: data.dec(_f$readinessReasons),
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
      status: data.dec(_f$status),
      taskDocumentId: data.dec(_f$taskDocumentId),
      recoveryIncidentId: data.dec(_f$recoveryIncidentId),
      fingerprint: data.dec(_f$fingerprint),
      rejectionReason: data.dec(_f$rejectionReason),
      failure: data.dec(_f$failure),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTask fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTask>(map);
  }

  static ProjectTask fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTask>(json);
  }
}

/// @nodoc
mixin ProjectTaskMappable {
  String toJson() {
    return ProjectTaskMapper.ensureInitialized().encodeJson<ProjectTask>(
      this as ProjectTask,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskMapper.ensureInitialized().encodeMap<ProjectTask>(
      this as ProjectTask,
    );
  }
}

/// @nodoc
class ProjectArtifactMapper extends ClassMapperBase<ProjectArtifact> {
  ProjectArtifactMapper._();

  static ProjectArtifactMapper? _instance;
  static ProjectArtifactMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectArtifactMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectArtifact';

  static String _$id(ProjectArtifact v) => v.id;
  static const Field<ProjectArtifact, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String? _$projectTaskId(ProjectArtifact v) => v.projectTaskId;
  static const Field<ProjectArtifact, String> _f$projectTaskId = Field(
    'projectTaskId',
    _$projectTaskId,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskDocumentId(ProjectArtifact v) => v.taskDocumentId;
  static const Field<ProjectArtifact, String> _f$taskDocumentId = Field(
    'taskDocumentId',
    _$taskDocumentId,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskRunId(ProjectArtifact v) => v.taskRunId;
  static const Field<ProjectArtifact, String> _f$taskRunId = Field(
    'taskRunId',
    _$taskRunId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$path(ProjectArtifact v) => v.path;
  static const Field<ProjectArtifact, String> _f$path = Field(
    'path',
    _$path,
    hook: JsonStringHook(),
  );
  static String _$description(ProjectArtifact v) => v.description;
  static const Field<ProjectArtifact, String> _f$description = Field(
    'description',
    _$description,
    hook: JsonStringHook(),
  );
  static String _$kind(ProjectArtifact v) => v.kind;
  static const Field<ProjectArtifact, String> _f$kind = Field(
    'kind',
    _$kind,
    hook: JsonStringHook(fallback: 'file'),
  );
  static DateTime _$createdAt(ProjectArtifact v) => v.createdAt;
  static const Field<ProjectArtifact, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<ProjectArtifact> fields = const {
    #id: _f$id,
    #projectTaskId: _f$projectTaskId,
    #taskDocumentId: _f$taskDocumentId,
    #taskRunId: _f$taskRunId,
    #path: _f$path,
    #description: _f$description,
    #kind: _f$kind,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const ProjectArtifactJsonHook();
  static ProjectArtifact _instantiate(DecodingData data) {
    return ProjectArtifact(
      id: data.dec(_f$id),
      projectTaskId: data.dec(_f$projectTaskId),
      taskDocumentId: data.dec(_f$taskDocumentId),
      taskRunId: data.dec(_f$taskRunId),
      path: data.dec(_f$path),
      description: data.dec(_f$description),
      kind: data.dec(_f$kind),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectArtifact fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectArtifact>(map);
  }

  static ProjectArtifact fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectArtifact>(json);
  }
}

/// @nodoc
mixin ProjectArtifactMappable {
  String toJson() {
    return ProjectArtifactMapper.ensureInitialized()
        .encodeJson<ProjectArtifact>(this as ProjectArtifact);
  }

  Map<String, dynamic> toMap() {
    return ProjectArtifactMapper.ensureInitialized().encodeMap<ProjectArtifact>(
      this as ProjectArtifact,
    );
  }
}

/// @nodoc
class ProjectTaskFailureMapper extends ClassMapperBase<ProjectTaskFailure> {
  ProjectTaskFailureMapper._();

  static ProjectTaskFailureMapper? _instance;
  static ProjectTaskFailureMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskFailureMapper._());
      TaskGateFailureDispositionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTaskFailure';

  static String? _$gateId(ProjectTaskFailure v) => v.gateId;
  static const Field<ProjectTaskFailure, String> _f$gateId = Field(
    'gateId',
    _$gateId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static TaskGateFailureDisposition _$disposition(ProjectTaskFailure v) =>
      v.disposition;
  static const Field<ProjectTaskFailure, TaskGateFailureDisposition>
  _f$disposition = Field('disposition', _$disposition, hook: EnumAliasHook({}));
  static String _$failureKey(ProjectTaskFailure v) => v.failureKey;
  static const Field<ProjectTaskFailure, String> _f$failureKey = Field(
    'failureKey',
    _$failureKey,
    hook: JsonStringHook(),
  );
  static String _$summary(ProjectTaskFailure v) => v.summary;
  static const Field<ProjectTaskFailure, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static List<String> _$errorCodes(ProjectTaskFailure v) => v.errorCodes;
  static const Field<ProjectTaskFailure, List<String>> _f$errorCodes = Field(
    'errorCodes',
    _$errorCodes,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$toolCallIds(ProjectTaskFailure v) => v.toolCallIds;
  static const Field<ProjectTaskFailure, List<String>> _f$toolCallIds = Field(
    'toolCallIds',
    _$toolCallIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static int _$advisoryErrorCount(ProjectTaskFailure v) => v.advisoryErrorCount;
  static const Field<ProjectTaskFailure, int> _f$advisoryErrorCount = Field(
    'advisoryErrorCount',
    _$advisoryErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$resolvedErrorCount(ProjectTaskFailure v) => v.resolvedErrorCount;
  static const Field<ProjectTaskFailure, int> _f$resolvedErrorCount = Field(
    'resolvedErrorCount',
    _$resolvedErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$unresolvedErrorCount(ProjectTaskFailure v) =>
      v.unresolvedErrorCount;
  static const Field<ProjectTaskFailure, int> _f$unresolvedErrorCount = Field(
    'unresolvedErrorCount',
    _$unresolvedErrorCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );

  @override
  final MappableFields<ProjectTaskFailure> fields = const {
    #gateId: _f$gateId,
    #disposition: _f$disposition,
    #failureKey: _f$failureKey,
    #summary: _f$summary,
    #errorCodes: _f$errorCodes,
    #toolCallIds: _f$toolCallIds,
    #advisoryErrorCount: _f$advisoryErrorCount,
    #resolvedErrorCount: _f$resolvedErrorCount,
    #unresolvedErrorCount: _f$unresolvedErrorCount,
  };
  @override
  final bool ignoreNull = true;

  static ProjectTaskFailure _instantiate(DecodingData data) {
    return ProjectTaskFailure(
      gateId: data.dec(_f$gateId),
      disposition: data.dec(_f$disposition),
      failureKey: data.dec(_f$failureKey),
      summary: data.dec(_f$summary),
      errorCodes: data.dec(_f$errorCodes),
      toolCallIds: data.dec(_f$toolCallIds),
      advisoryErrorCount: data.dec(_f$advisoryErrorCount),
      resolvedErrorCount: data.dec(_f$resolvedErrorCount),
      unresolvedErrorCount: data.dec(_f$unresolvedErrorCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTaskFailure fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTaskFailure>(map);
  }

  static ProjectTaskFailure fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTaskFailure>(json);
  }
}

/// @nodoc
mixin ProjectTaskFailureMappable {
  String toJson() {
    return ProjectTaskFailureMapper.ensureInitialized()
        .encodeJson<ProjectTaskFailure>(this as ProjectTaskFailure);
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskFailureMapper.ensureInitialized()
        .encodeMap<ProjectTaskFailure>(this as ProjectTaskFailure);
  }
}

/// @nodoc
class PendingProjectQuestionMapper
    extends ClassMapperBase<PendingProjectQuestion> {
  PendingProjectQuestionMapper._();

  static PendingProjectQuestionMapper? _instance;
  static PendingProjectQuestionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PendingProjectQuestionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PendingProjectQuestion';

  static String _$id(PendingProjectQuestion v) => v.id;
  static const Field<PendingProjectQuestion, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$question(PendingProjectQuestion v) => v.question;
  static const Field<PendingProjectQuestion, String> _f$question = Field(
    'question',
    _$question,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(PendingProjectQuestion v) => v.createdAt;
  static const Field<PendingProjectQuestion, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );

  @override
  final MappableFields<PendingProjectQuestion> fields = const {
    #id: _f$id,
    #question: _f$question,
    #createdAt: _f$createdAt,
  };
  @override
  final bool ignoreNull = true;

  static PendingProjectQuestion _instantiate(DecodingData data) {
    return PendingProjectQuestion(
      id: data.dec(_f$id),
      question: data.dec(_f$question),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PendingProjectQuestion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PendingProjectQuestion>(map);
  }

  static PendingProjectQuestion fromJson(String json) {
    return ensureInitialized().decodeJson<PendingProjectQuestion>(json);
  }
}

/// @nodoc
mixin PendingProjectQuestionMappable {
  String toJson() {
    return PendingProjectQuestionMapper.ensureInitialized()
        .encodeJson<PendingProjectQuestion>(this as PendingProjectQuestion);
  }

  Map<String, dynamic> toMap() {
    return PendingProjectQuestionMapper.ensureInitialized()
        .encodeMap<PendingProjectQuestion>(this as PendingProjectQuestion);
  }
}

/// @nodoc
class ProjectPlanRevisionMapper extends ClassMapperBase<ProjectPlanRevision> {
  ProjectPlanRevisionMapper._();

  static ProjectPlanRevisionMapper? _instance;
  static ProjectPlanRevisionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectPlanRevisionMapper._());
      ProjectPlanRevisionTriggerMapper.ensureInitialized();
      ProjectPlanRevisionApproverMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectPlanRevision';

  static int _$revision(ProjectPlanRevision v) => v.revision;
  static const Field<ProjectPlanRevision, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static ProjectPlanRevisionTrigger _$trigger(ProjectPlanRevision v) =>
      v.trigger;
  static const Field<ProjectPlanRevision, ProjectPlanRevisionTrigger>
  _f$trigger = Field('trigger', _$trigger);
  static String _$summary(ProjectPlanRevision v) => v.summary;
  static const Field<ProjectPlanRevision, String> _f$summary = Field(
    'summary',
    _$summary,
  );
  static String _$rationale(ProjectPlanRevision v) => v.rationale;
  static const Field<ProjectPlanRevision, String> _f$rationale = Field(
    'rationale',
    _$rationale,
  );
  static List<String> _$addedTaskIds(ProjectPlanRevision v) => v.addedTaskIds;
  static const Field<ProjectPlanRevision, List<String>> _f$addedTaskIds = Field(
    'addedTaskIds',
    _$addedTaskIds,
    opt: true,
    def: const [],
  );
  static List<String> _$updatedTaskIds(ProjectPlanRevision v) =>
      v.updatedTaskIds;
  static const Field<ProjectPlanRevision, List<String>> _f$updatedTaskIds =
      Field('updatedTaskIds', _$updatedTaskIds, opt: true, def: const []);
  static List<String> _$removedTaskIds(ProjectPlanRevision v) =>
      v.removedTaskIds;
  static const Field<ProjectPlanRevision, List<String>> _f$removedTaskIds =
      Field('removedTaskIds', _$removedTaskIds, opt: true, def: const []);
  static List<String> _$criterionChanges(ProjectPlanRevision v) =>
      v.criterionChanges;
  static const Field<ProjectPlanRevision, List<String>> _f$criterionChanges =
      Field('criterionChanges', _$criterionChanges, opt: true, def: const []);
  static List<String> _$milestoneChanges(ProjectPlanRevision v) =>
      v.milestoneChanges;
  static const Field<ProjectPlanRevision, List<String>> _f$milestoneChanges =
      Field('milestoneChanges', _$milestoneChanges, opt: true, def: const []);
  static List<String> _$validationWarnings(ProjectPlanRevision v) =>
      v.validationWarnings;
  static const Field<ProjectPlanRevision, List<String>> _f$validationWarnings =
      Field(
        'validationWarnings',
        _$validationWarnings,
        opt: true,
        def: const [],
      );
  static DateTime _$createdAt(ProjectPlanRevision v) => v.createdAt;
  static const Field<ProjectPlanRevision, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime? _$approvedAt(ProjectPlanRevision v) => v.approvedAt;
  static const Field<ProjectPlanRevision, DateTime> _f$approvedAt = Field(
    'approvedAt',
    _$approvedAt,
    opt: true,
  );
  static ProjectPlanRevisionApprover? _$approvedBy(ProjectPlanRevision v) =>
      v.approvedBy;
  static const Field<ProjectPlanRevision, ProjectPlanRevisionApprover>
  _f$approvedBy = Field('approvedBy', _$approvedBy, opt: true);

  @override
  final MappableFields<ProjectPlanRevision> fields = const {
    #revision: _f$revision,
    #trigger: _f$trigger,
    #summary: _f$summary,
    #rationale: _f$rationale,
    #addedTaskIds: _f$addedTaskIds,
    #updatedTaskIds: _f$updatedTaskIds,
    #removedTaskIds: _f$removedTaskIds,
    #criterionChanges: _f$criterionChanges,
    #milestoneChanges: _f$milestoneChanges,
    #validationWarnings: _f$validationWarnings,
    #createdAt: _f$createdAt,
    #approvedAt: _f$approvedAt,
    #approvedBy: _f$approvedBy,
  };
  @override
  final bool ignoreNull = true;

  static ProjectPlanRevision _instantiate(DecodingData data) {
    return ProjectPlanRevision(
      revision: data.dec(_f$revision),
      trigger: data.dec(_f$trigger),
      summary: data.dec(_f$summary),
      rationale: data.dec(_f$rationale),
      addedTaskIds: data.dec(_f$addedTaskIds),
      updatedTaskIds: data.dec(_f$updatedTaskIds),
      removedTaskIds: data.dec(_f$removedTaskIds),
      criterionChanges: data.dec(_f$criterionChanges),
      milestoneChanges: data.dec(_f$milestoneChanges),
      validationWarnings: data.dec(_f$validationWarnings),
      createdAt: data.dec(_f$createdAt),
      approvedAt: data.dec(_f$approvedAt),
      approvedBy: data.dec(_f$approvedBy),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectPlanRevision fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectPlanRevision>(map);
  }

  static ProjectPlanRevision fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectPlanRevision>(json);
  }
}

/// @nodoc
mixin ProjectPlanRevisionMappable {
  String toJson() {
    return ProjectPlanRevisionMapper.ensureInitialized()
        .encodeJson<ProjectPlanRevision>(this as ProjectPlanRevision);
  }

  Map<String, dynamic> toMap() {
    return ProjectPlanRevisionMapper.ensureInitialized()
        .encodeMap<ProjectPlanRevision>(this as ProjectPlanRevision);
  }
}

/// @nodoc
class PendingProjectPlanApprovalMapper
    extends ClassMapperBase<PendingProjectPlanApproval> {
  PendingProjectPlanApprovalMapper._();

  static PendingProjectPlanApprovalMapper? _instance;
  static PendingProjectPlanApprovalMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = PendingProjectPlanApprovalMapper._(),
      );
      ProjectPlanProposalMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PendingProjectPlanApproval';

  static int _$revision(PendingProjectPlanApproval v) => v.revision;
  static const Field<PendingProjectPlanApproval, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static String _$reason(PendingProjectPlanApproval v) => v.reason;
  static const Field<PendingProjectPlanApproval, String> _f$reason = Field(
    'reason',
    _$reason,
  );
  static String _$summary(PendingProjectPlanApproval v) => v.summary;
  static const Field<PendingProjectPlanApproval, String> _f$summary = Field(
    'summary',
    _$summary,
  );
  static List<String> _$highRiskChanges(PendingProjectPlanApproval v) =>
      v.highRiskChanges;
  static const Field<PendingProjectPlanApproval, List<String>>
  _f$highRiskChanges = Field(
    'highRiskChanges',
    _$highRiskChanges,
    opt: true,
    def: const [],
  );
  static DateTime _$createdAt(PendingProjectPlanApproval v) => v.createdAt;
  static const Field<PendingProjectPlanApproval, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static ProjectPlanProposal? _$proposal(PendingProjectPlanApproval v) =>
      v.proposal;
  static const Field<PendingProjectPlanApproval, ProjectPlanProposal>
  _f$proposal = Field('proposal', _$proposal, opt: true);

  @override
  final MappableFields<PendingProjectPlanApproval> fields = const {
    #revision: _f$revision,
    #reason: _f$reason,
    #summary: _f$summary,
    #highRiskChanges: _f$highRiskChanges,
    #createdAt: _f$createdAt,
    #proposal: _f$proposal,
  };
  @override
  final bool ignoreNull = true;

  static PendingProjectPlanApproval _instantiate(DecodingData data) {
    return PendingProjectPlanApproval(
      revision: data.dec(_f$revision),
      reason: data.dec(_f$reason),
      summary: data.dec(_f$summary),
      highRiskChanges: data.dec(_f$highRiskChanges),
      createdAt: data.dec(_f$createdAt),
      proposal: data.dec(_f$proposal),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PendingProjectPlanApproval fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PendingProjectPlanApproval>(map);
  }

  static PendingProjectPlanApproval fromJson(String json) {
    return ensureInitialized().decodeJson<PendingProjectPlanApproval>(json);
  }
}

/// @nodoc
mixin PendingProjectPlanApprovalMappable {
  String toJson() {
    return PendingProjectPlanApprovalMapper.ensureInitialized()
        .encodeJson<PendingProjectPlanApproval>(
          this as PendingProjectPlanApproval,
        );
  }

  Map<String, dynamic> toMap() {
    return PendingProjectPlanApprovalMapper.ensureInitialized()
        .encodeMap<PendingProjectPlanApproval>(
          this as PendingProjectPlanApproval,
        );
  }
}

/// @nodoc
class ProjectStateMapper extends ClassMapperBase<ProjectState> {
  ProjectStateMapper._();

  static ProjectStateMapper? _instance;
  static ProjectStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectStateMapper._());
      ProjectCriterionMapper.ensureInitialized();
      ProjectTaskMapper.ensureInitialized();
      ProjectArtifactMapper.ensureInitialized();
      ProjectRecoveryIncidentMapper.ensureInitialized();
      ProjectEvidenceMapper.ensureInitialized();
      ProjectMilestoneMapper.ensureInitialized();
      ProjectMemoryEntryMapper.ensureInitialized();
      ProjectPlanRevisionMapper.ensureInitialized();
      PendingProjectPlanApprovalMapper.ensureInitialized();
      ProjectPlanRevisionTriggerMapper.ensureInitialized();
      PendingProjectQuestionMapper.ensureInitialized();
      ProjectTaskRefMapper.ensureInitialized();
      ProjectStatusMapper.ensureInitialized();
      ProjectPhaseMapper.ensureInitialized();
      ProjectBlockerMapper.ensureInitialized();
      ProjectDecisionRecordMapper.ensureInitialized();
      ProjectDiagnosticsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectState';

  static int _$schemaVersion(ProjectState v) => v.schemaVersion;
  static const Field<ProjectState, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: ProjectState.currentSchemaVersion,
    hook: JsonIntHook(),
  );
  static String _$id(ProjectState v) => v.id;
  static const Field<ProjectState, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static String _$title(ProjectState v) => v.title;
  static const Field<ProjectState, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled project'),
  );
  static String _$originalGoal(ProjectState v) => v.originalGoal;
  static const Field<ProjectState, String> _f$originalGoal = Field(
    'originalGoal',
    _$originalGoal,
    opt: true,
    hook: JsonStringHook(),
  );
  static String _$refinedGoal(ProjectState v) => v.refinedGoal;
  static const Field<ProjectState, String> _f$refinedGoal = Field(
    'refinedGoal',
    _$refinedGoal,
    opt: true,
    hook: JsonStringHook(),
  );
  static String _$originalPrompt(ProjectState v) => v.originalPrompt;
  static const Field<ProjectState, String> _f$originalPrompt = Field(
    'originalPrompt',
    _$originalPrompt,
    opt: true,
  );
  static String _$goal(ProjectState v) => v.goal;
  static const Field<ProjectState, String> _f$goal = Field(
    'goal',
    _$goal,
    opt: true,
  );
  static List<ProjectCriterion> _$criteria(ProjectState v) => v.criteria;
  static const Field<ProjectState, List<ProjectCriterion>> _f$criteria = Field(
    'criteria',
    _$criteria,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<String> _$successCriteria(ProjectState v) => v.successCriteria;
  static const Field<ProjectState, List<String>> _f$successCriteria = Field(
    'successCriteria',
    _$successCriteria,
    opt: true,
  );
  static List<String> _$constraints(ProjectState v) => v.constraints;
  static const Field<ProjectState, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    hook: JsonStringListHook(),
  );
  static List<ProjectTask> _$backlog(ProjectState v) => v.backlog;
  static const Field<ProjectState, List<ProjectTask>> _f$backlog = Field(
    'backlog',
    _$backlog,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static ProjectTask? _$currentTask(ProjectState v) => v.currentTask;
  static const Field<ProjectState, ProjectTask> _f$currentTask = Field(
    'currentTask',
    _$currentTask,
    opt: true,
  );
  static List<ProjectTask> _$completedTasks(ProjectState v) => v.completedTasks;
  static const Field<ProjectState, List<ProjectTask>> _f$completedTasks = Field(
    'completedTasks',
    _$completedTasks,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectTask> _$failedTasks(ProjectState v) => v.failedTasks;
  static const Field<ProjectState, List<ProjectTask>> _f$failedTasks = Field(
    'failedTasks',
    _$failedTasks,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectArtifact> _$artifacts(ProjectState v) => v.artifacts;
  static const Field<ProjectState, List<ProjectArtifact>> _f$artifacts = Field(
    'artifacts',
    _$artifacts,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectRecoveryIncident> _$recoveryIncidents(ProjectState v) =>
      v.recoveryIncidents;
  static const Field<ProjectState, List<ProjectRecoveryIncident>>
  _f$recoveryIncidents = Field(
    'recoveryIncidents',
    _$recoveryIncidents,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectEvidence> _$evidence(ProjectState v) => v.evidence;
  static const Field<ProjectState, List<ProjectEvidence>> _f$evidence = Field(
    'evidence',
    _$evidence,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<ProjectMilestone> _$milestones(ProjectState v) => v.milestones;
  static const Field<ProjectState, List<ProjectMilestone>> _f$milestones =
      Field('milestones', _$milestones, opt: true, hook: JsonObjectListHook());
  static List<ProjectMemoryEntry> _$memory(ProjectState v) => v.memory;
  static const Field<ProjectState, List<ProjectMemoryEntry>> _f$memory = Field(
    'memory',
    _$memory,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<String> _$knownFacts(ProjectState v) => v.knownFacts;
  static const Field<ProjectState, List<String>> _f$knownFacts = Field(
    'knownFacts',
    _$knownFacts,
    opt: true,
  );
  static int _$currentRevision(ProjectState v) => v.currentRevision;
  static const Field<ProjectState, int> _f$currentRevision = Field(
    'currentRevision',
    _$currentRevision,
    opt: true,
    hook: JsonIntHook(fallback: 1, min: 1),
  );
  static List<ProjectPlanRevision> _$planHistory(ProjectState v) =>
      v.planHistory;
  static const Field<ProjectState, List<ProjectPlanRevision>> _f$planHistory =
      Field(
        'planHistory',
        _$planHistory,
        opt: true,
        hook: JsonObjectListHook(),
      );
  static PendingProjectPlanApproval? _$pendingPlanApproval(ProjectState v) =>
      v.pendingPlanApproval;
  static const Field<ProjectState, PendingProjectPlanApproval>
  _f$pendingPlanApproval = Field(
    'pendingPlanApproval',
    _$pendingPlanApproval,
    opt: true,
  );
  static List<ProjectPlanRevisionTrigger> _$pendingReplanTriggers(
    ProjectState v,
  ) => v.pendingReplanTriggers;
  static const Field<ProjectState, List<ProjectPlanRevisionTrigger>>
  _f$pendingReplanTriggers = Field(
    'pendingReplanTriggers',
    _$pendingReplanTriggers,
    opt: true,
    def: const [],
  );
  static List<PendingProjectQuestion> _$openQuestions(ProjectState v) =>
      v.openQuestions;
  static const Field<ProjectState, List<PendingProjectQuestion>>
  _f$openQuestions = Field(
    'openQuestions',
    _$openQuestions,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static String _$memorySummary(ProjectState v) => v.memorySummary;
  static const Field<ProjectState, String> _f$memorySummary = Field(
    'memorySummary',
    _$memorySummary,
    opt: true,
  );
  static List<ProjectTaskRef> _$tasks(ProjectState v) => v.tasks;
  static const Field<ProjectState, List<ProjectTaskRef>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
  );
  static PendingProjectQuestion? _$pendingQuestion(ProjectState v) =>
      v.pendingQuestion;
  static const Field<ProjectState, PendingProjectQuestion> _f$pendingQuestion =
      Field('pendingQuestion', _$pendingQuestion, opt: true);
  static ProjectStatus _$status(ProjectState v) => v.status;
  static const Field<ProjectState, ProjectStatus> _f$status = Field(
    'status',
    _$status,
    hook: EnumAliasHook({
      'running': 'running_task',
      'runningtask': 'running_task',
      'reviewingtask': 'reviewing_task',
      'waitingforuser': 'waiting_for_user',
    }),
  );
  static ProjectPhase _$phase(ProjectState v) => v.phase;
  static const Field<ProjectState, ProjectPhase> _f$phase = Field(
    'phase',
    _$phase,
    opt: true,
    hook: EnumAliasHook({}),
  );
  static int _$iterationCount(ProjectState v) => v.iterationCount;
  static const Field<ProjectState, int> _f$iterationCount = Field(
    'iterationCount',
    _$iterationCount,
    opt: true,
    hook: JsonIntHook(),
  );
  static int _$maxIterations(ProjectState v) => v.maxIterations;
  static const Field<ProjectState, int> _f$maxIterations = Field(
    'maxIterations',
    _$maxIterations,
    opt: true,
    def: ProjectState.defaultMaxIterations,
    hook: JsonIntHook(fallback: ProjectState.defaultMaxIterations, min: 0),
  );
  static int _$maxFailedTasks(ProjectState v) => v.maxFailedTasks;
  static const Field<ProjectState, int> _f$maxFailedTasks = Field(
    'maxFailedTasks',
    _$maxFailedTasks,
    opt: true,
    def: ProjectState.defaultMaxFailedTasks,
    hook: JsonIntHook(
      fallback: ProjectState.defaultMaxFailedTasks,
      min: 1,
      max: 100,
    ),
  );
  static String? _$activeTaskId(ProjectState v) => v.activeTaskId;
  static const Field<ProjectState, String> _f$activeTaskId = Field(
    'activeTaskId',
    _$activeTaskId,
    hook: JsonNullableStringHook(),
  );
  static String? _$chatSessionId(ProjectState v) => v.chatSessionId;
  static const Field<ProjectState, String> _f$chatSessionId = Field(
    'chatSessionId',
    _$chatSessionId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String _$completionSummary(ProjectState v) => v.completionSummary;
  static const Field<ProjectState, String> _f$completionSummary = Field(
    'completionSummary',
    _$completionSummary,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static ProjectBlocker? _$blocker(ProjectState v) => v.blocker;
  static const Field<ProjectState, ProjectBlocker> _f$blocker = Field(
    'blocker',
    _$blocker,
    opt: true,
  );
  static List<ProjectDecisionRecord> _$decisions(ProjectState v) => v.decisions;
  static const Field<ProjectState, List<ProjectDecisionRecord>> _f$decisions =
      Field(
        'decisions',
        _$decisions,
        opt: true,
        def: const [],
        hook: JsonObjectListHook(),
      );
  static ProjectDiagnostics _$diagnostics(ProjectState v) => v.diagnostics;
  static const Field<ProjectState, ProjectDiagnostics> _f$diagnostics = Field(
    'diagnostics',
    _$diagnostics,
    opt: true,
    def: const ProjectDiagnostics(),
  );
  static DateTime _$createdAt(ProjectState v) => v.createdAt;
  static const Field<ProjectState, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectState v) => v.updatedAt;
  static const Field<ProjectState, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$completedAt(ProjectState v) => v.completedAt;
  static const Field<ProjectState, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<ProjectState> fields = const {
    #schemaVersion: _f$schemaVersion,
    #id: _f$id,
    #title: _f$title,
    #originalGoal: _f$originalGoal,
    #refinedGoal: _f$refinedGoal,
    #originalPrompt: _f$originalPrompt,
    #goal: _f$goal,
    #criteria: _f$criteria,
    #successCriteria: _f$successCriteria,
    #constraints: _f$constraints,
    #backlog: _f$backlog,
    #currentTask: _f$currentTask,
    #completedTasks: _f$completedTasks,
    #failedTasks: _f$failedTasks,
    #artifacts: _f$artifacts,
    #recoveryIncidents: _f$recoveryIncidents,
    #evidence: _f$evidence,
    #milestones: _f$milestones,
    #memory: _f$memory,
    #knownFacts: _f$knownFacts,
    #currentRevision: _f$currentRevision,
    #planHistory: _f$planHistory,
    #pendingPlanApproval: _f$pendingPlanApproval,
    #pendingReplanTriggers: _f$pendingReplanTriggers,
    #openQuestions: _f$openQuestions,
    #memorySummary: _f$memorySummary,
    #tasks: _f$tasks,
    #pendingQuestion: _f$pendingQuestion,
    #status: _f$status,
    #phase: _f$phase,
    #iterationCount: _f$iterationCount,
    #maxIterations: _f$maxIterations,
    #maxFailedTasks: _f$maxFailedTasks,
    #activeTaskId: _f$activeTaskId,
    #chatSessionId: _f$chatSessionId,
    #completionSummary: _f$completionSummary,
    #blocker: _f$blocker,
    #decisions: _f$decisions,
    #diagnostics: _f$diagnostics,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  @override
  final MappingHook hook = const ProjectStateJsonHook();
  static ProjectState _instantiate(DecodingData data) {
    return ProjectState(
      schemaVersion: data.dec(_f$schemaVersion),
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      originalGoal: data.dec(_f$originalGoal),
      refinedGoal: data.dec(_f$refinedGoal),
      originalPrompt: data.dec(_f$originalPrompt),
      goal: data.dec(_f$goal),
      criteria: data.dec(_f$criteria),
      successCriteria: data.dec(_f$successCriteria),
      constraints: data.dec(_f$constraints),
      backlog: data.dec(_f$backlog),
      currentTask: data.dec(_f$currentTask),
      completedTasks: data.dec(_f$completedTasks),
      failedTasks: data.dec(_f$failedTasks),
      artifacts: data.dec(_f$artifacts),
      recoveryIncidents: data.dec(_f$recoveryIncidents),
      evidence: data.dec(_f$evidence),
      milestones: data.dec(_f$milestones),
      memory: data.dec(_f$memory),
      knownFacts: data.dec(_f$knownFacts),
      currentRevision: data.dec(_f$currentRevision),
      planHistory: data.dec(_f$planHistory),
      pendingPlanApproval: data.dec(_f$pendingPlanApproval),
      pendingReplanTriggers: data.dec(_f$pendingReplanTriggers),
      openQuestions: data.dec(_f$openQuestions),
      memorySummary: data.dec(_f$memorySummary),
      tasks: data.dec(_f$tasks),
      pendingQuestion: data.dec(_f$pendingQuestion),
      status: data.dec(_f$status),
      phase: data.dec(_f$phase),
      iterationCount: data.dec(_f$iterationCount),
      maxIterations: data.dec(_f$maxIterations),
      maxFailedTasks: data.dec(_f$maxFailedTasks),
      activeTaskId: data.dec(_f$activeTaskId),
      chatSessionId: data.dec(_f$chatSessionId),
      completionSummary: data.dec(_f$completionSummary),
      blocker: data.dec(_f$blocker),
      decisions: data.dec(_f$decisions),
      diagnostics: data.dec(_f$diagnostics),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectState>(map);
  }

  static ProjectState fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectState>(json);
  }
}

/// @nodoc
mixin ProjectStateMappable {
  String toJson() {
    return ProjectStateMapper.ensureInitialized().encodeJson<ProjectState>(
      this as ProjectState,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectStateMapper.ensureInitialized().encodeMap<ProjectState>(
      this as ProjectState,
    );
  }
}

/// @nodoc
class ProjectRecoveryIncidentMapper
    extends ClassMapperBase<ProjectRecoveryIncident> {
  ProjectRecoveryIncidentMapper._();

  static ProjectRecoveryIncidentMapper? _instance;
  static ProjectRecoveryIncidentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectRecoveryIncidentMapper._(),
      );
      ProjectRecoveryIncidentStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectRecoveryIncident';

  static String _$id(ProjectRecoveryIncident v) => v.id;
  static const Field<ProjectRecoveryIncident, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(fallback: 'recovery_incident'),
  );
  static ProjectRecoveryIncidentStatus _$status(ProjectRecoveryIncident v) =>
      v.status;
  static const Field<ProjectRecoveryIncident, ProjectRecoveryIncidentStatus>
  _f$status = Field('status', _$status, hook: EnumAliasHook({}));
  static List<String> _$sourceTaskIds(ProjectRecoveryIncident v) =>
      v.sourceTaskIds;
  static const Field<ProjectRecoveryIncident, List<String>> _f$sourceTaskIds =
      Field('sourceTaskIds', _$sourceTaskIds, hook: JsonStringListHook());
  static List<String> _$sourceTaskTitles(ProjectRecoveryIncident v) =>
      v.sourceTaskTitles;
  static const Field<ProjectRecoveryIncident, List<String>>
  _f$sourceTaskTitles = Field(
    'sourceTaskTitles',
    _$sourceTaskTitles,
    hook: JsonStringListHook(),
  );
  static String _$failedGateId(ProjectRecoveryIncident v) => v.failedGateId;
  static const Field<ProjectRecoveryIncident, String> _f$failedGateId = Field(
    'failedGateId',
    _$failedGateId,
    hook: JsonStringHook(),
  );
  static String? _$command(ProjectRecoveryIncident v) => v.command;
  static const Field<ProjectRecoveryIncident, String> _f$command = Field(
    'command',
    _$command,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$workingDirectory(ProjectRecoveryIncident v) =>
      v.workingDirectory;
  static const Field<ProjectRecoveryIncident, String> _f$workingDirectory =
      Field(
        'workingDirectory',
        _$workingDirectory,
        opt: true,
        hook: JsonNullableStringHook(),
      );
  static String _$failureSummary(ProjectRecoveryIncident v) => v.failureSummary;
  static const Field<ProjectRecoveryIncident, String> _f$failureSummary = Field(
    'failureSummary',
    _$failureSummary,
    hook: JsonStringHook(),
  );
  static int _$attemptCount(ProjectRecoveryIncident v) => v.attemptCount;
  static const Field<ProjectRecoveryIncident, int> _f$attemptCount = Field(
    'attemptCount',
    _$attemptCount,
    hook: JsonIntHook(),
  );
  static int _$maxAttempts(ProjectRecoveryIncident v) => v.maxAttempts;
  static const Field<ProjectRecoveryIncident, int> _f$maxAttempts = Field(
    'maxAttempts',
    _$maxAttempts,
    opt: true,
    def: ProjectRecoveryIncident.defaultMaxAttempts,
    hook: JsonIntHook(
      fallback: ProjectRecoveryIncident.defaultMaxAttempts,
      min: 1,
      max: 100,
    ),
  );
  static List<String> _$recoveryTaskIds(ProjectRecoveryIncident v) =>
      v.recoveryTaskIds;
  static const Field<ProjectRecoveryIncident, List<String>> _f$recoveryTaskIds =
      Field('recoveryTaskIds', _$recoveryTaskIds, hook: JsonStringListHook());
  static DateTime _$createdAt(ProjectRecoveryIncident v) => v.createdAt;
  static const Field<ProjectRecoveryIncident, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectRecoveryIncident v) => v.updatedAt;
  static const Field<ProjectRecoveryIncident, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$resolvedAt(ProjectRecoveryIncident v) => v.resolvedAt;
  static const Field<ProjectRecoveryIncident, DateTime> _f$resolvedAt = Field(
    'resolvedAt',
    _$resolvedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<ProjectRecoveryIncident> fields = const {
    #id: _f$id,
    #status: _f$status,
    #sourceTaskIds: _f$sourceTaskIds,
    #sourceTaskTitles: _f$sourceTaskTitles,
    #failedGateId: _f$failedGateId,
    #command: _f$command,
    #workingDirectory: _f$workingDirectory,
    #failureSummary: _f$failureSummary,
    #attemptCount: _f$attemptCount,
    #maxAttempts: _f$maxAttempts,
    #recoveryTaskIds: _f$recoveryTaskIds,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #resolvedAt: _f$resolvedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectRecoveryIncident _instantiate(DecodingData data) {
    return ProjectRecoveryIncident(
      id: data.dec(_f$id),
      status: data.dec(_f$status),
      sourceTaskIds: data.dec(_f$sourceTaskIds),
      sourceTaskTitles: data.dec(_f$sourceTaskTitles),
      failedGateId: data.dec(_f$failedGateId),
      command: data.dec(_f$command),
      workingDirectory: data.dec(_f$workingDirectory),
      failureSummary: data.dec(_f$failureSummary),
      attemptCount: data.dec(_f$attemptCount),
      maxAttempts: data.dec(_f$maxAttempts),
      recoveryTaskIds: data.dec(_f$recoveryTaskIds),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      resolvedAt: data.dec(_f$resolvedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectRecoveryIncident fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectRecoveryIncident>(map);
  }

  static ProjectRecoveryIncident fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectRecoveryIncident>(json);
  }
}

/// @nodoc
mixin ProjectRecoveryIncidentMappable {
  String toJson() {
    return ProjectRecoveryIncidentMapper.ensureInitialized()
        .encodeJson<ProjectRecoveryIncident>(this as ProjectRecoveryIncident);
  }

  Map<String, dynamic> toMap() {
    return ProjectRecoveryIncidentMapper.ensureInitialized()
        .encodeMap<ProjectRecoveryIncident>(this as ProjectRecoveryIncident);
  }
}

/// @nodoc
class ProjectTaskRefMapper extends ClassMapperBase<ProjectTaskRef> {
  ProjectTaskRefMapper._();

  static ProjectTaskRefMapper? _instance;
  static ProjectTaskRefMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectTaskRefMapper._());
      TaskStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectTaskRef';

  static String _$taskId(ProjectTaskRef v) => v.taskId;
  static const Field<ProjectTaskRef, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    hook: JsonStringHook(),
  );
  static String _$title(ProjectTaskRef v) => v.title;
  static const Field<ProjectTaskRef, String> _f$title = Field(
    'title',
    _$title,
    hook: JsonStringHook(fallback: 'Untitled task'),
  );
  static TaskStatus _$status(ProjectTaskRef v) => v.status;
  static const Field<ProjectTaskRef, TaskStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String _$summary(ProjectTaskRef v) => v.summary;
  static const Field<ProjectTaskRef, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(ProjectTaskRef v) => v.createdAt;
  static const Field<ProjectTaskRef, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static DateTime _$updatedAt(ProjectTaskRef v) => v.updatedAt;
  static const Field<ProjectTaskRef, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    hook: JsonDateHook(),
  );
  static DateTime? _$completedAt(ProjectTaskRef v) => v.completedAt;
  static const Field<ProjectTaskRef, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );

  @override
  final MappableFields<ProjectTaskRef> fields = const {
    #taskId: _f$taskId,
    #title: _f$title,
    #status: _f$status,
    #summary: _f$summary,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #completedAt: _f$completedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectTaskRef _instantiate(DecodingData data) {
    return ProjectTaskRef(
      taskId: data.dec(_f$taskId),
      title: data.dec(_f$title),
      status: data.dec(_f$status),
      summary: data.dec(_f$summary),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      completedAt: data.dec(_f$completedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectTaskRef fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectTaskRef>(map);
  }

  static ProjectTaskRef fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectTaskRef>(json);
  }
}

/// @nodoc
mixin ProjectTaskRefMappable {
  String toJson() {
    return ProjectTaskRefMapper.ensureInitialized().encodeJson<ProjectTaskRef>(
      this as ProjectTaskRef,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectTaskRefMapper.ensureInitialized().encodeMap<ProjectTaskRef>(
      this as ProjectTaskRef,
    );
  }
}

/// @nodoc
class ProjectBlockerMapper extends ClassMapperBase<ProjectBlocker> {
  ProjectBlockerMapper._();

  static ProjectBlockerMapper? _instance;
  static ProjectBlockerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectBlockerMapper._());
      ProjectBlockerTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectBlocker';

  static ProjectBlockerType _$type(ProjectBlocker v) => v.type;
  static const Field<ProjectBlocker, ProjectBlockerType> _f$type = Field(
    'type',
    _$type,
    hook: EnumAliasHook({
      'taskapproval': 'task_approval',
      'taskblocked': 'task_blocked',
      'taskfailed': 'task_failed',
      'recoveryfailed': 'recovery_failed',
      'duplicatetask': 'duplicate_task',
      'oversizedtask': 'oversized_task',
      'maxfailures': 'max_failures',
      'planapproval': 'plan_approval',
    }),
  );
  static String _$message(ProjectBlocker v) => v.message;
  static const Field<ProjectBlocker, String> _f$message = Field(
    'message',
    _$message,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(ProjectBlocker v) => v.createdAt;
  static const Field<ProjectBlocker, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static String? _$taskId(ProjectBlocker v) => v.taskId;
  static const Field<ProjectBlocker, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<ProjectBlocker> fields = const {
    #type: _f$type,
    #message: _f$message,
    #createdAt: _f$createdAt,
    #taskId: _f$taskId,
  };
  @override
  final bool ignoreNull = true;

  static ProjectBlocker _instantiate(DecodingData data) {
    return ProjectBlocker(
      type: data.dec(_f$type),
      message: data.dec(_f$message),
      createdAt: data.dec(_f$createdAt),
      taskId: data.dec(_f$taskId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectBlocker fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectBlocker>(map);
  }

  static ProjectBlocker fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectBlocker>(json);
  }
}

/// @nodoc
mixin ProjectBlockerMappable {
  String toJson() {
    return ProjectBlockerMapper.ensureInitialized().encodeJson<ProjectBlocker>(
      this as ProjectBlocker,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectBlockerMapper.ensureInitialized().encodeMap<ProjectBlocker>(
      this as ProjectBlocker,
    );
  }
}

/// @nodoc
class ProjectDecisionRecordMapper
    extends ClassMapperBase<ProjectDecisionRecord> {
  ProjectDecisionRecordMapper._();

  static ProjectDecisionRecordMapper? _instance;
  static ProjectDecisionRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectDecisionRecordMapper._());
      ProjectDecisionTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectDecisionRecord';

  static String _$id(ProjectDecisionRecord v) => v.id;
  static const Field<ProjectDecisionRecord, String> _f$id = Field(
    'id',
    _$id,
    hook: JsonStringHook(),
  );
  static ProjectDecisionType _$decision(ProjectDecisionRecord v) => v.decision;
  static const Field<ProjectDecisionRecord, ProjectDecisionType> _f$decision =
      Field(
        'decision',
        _$decision,
        hook: EnumAliasHook({
          'createtask': 'create_task',
          'createrecoverytask': 'create_recovery_task',
          'rejecttask': 'reject_task',
          'splittask': 'split_task',
          'evaluatetask': 'evaluate_task',
          'refreshbacklog': 'refresh_backlog',
          'retryrecovery': 'retry_recovery',
          'applyplanrevision': 'apply_plan_revision',
          'approveplanrevision': 'approve_plan_revision',
          'rejectplanrevision': 'reject_plan_revision',
        }),
      );
  static String _$summary(ProjectDecisionRecord v) => v.summary;
  static const Field<ProjectDecisionRecord, String> _f$summary = Field(
    'summary',
    _$summary,
    hook: JsonStringHook(),
  );
  static String _$memoryUpdate(ProjectDecisionRecord v) => v.memoryUpdate;
  static const Field<ProjectDecisionRecord, String> _f$memoryUpdate = Field(
    'memoryUpdate',
    _$memoryUpdate,
    hook: JsonStringHook(),
  );
  static DateTime _$createdAt(ProjectDecisionRecord v) => v.createdAt;
  static const Field<ProjectDecisionRecord, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    hook: JsonDateHook(),
  );
  static String? _$taskId(ProjectDecisionRecord v) => v.taskId;
  static const Field<ProjectDecisionRecord, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskTitle(ProjectDecisionRecord v) => v.taskTitle;
  static const Field<ProjectDecisionRecord, String> _f$taskTitle = Field(
    'taskTitle',
    _$taskTitle,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$taskPrompt(ProjectDecisionRecord v) => v.taskPrompt;
  static const Field<ProjectDecisionRecord, String> _f$taskPrompt = Field(
    'taskPrompt',
    _$taskPrompt,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static String? _$error(ProjectDecisionRecord v) => v.error;
  static const Field<ProjectDecisionRecord, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
    hook: JsonNullableStringHook(),
  );

  @override
  final MappableFields<ProjectDecisionRecord> fields = const {
    #id: _f$id,
    #decision: _f$decision,
    #summary: _f$summary,
    #memoryUpdate: _f$memoryUpdate,
    #createdAt: _f$createdAt,
    #taskId: _f$taskId,
    #taskTitle: _f$taskTitle,
    #taskPrompt: _f$taskPrompt,
    #error: _f$error,
  };
  @override
  final bool ignoreNull = true;

  static ProjectDecisionRecord _instantiate(DecodingData data) {
    return ProjectDecisionRecord(
      id: data.dec(_f$id),
      decision: data.dec(_f$decision),
      summary: data.dec(_f$summary),
      memoryUpdate: data.dec(_f$memoryUpdate),
      createdAt: data.dec(_f$createdAt),
      taskId: data.dec(_f$taskId),
      taskTitle: data.dec(_f$taskTitle),
      taskPrompt: data.dec(_f$taskPrompt),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectDecisionRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectDecisionRecord>(map);
  }

  static ProjectDecisionRecord fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectDecisionRecord>(json);
  }
}

/// @nodoc
mixin ProjectDecisionRecordMappable {
  String toJson() {
    return ProjectDecisionRecordMapper.ensureInitialized()
        .encodeJson<ProjectDecisionRecord>(this as ProjectDecisionRecord);
  }

  Map<String, dynamic> toMap() {
    return ProjectDecisionRecordMapper.ensureInitialized()
        .encodeMap<ProjectDecisionRecord>(this as ProjectDecisionRecord);
  }
}

