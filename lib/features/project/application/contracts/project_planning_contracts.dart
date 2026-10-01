import 'package:dart_mappable/dart_mappable.dart';

part 'project_planning_contracts.mapper.dart';

/// Shared policy value used by project planning and task execution settings.
/// It is a contract value, not an orchestration dependency.
@MappableEnum(defaultValue: ProjectPlanApprovalPolicy.highRiskOnly)
enum ProjectPlanApprovalPolicy {
  never,
  highRiskOnly,
  everyRevision;

  String get wire => name;

  String get label => switch (this) {
    ProjectPlanApprovalPolicy.never => 'Never (autonomous)',
    ProjectPlanApprovalPolicy.highRiskOnly => 'High risk only',
    ProjectPlanApprovalPolicy.everyRevision => 'Every revision',
  };

  static ProjectPlanApprovalPolicy parse(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    return switch (raw) {
      'never' => ProjectPlanApprovalPolicy.never,
      'everyrevision' ||
      'every_revision' => ProjectPlanApprovalPolicy.everyRevision,
      _ => ProjectPlanApprovalPolicy.highRiskOnly,
    };
  }
}
