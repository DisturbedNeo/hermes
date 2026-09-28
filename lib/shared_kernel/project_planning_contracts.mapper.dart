// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project_planning_contracts.dart';

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

