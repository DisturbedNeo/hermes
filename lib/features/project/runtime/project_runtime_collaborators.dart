/// Dependency/wiring exports for the project runtime composition root.
///
/// Runtime behavior lives in the focused project services and the private
/// execution runtime in `project_execution_runtime.dart`; this file is
/// intentionally not an implementation unit.
library;

export 'project_execution_runtime.dart'
    show ProjectRuntimeDependencies, ProjectExecutionRuntime;
