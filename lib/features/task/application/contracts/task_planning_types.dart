import 'package:dart_mappable/dart_mappable.dart';

part 'task_planning_types.mapper.dart';

@MappableEnum(defaultValue: TaskStatus.paused)
enum TaskStatus {
  draft,
  queued,
  planned,
  running,
  paused,
  blocked,
  completed,
  failed,
  rejected,
  split,
  deferred,
  obsolete,
  cancelled,
}

@MappableEnum(defaultValue: TaskPriority.normal)
enum TaskPriority { critical, high, normal, low }

@MappableEnum(defaultValue: TaskRisk.unknown)
enum TaskRisk { high, medium, low, unknown }

@MappableEnum(defaultValue: ProjectRiskReduction.none)
enum ProjectRiskReduction { high, medium, low, none }

@MappableEnum(defaultValue: TaskEffort.small)
enum TaskEffort { small, medium, large }

@MappableEnum(defaultValue: ProjectEvidenceType.taskClaim)
enum ProjectEvidenceType {
  gate,
  artifact,
  command,
  @MappableValue('task_claim')
  taskClaim,
  @MappableValue('user_approval')
  userApproval,
}

extension TaskStatusWire on TaskStatus {
  String get wire => name;
}
