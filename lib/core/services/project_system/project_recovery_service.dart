import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_service.dart';

/// Recovery boundary for interrupted aggregate execution.
class ProjectRecoveryService {
  final ProjectRecoveryDelegate _recover;

  const ProjectRecoveryService({required ProjectRecoveryDelegate recover})
    : _recover = recover;

  Future<ProjectRunResult> recover(ProjectRecoveryRequest request) =>
      _recover(request);
}
