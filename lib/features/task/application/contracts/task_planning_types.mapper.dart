// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'task_planning_types.dart';

/// @nodoc

class TaskStatusMapper extends EnumMapper<TaskStatus> {
  TaskStatusMapper._();

  static TaskStatusMapper? _instance;
  static TaskStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskStatusMapper._());
    }
    return _instance!;
  }

  static TaskStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskStatus decode(dynamic value) {
    switch (value) {
      case r'draft':
        return TaskStatus.draft;
      case r'queued':
        return TaskStatus.queued;
      case r'planned':
        return TaskStatus.planned;
      case r'running':
        return TaskStatus.running;
      case r'paused':
        return TaskStatus.paused;
      case r'blocked':
        return TaskStatus.blocked;
      case r'completed':
        return TaskStatus.completed;
      case r'failed':
        return TaskStatus.failed;
      case r'rejected':
        return TaskStatus.rejected;
      case r'split':
        return TaskStatus.split;
      case r'deferred':
        return TaskStatus.deferred;
      case r'obsolete':
        return TaskStatus.obsolete;
      case r'cancelled':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.values[4];
    }
  }

  @override
  dynamic encode(TaskStatus self) {
    switch (self) {
      case TaskStatus.draft:
        return r'draft';
      case TaskStatus.queued:
        return r'queued';
      case TaskStatus.planned:
        return r'planned';
      case TaskStatus.running:
        return r'running';
      case TaskStatus.paused:
        return r'paused';
      case TaskStatus.blocked:
        return r'blocked';
      case TaskStatus.completed:
        return r'completed';
      case TaskStatus.failed:
        return r'failed';
      case TaskStatus.rejected:
        return r'rejected';
      case TaskStatus.split:
        return r'split';
      case TaskStatus.deferred:
        return r'deferred';
      case TaskStatus.obsolete:
        return r'obsolete';
      case TaskStatus.cancelled:
        return r'cancelled';
    }
  }
}

/// @nodoc

extension TaskStatusMapperExtension on TaskStatus {
  String toValue() {
    TaskStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskStatus>(this) as String;
  }
}

/// @nodoc

class TaskPriorityMapper extends EnumMapper<TaskPriority> {
  TaskPriorityMapper._();

  static TaskPriorityMapper? _instance;
  static TaskPriorityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskPriorityMapper._());
    }
    return _instance!;
  }

  static TaskPriority fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskPriority decode(dynamic value) {
    switch (value) {
      case r'critical':
        return TaskPriority.critical;
      case r'high':
        return TaskPriority.high;
      case r'normal':
        return TaskPriority.normal;
      case r'low':
        return TaskPriority.low;
      default:
        return TaskPriority.values[2];
    }
  }

  @override
  dynamic encode(TaskPriority self) {
    switch (self) {
      case TaskPriority.critical:
        return r'critical';
      case TaskPriority.high:
        return r'high';
      case TaskPriority.normal:
        return r'normal';
      case TaskPriority.low:
        return r'low';
    }
  }
}

/// @nodoc

extension TaskPriorityMapperExtension on TaskPriority {
  String toValue() {
    TaskPriorityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskPriority>(this) as String;
  }
}

/// @nodoc

class TaskRiskMapper extends EnumMapper<TaskRisk> {
  TaskRiskMapper._();

  static TaskRiskMapper? _instance;
  static TaskRiskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskRiskMapper._());
    }
    return _instance!;
  }

  static TaskRisk fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskRisk decode(dynamic value) {
    switch (value) {
      case r'high':
        return TaskRisk.high;
      case r'medium':
        return TaskRisk.medium;
      case r'low':
        return TaskRisk.low;
      case r'unknown':
        return TaskRisk.unknown;
      default:
        return TaskRisk.values[3];
    }
  }

  @override
  dynamic encode(TaskRisk self) {
    switch (self) {
      case TaskRisk.high:
        return r'high';
      case TaskRisk.medium:
        return r'medium';
      case TaskRisk.low:
        return r'low';
      case TaskRisk.unknown:
        return r'unknown';
    }
  }
}

/// @nodoc

extension TaskRiskMapperExtension on TaskRisk {
  String toValue() {
    TaskRiskMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskRisk>(this) as String;
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

class TaskEffortMapper extends EnumMapper<TaskEffort> {
  TaskEffortMapper._();

  static TaskEffortMapper? _instance;
  static TaskEffortMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskEffortMapper._());
    }
    return _instance!;
  }

  static TaskEffort fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskEffort decode(dynamic value) {
    switch (value) {
      case r'small':
        return TaskEffort.small;
      case r'medium':
        return TaskEffort.medium;
      case r'large':
        return TaskEffort.large;
      default:
        return TaskEffort.values[0];
    }
  }

  @override
  dynamic encode(TaskEffort self) {
    switch (self) {
      case TaskEffort.small:
        return r'small';
      case TaskEffort.medium:
        return r'medium';
      case TaskEffort.large:
        return r'large';
    }
  }
}

/// @nodoc

extension TaskEffortMapperExtension on TaskEffort {
  String toValue() {
    TaskEffortMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskEffort>(this) as String;
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
