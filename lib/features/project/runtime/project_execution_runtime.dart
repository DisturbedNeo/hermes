library;

import 'package:hermes/features/project/runtime/project_execution_state_machine.dart';

export 'project_execution_state_machine.dart'
    show
        ProjectRuntimeDependencies,
        ProjectExecutionOperations,
        ProjectExecutionCore;

/// Stable compatibility name for the project execution facade.
///
/// The state-machine implementation composes the planning, recovery,
/// evidence/completion, command, and persistence capabilities.
typedef ProjectExecutionRuntime = ProjectExecutionStateMachine;
