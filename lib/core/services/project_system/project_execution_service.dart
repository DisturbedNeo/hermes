import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_service.dart';

/// Project execution boundary. The delegate is supplied by the orchestrator,
/// which keeps model calls outside the persistence coordinator.
class ProjectExecutionService {
  final ProjectRunDelegate _run;

  const ProjectExecutionService({required ProjectRunDelegate run}) : _run = run;

  Future<ProjectRunResult> execute(ProjectExecutionRequest request) =>
      _run(request);
}
