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

class TaskReadinessMapper extends EnumMapper<TaskReadiness> {
  TaskReadinessMapper._();

  static TaskReadinessMapper? _instance;
  static TaskReadinessMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskReadinessMapper._());
    }
    return _instance!;
  }

  static TaskReadiness fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskReadiness decode(dynamic value) {
    switch (value) {
      case r'ready':
        return TaskReadiness.ready;
      case 'waiting_dependency':
        return TaskReadiness.waitingDependency;
      case 'waiting_input':
        return TaskReadiness.waitingInput;
      case 'not_eligible':
        return TaskReadiness.notEligible;
      default:
        return TaskReadiness.values[0];
    }
  }

  @override
  dynamic encode(TaskReadiness self) {
    switch (self) {
      case TaskReadiness.ready:
        return r'ready';
      case TaskReadiness.waitingDependency:
        return 'waiting_dependency';
      case TaskReadiness.waitingInput:
        return 'waiting_input';
      case TaskReadiness.notEligible:
        return 'not_eligible';
    }
  }
}

/// @nodoc

extension TaskReadinessMapperExtension on TaskReadiness {
  dynamic toValue() {
    TaskReadinessMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskReadiness>(this);
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
      case r'system':
        return ProjectMemorySourceType.system;
      default:
        return ProjectMemorySourceType.values[4];
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
      case 'batch_complete':
        return ProjectPlanRevisionTrigger.batchComplete;
      case 'scope_changed':
        return ProjectPlanRevisionTrigger.scopeChanged;
      case 'milestone_roadmap_changed':
        return ProjectPlanRevisionTrigger.milestoneRoadmapChanged;
      default:
        return ProjectPlanRevisionTrigger.values[0];
    }
  }

  @override
  dynamic encode(ProjectPlanRevisionTrigger self) {
    switch (self) {
      case ProjectPlanRevisionTrigger.initialization:
        return r'initialization';
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
      case ProjectPlanRevisionTrigger.batchComplete:
        return 'batch_complete';
      case ProjectPlanRevisionTrigger.scopeChanged:
        return 'scope_changed';
      case ProjectPlanRevisionTrigger.milestoneRoadmapChanged:
        return 'milestone_roadmap_changed';
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

class ProjectCompletionReviewReasonMapper
    extends EnumMapper<ProjectCompletionReviewReason> {
  ProjectCompletionReviewReasonMapper._();

  static ProjectCompletionReviewReasonMapper? _instance;
  static ProjectCompletionReviewReasonMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectCompletionReviewReasonMapper._(),
      );
    }
    return _instance!;
  }

  static ProjectCompletionReviewReason fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectCompletionReviewReason decode(dynamic value) {
    switch (value) {
      case 'no_remaining_tasks':
        return ProjectCompletionReviewReason.noRemainingTasks;
      case 'milestone_ended':
        return ProjectCompletionReviewReason.milestoneEnded;
      case 'batch_ended':
        return ProjectCompletionReviewReason.batchEnded;
      case 'final_criterion_evidence':
        return ProjectCompletionReviewReason.finalCriterionEvidence;
      default:
        return ProjectCompletionReviewReason.values[0];
    }
  }

  @override
  dynamic encode(ProjectCompletionReviewReason self) {
    switch (self) {
      case ProjectCompletionReviewReason.noRemainingTasks:
        return 'no_remaining_tasks';
      case ProjectCompletionReviewReason.milestoneEnded:
        return 'milestone_ended';
      case ProjectCompletionReviewReason.batchEnded:
        return 'batch_ended';
      case ProjectCompletionReviewReason.finalCriterionEvidence:
        return 'final_criterion_evidence';
    }
  }
}

/// @nodoc

extension ProjectCompletionReviewReasonMapperExtension
    on ProjectCompletionReviewReason {
  dynamic toValue() {
    ProjectCompletionReviewReasonMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectCompletionReviewReason>(this);
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
      case 'task_edit_approval':
        return ProjectBlockerType.taskEditApproval;
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
      case ProjectBlockerType.taskEditApproval:
        return 'task_edit_approval';
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
      PlanningMetricsMapper.ensureInitialized();
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
  static int _$completedBatchesWithoutCriterionProgress(ProjectDiagnostics v) =>
      v.completedBatchesWithoutCriterionProgress;
  static const Field<ProjectDiagnostics, int>
  _f$completedBatchesWithoutCriterionProgress = Field(
    'completedBatchesWithoutCriterionProgress',
    _$completedBatchesWithoutCriterionProgress,
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
  static int _$consecutiveNoProgressBatches(ProjectDiagnostics v) =>
      v.consecutiveNoProgressBatches;
  static const Field<ProjectDiagnostics, int> _f$consecutiveNoProgressBatches =
      Field(
        'consecutiveNoProgressBatches',
        _$consecutiveNoProgressBatches,
        opt: true,
        def: 0,
      );
  static PlanningMetrics _$planningMetrics(ProjectDiagnostics v) =>
      v.planningMetrics;
  static const Field<ProjectDiagnostics, PlanningMetrics> _f$planningMetrics =
      Field(
        'planningMetrics',
        _$planningMetrics,
        opt: true,
        def: const PlanningMetrics(),
        hook: OmitEmptyPlanningMetricsHook(),
      );
  static List<String> _$recentNoProgressBatchIds(ProjectDiagnostics v) =>
      v.recentNoProgressBatchIds;
  static const Field<ProjectDiagnostics, List<String>>
  _f$recentNoProgressBatchIds = Field(
    'recentNoProgressBatchIds',
    _$recentNoProgressBatchIds,
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
    #completedBatchesWithoutCriterionProgress:
        _f$completedBatchesWithoutCriterionProgress,
    #criterionReversals: _f$criterionReversals,
    #noReadyTaskBlocks: _f$noReadyTaskBlocks,
    #userApprovals: _f$userApprovals,
    #userQuestions: _f$userQuestions,
    #consecutiveNoProgressBatches: _f$consecutiveNoProgressBatches,
    #planningMetrics: _f$planningMetrics,
    #recentNoProgressBatchIds: _f$recentNoProgressBatchIds,
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
      completedBatchesWithoutCriterionProgress: data.dec(
        _f$completedBatchesWithoutCriterionProgress,
      ),
      criterionReversals: data.dec(_f$criterionReversals),
      noReadyTaskBlocks: data.dec(_f$noReadyTaskBlocks),
      userApprovals: data.dec(_f$userApprovals),
      userQuestions: data.dec(_f$userQuestions),
      consecutiveNoProgressBatches: data.dec(_f$consecutiveNoProgressBatches),
      planningMetrics: data.dec(_f$planningMetrics),
      recentNoProgressBatchIds: data.dec(_f$recentNoProgressBatchIds),
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
  static List<String> _$expectationIds(ProjectEvidence v) => v.expectationIds;
  static const Field<ProjectEvidence, List<String>> _f$expectationIds = Field(
    'expectationIds',
    _$expectationIds,
    opt: true,
    def: const [],
  );
  static String? _$taskId(ProjectEvidence v) => v.taskId;
  static const Field<ProjectEvidence, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );
  static String? _$runId(ProjectEvidence v) => v.runId;
  static const Field<ProjectEvidence, String> _f$runId = Field(
    'runId',
    _$runId,
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
    #expectationIds: _f$expectationIds,
    #taskId: _f$taskId,
    #runId: _f$runId,
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
      expectationIds: data.dec(_f$expectationIds),
      taskId: data.dec(_f$taskId),
      runId: data.dec(_f$runId),
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
class ProjectDesiredPlanMapper extends ClassMapperBase<ProjectDesiredPlan> {
  ProjectDesiredPlanMapper._();

  static ProjectDesiredPlanMapper? _instance;
  static ProjectDesiredPlanMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectDesiredPlanMapper._());
      ProjectPlanRevisionTriggerMapper.ensureInitialized();
      ProjectCriterionMapper.ensureInitialized();
      ProjectMilestoneMapper.ensureInitialized();
      TaskMapper.ensureInitialized();
      ProjectMemoryEntryMapper.ensureInitialized();
      ProjectMemorySupersessionMapper.ensureInitialized();
      PendingProjectQuestionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectDesiredPlan';

  static int _$revision(ProjectDesiredPlan v) => v.revision;
  static const Field<ProjectDesiredPlan, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static List<ProjectPlanRevisionTrigger> _$triggers(ProjectDesiredPlan v) =>
      v.triggers;
  static const Field<ProjectDesiredPlan, List<ProjectPlanRevisionTrigger>>
  _f$triggers = Field('triggers', _$triggers, opt: true, def: const []);
  static String _$summary(ProjectDesiredPlan v) => v.summary;
  static const Field<ProjectDesiredPlan, String> _f$summary = Field(
    'summary',
    _$summary,
  );
  static String _$rationale(ProjectDesiredPlan v) => v.rationale;
  static const Field<ProjectDesiredPlan, String> _f$rationale = Field(
    'rationale',
    _$rationale,
  );
  static bool _$hasCompleteCollections(ProjectDesiredPlan v) =>
      v.hasCompleteCollections;
  static const Field<ProjectDesiredPlan, bool> _f$hasCompleteCollections =
      Field(
        'hasCompleteCollections',
        _$hasCompleteCollections,
        opt: true,
        def: true,
      );
  static List<String> _$assumptions(ProjectDesiredPlan v) => v.assumptions;
  static const Field<ProjectDesiredPlan, List<String>> _f$assumptions = Field(
    'assumptions',
    _$assumptions,
    opt: true,
    def: const [],
  );
  static List<ProjectCriterion> _$criteria(ProjectDesiredPlan v) => v.criteria;
  static const Field<ProjectDesiredPlan, List<ProjectCriterion>> _f$criteria =
      Field('criteria', _$criteria, opt: true, def: const []);
  static List<ProjectMilestone> _$milestones(ProjectDesiredPlan v) =>
      v.milestones;
  static const Field<ProjectDesiredPlan, List<ProjectMilestone>> _f$milestones =
      Field('milestones', _$milestones, opt: true, def: const []);
  static List<Task> _$tasks(ProjectDesiredPlan v) => v.tasks;
  static const Field<ProjectDesiredPlan, List<Task>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
    def: const [],
  );
  static List<String> _$splitTaskIds(ProjectDesiredPlan v) => v.splitTaskIds;
  static const Field<ProjectDesiredPlan, List<String>> _f$splitTaskIds = Field(
    'splitTaskIds',
    _$splitTaskIds,
    opt: true,
    def: const [],
  );
  static List<String> _$deferredTaskIds(ProjectDesiredPlan v) =>
      v.deferredTaskIds;
  static const Field<ProjectDesiredPlan, List<String>> _f$deferredTaskIds =
      Field('deferredTaskIds', _$deferredTaskIds, opt: true, def: const []);
  static List<String> _$obsoleteTaskIds(ProjectDesiredPlan v) =>
      v.obsoleteTaskIds;
  static const Field<ProjectDesiredPlan, List<String>> _f$obsoleteTaskIds =
      Field('obsoleteTaskIds', _$obsoleteTaskIds, opt: true, def: const []);
  static List<ProjectMemoryEntry> _$memoryAdditions(ProjectDesiredPlan v) =>
      v.memoryAdditions;
  static const Field<ProjectDesiredPlan, List<ProjectMemoryEntry>>
  _f$memoryAdditions = Field(
    'memoryAdditions',
    _$memoryAdditions,
    opt: true,
    def: const [],
  );
  static List<ProjectMemorySupersession> _$memorySupersessions(
    ProjectDesiredPlan v,
  ) => v.memorySupersessions;
  static const Field<ProjectDesiredPlan, List<ProjectMemorySupersession>>
  _f$memorySupersessions = Field(
    'memorySupersessions',
    _$memorySupersessions,
    opt: true,
    def: const [],
  );
  static List<PendingProjectQuestion> _$openQuestions(ProjectDesiredPlan v) =>
      v.openQuestions;
  static const Field<ProjectDesiredPlan, List<PendingProjectQuestion>>
  _f$openQuestions = Field(
    'openQuestions',
    _$openQuestions,
    opt: true,
    def: const [],
  );
  static bool _$requiresApproval(ProjectDesiredPlan v) => v.requiresApproval;
  static const Field<ProjectDesiredPlan, bool> _f$requiresApproval = Field(
    'requiresApproval',
    _$requiresApproval,
    opt: true,
    def: false,
  );
  static String _$approvalReason(ProjectDesiredPlan v) => v.approvalReason;
  static const Field<ProjectDesiredPlan, String> _f$approvalReason = Field(
    'approvalReason',
    _$approvalReason,
    opt: true,
    def: '',
  );
  static DateTime _$createdAt(ProjectDesiredPlan v) => v.createdAt;
  static const Field<ProjectDesiredPlan, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );

  @override
  final MappableFields<ProjectDesiredPlan> fields = const {
    #revision: _f$revision,
    #triggers: _f$triggers,
    #summary: _f$summary,
    #rationale: _f$rationale,
    #hasCompleteCollections: _f$hasCompleteCollections,
    #assumptions: _f$assumptions,
    #criteria: _f$criteria,
    #milestones: _f$milestones,
    #tasks: _f$tasks,
    #splitTaskIds: _f$splitTaskIds,
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

  static ProjectDesiredPlan _instantiate(DecodingData data) {
    return ProjectDesiredPlan(
      revision: data.dec(_f$revision),
      triggers: data.dec(_f$triggers),
      summary: data.dec(_f$summary),
      rationale: data.dec(_f$rationale),
      hasCompleteCollections: data.dec(_f$hasCompleteCollections),
      assumptions: data.dec(_f$assumptions),
      criteria: data.dec(_f$criteria),
      milestones: data.dec(_f$milestones),
      tasks: data.dec(_f$tasks),
      splitTaskIds: data.dec(_f$splitTaskIds),
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

  static ProjectDesiredPlan fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectDesiredPlan>(map);
  }

  static ProjectDesiredPlan fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectDesiredPlan>(json);
  }
}

/// @nodoc
mixin ProjectDesiredPlanMappable {
  String toJson() {
    return ProjectDesiredPlanMapper.ensureInitialized()
        .encodeJson<ProjectDesiredPlan>(this as ProjectDesiredPlan);
  }

  Map<String, dynamic> toMap() {
    return ProjectDesiredPlanMapper.ensureInitialized()
        .encodeMap<ProjectDesiredPlan>(this as ProjectDesiredPlan);
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
      ProjectDesiredPlanMapper.ensureInitialized();
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
  static List<String> _$highRiskReasonCodes(PendingProjectPlanApproval v) =>
      v.highRiskReasonCodes;
  static const Field<PendingProjectPlanApproval, List<String>>
  _f$highRiskReasonCodes = Field(
    'highRiskReasonCodes',
    _$highRiskReasonCodes,
    opt: true,
    def: const [],
  );
  static DateTime _$createdAt(PendingProjectPlanApproval v) => v.createdAt;
  static const Field<PendingProjectPlanApproval, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static ProjectDesiredPlan? _$desiredPlan(PendingProjectPlanApproval v) =>
      v.desiredPlan;
  static const Field<PendingProjectPlanApproval, ProjectDesiredPlan>
  _f$desiredPlan = Field('desiredPlan', _$desiredPlan, opt: true);

  @override
  final MappableFields<PendingProjectPlanApproval> fields = const {
    #revision: _f$revision,
    #reason: _f$reason,
    #summary: _f$summary,
    #highRiskChanges: _f$highRiskChanges,
    #highRiskReasonCodes: _f$highRiskReasonCodes,
    #createdAt: _f$createdAt,
    #desiredPlan: _f$desiredPlan,
  };
  @override
  final bool ignoreNull = true;

  static PendingProjectPlanApproval _instantiate(DecodingData data) {
    return PendingProjectPlanApproval(
      revision: data.dec(_f$revision),
      reason: data.dec(_f$reason),
      summary: data.dec(_f$summary),
      highRiskChanges: data.dec(_f$highRiskChanges),
      highRiskReasonCodes: data.dec(_f$highRiskReasonCodes),
      createdAt: data.dec(_f$createdAt),
      desiredPlan: data.dec(_f$desiredPlan),
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
class ProjectCompletionReviewCheckpointMapper
    extends ClassMapperBase<ProjectCompletionReviewCheckpoint> {
  ProjectCompletionReviewCheckpointMapper._();

  static ProjectCompletionReviewCheckpointMapper? _instance;
  static ProjectCompletionReviewCheckpointMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProjectCompletionReviewCheckpointMapper._(),
      );
      ProjectCompletionReviewReasonMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectCompletionReviewCheckpoint';

  static ProjectCompletionReviewReason _$reason(
    ProjectCompletionReviewCheckpoint v,
  ) => v.reason;
  static const Field<
    ProjectCompletionReviewCheckpoint,
    ProjectCompletionReviewReason
  >
  _f$reason = Field('reason', _$reason);
  static String _$evidenceFingerprint(ProjectCompletionReviewCheckpoint v) =>
      v.evidenceFingerprint;
  static const Field<ProjectCompletionReviewCheckpoint, String>
  _f$evidenceFingerprint = Field(
    'evidenceFingerprint',
    _$evidenceFingerprint,
    hook: JsonStringHook(),
  );
  static String? _$milestoneId(ProjectCompletionReviewCheckpoint v) =>
      v.milestoneId;
  static const Field<ProjectCompletionReviewCheckpoint, String> _f$milestoneId =
      Field(
        'milestoneId',
        _$milestoneId,
        opt: true,
        hook: JsonNullableStringHook(),
      );
  static DateTime _$reviewedAt(ProjectCompletionReviewCheckpoint v) =>
      v.reviewedAt;
  static const Field<ProjectCompletionReviewCheckpoint, DateTime>
  _f$reviewedAt = Field('reviewedAt', _$reviewedAt, hook: JsonDateHook());

  @override
  final MappableFields<ProjectCompletionReviewCheckpoint> fields = const {
    #reason: _f$reason,
    #evidenceFingerprint: _f$evidenceFingerprint,
    #milestoneId: _f$milestoneId,
    #reviewedAt: _f$reviewedAt,
  };
  @override
  final bool ignoreNull = true;

  static ProjectCompletionReviewCheckpoint _instantiate(DecodingData data) {
    return ProjectCompletionReviewCheckpoint(
      reason: data.dec(_f$reason),
      evidenceFingerprint: data.dec(_f$evidenceFingerprint),
      milestoneId: data.dec(_f$milestoneId),
      reviewedAt: data.dec(_f$reviewedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectCompletionReviewCheckpoint fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectCompletionReviewCheckpoint>(
      map,
    );
  }

  static ProjectCompletionReviewCheckpoint fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectCompletionReviewCheckpoint>(
      json,
    );
  }
}

/// @nodoc
mixin ProjectCompletionReviewCheckpointMappable {
  String toJson() {
    return ProjectCompletionReviewCheckpointMapper.ensureInitialized()
        .encodeJson<ProjectCompletionReviewCheckpoint>(
          this as ProjectCompletionReviewCheckpoint,
        );
  }

  Map<String, dynamic> toMap() {
    return ProjectCompletionReviewCheckpointMapper.ensureInitialized()
        .encodeMap<ProjectCompletionReviewCheckpoint>(
          this as ProjectCompletionReviewCheckpoint,
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
      TaskMapper.ensureInitialized();
      TaskArtifactMapper.ensureInitialized();
      ProjectRecoveryIncidentMapper.ensureInitialized();
      ProjectEvidenceMapper.ensureInitialized();
      ProjectMilestoneMapper.ensureInitialized();
      ProjectMemoryEntryMapper.ensureInitialized();
      ProjectPlanRevisionMapper.ensureInitialized();
      PendingProjectPlanApprovalMapper.ensureInitialized();
      ProjectPlanRevisionTriggerMapper.ensureInitialized();
      ProjectCompletionReviewCheckpointMapper.ensureInitialized();
      PendingProjectQuestionMapper.ensureInitialized();
      ProjectStatusMapper.ensureInitialized();
      ProjectBlockerMapper.ensureInitialized();
      ProjectDecisionRecordMapper.ensureInitialized();
      ProjectDiagnosticsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectState';

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
    hook: JsonStringHook(),
  );
  static String _$refinedGoal(ProjectState v) => v.refinedGoal;
  static const Field<ProjectState, String> _f$refinedGoal = Field(
    'refinedGoal',
    _$refinedGoal,
    hook: JsonStringHook(),
  );
  static List<ProjectCriterion> _$criteria(ProjectState v) => v.criteria;
  static const Field<ProjectState, List<ProjectCriterion>> _f$criteria = Field(
    'criteria',
    _$criteria,
    hook: JsonObjectListHook(),
  );
  static List<String> _$constraints(ProjectState v) => v.constraints;
  static const Field<ProjectState, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    hook: JsonStringListHook(),
  );
  static List<Task> _$tasks(ProjectState v) => v.tasks;
  static const Field<ProjectState, List<Task>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
    hook: JsonObjectListHook(),
  );
  static List<String> _$taskIds(ProjectState v) => v.taskIds;
  static const Field<ProjectState, List<String>> _f$taskIds = Field(
    'taskIds',
    _$taskIds,
    opt: true,
    hook: JsonStringListHook(),
  );
  static List<String> _$currentBatchTaskIds(ProjectState v) =>
      v.currentBatchTaskIds;
  static const Field<ProjectState, List<String>> _f$currentBatchTaskIds = Field(
    'currentBatchTaskIds',
    _$currentBatchTaskIds,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static int _$currentBatchIndex(ProjectState v) => v.currentBatchIndex;
  static const Field<ProjectState, int> _f$currentBatchIndex = Field(
    'currentBatchIndex',
    _$currentBatchIndex,
    opt: true,
    def: 0,
    hook: JsonIntHook(min: 0),
  );
  static int _$currentBatchPlanRevision(ProjectState v) =>
      v.currentBatchPlanRevision;
  static const Field<ProjectState, int> _f$currentBatchPlanRevision = Field(
    'currentBatchPlanRevision',
    _$currentBatchPlanRevision,
    opt: true,
    def: 0,
    hook: JsonIntHook(min: 0),
  );
  static bool _$currentBatchProgressObserved(ProjectState v) =>
      v.currentBatchProgressObserved;
  static const Field<ProjectState, bool> _f$currentBatchProgressObserved =
      Field(
        'currentBatchProgressObserved',
        _$currentBatchProgressObserved,
        opt: true,
        def: false,
        hook: JsonBoolHook(),
      );
  static String? _$pendingReplanReason(ProjectState v) => v.pendingReplanReason;
  static const Field<ProjectState, String> _f$pendingReplanReason = Field(
    'pendingReplanReason',
    _$pendingReplanReason,
    opt: true,
    hook: JsonNullableStringHook(),
  );
  static List<TaskArtifact> _$artifacts(ProjectState v) => v.artifacts;
  static const Field<ProjectState, List<TaskArtifact>> _f$artifacts = Field(
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
  static ProjectCompletionReviewCheckpoint? _$completionReviewCheckpoint(
    ProjectState v,
  ) => v.completionReviewCheckpoint;
  static const Field<ProjectState, ProjectCompletionReviewCheckpoint>
  _f$completionReviewCheckpoint = Field(
    'completionReviewCheckpoint',
    _$completionReviewCheckpoint,
    opt: true,
  );
  static List<PendingProjectQuestion> _$openQuestions(ProjectState v) =>
      v.openQuestions;
  static const Field<ProjectState, List<PendingProjectQuestion>>
  _f$openQuestions = Field(
    'openQuestions',
    _$openQuestions,
    opt: true,
    def: const [],
    hook: JsonObjectListHook(),
  );
  static ProjectStatus _$status(ProjectState v) => v.status;
  static const Field<ProjectState, ProjectStatus> _f$status = Field(
    'status',
    _$status,
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
    #id: _f$id,
    #title: _f$title,
    #originalGoal: _f$originalGoal,
    #refinedGoal: _f$refinedGoal,
    #criteria: _f$criteria,
    #constraints: _f$constraints,
    #tasks: _f$tasks,
    #taskIds: _f$taskIds,
    #currentBatchTaskIds: _f$currentBatchTaskIds,
    #currentBatchIndex: _f$currentBatchIndex,
    #currentBatchPlanRevision: _f$currentBatchPlanRevision,
    #currentBatchProgressObserved: _f$currentBatchProgressObserved,
    #pendingReplanReason: _f$pendingReplanReason,
    #artifacts: _f$artifacts,
    #recoveryIncidents: _f$recoveryIncidents,
    #evidence: _f$evidence,
    #milestones: _f$milestones,
    #memory: _f$memory,
    #planHistory: _f$planHistory,
    #pendingPlanApproval: _f$pendingPlanApproval,
    #pendingReplanTriggers: _f$pendingReplanTriggers,
    #completionReviewCheckpoint: _f$completionReviewCheckpoint,
    #openQuestions: _f$openQuestions,
    #status: _f$status,
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
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      originalGoal: data.dec(_f$originalGoal),
      refinedGoal: data.dec(_f$refinedGoal),
      criteria: data.dec(_f$criteria),
      constraints: data.dec(_f$constraints),
      tasks: data.dec(_f$tasks),
      taskIds: data.dec(_f$taskIds),
      currentBatchTaskIds: data.dec(_f$currentBatchTaskIds),
      currentBatchIndex: data.dec(_f$currentBatchIndex),
      currentBatchPlanRevision: data.dec(_f$currentBatchPlanRevision),
      currentBatchProgressObserved: data.dec(_f$currentBatchProgressObserved),
      pendingReplanReason: data.dec(_f$pendingReplanReason),
      artifacts: data.dec(_f$artifacts),
      recoveryIncidents: data.dec(_f$recoveryIncidents),
      evidence: data.dec(_f$evidence),
      milestones: data.dec(_f$milestones),
      memory: data.dec(_f$memory),
      planHistory: data.dec(_f$planHistory),
      pendingPlanApproval: data.dec(_f$pendingPlanApproval),
      pendingReplanTriggers: data.dec(_f$pendingReplanTriggers),
      completionReviewCheckpoint: data.dec(_f$completionReviewCheckpoint),
      openQuestions: data.dec(_f$openQuestions),
      status: data.dec(_f$status),
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
  _f$status = Field('status', _$status);
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
      Field('decision', _$decision);
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

