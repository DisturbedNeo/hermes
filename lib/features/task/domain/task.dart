/// Domain-owned task state surface.
///
/// The application contract export remains as a compatibility bridge for
/// existing callers while persistence DTO extraction proceeds. Domain
/// policies import this module, so task lifecycle ownership is not coupled to
/// a persistence adapter or to chat.
library;

export 'package:hermes/features/task/application/contracts/task_planning_types.dart';
export 'package:hermes/features/task/application/contracts/task_execution_contracts.dart';
export 'package:hermes/features/project/application/contracts/project_task_models.dart';
export 'package:hermes/features/task/application/contracts/task_snapshot_models.dart'
    show
        ExecutionMode,
        ExecutionModeWire,
        PendingTaskApproval,
        PendingTaskQuestion,
        RefinedTaskBrief,
        Task,
        TaskAggregate,
        TaskProjectCriterion,
        TaskProjectEvidenceExpectation,
        TaskRun,
        TaskRunStatus,
        TaskRunStatusWire,
        TaskStatus,
        TaskStep,
        TaskStepStatus,
        TaskStepStatusWire,
        TaskToolCallRecord,
        TaskToolCallOutcome,
        TaskToolCallOutcomeWire;
