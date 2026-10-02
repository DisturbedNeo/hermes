/// Domain-owned project aggregate and value-object surface.
///
/// This is the stable domain import used by project policies and persistence
/// adapters. The application contract file remains a compatibility export
/// until the generated snapshot DTOs are fully isolated in infrastructure.
library;

export 'package:hermes/features/project/application/contracts/project_task_models.dart';
export 'package:hermes/features/project/application/contracts/project_workspace_graph.dart';
export 'package:hermes/features/task/application/contracts/task_planning_types.dart';
export 'package:hermes/features/task/application/contracts/task_execution_contracts.dart';
export 'package:hermes/core/contracts/execution_settings.dart'
    show ProjectPlanApprovalPolicy;
export 'package:hermes/features/project/application/contracts/project_snapshot_models.dart'
    show
        PendingProjectPlanApproval,
        PendingProjectQuestion,
        ProjectAggregate,
        ProjectBlocker,
        ProjectBlockerType,
        ProjectBlockerTypeWire,
        ProjectBoundary,
        ProjectCompletionReviewCheckpoint,
        ProjectCompletionReviewReason,
        ProjectControlOutcome,
        ProjectControlOutcomeWire,
        ProjectCriterion,
        ProjectCriterionStatus,
        ProjectDecisionRecord,
        ProjectDecisionType,
        ProjectDesiredPlan,
        ProjectDiagnostics,
        ProjectEvidence,
        ProjectEvidenceStatus,
        ProjectEvidenceStrength,
        ProjectEvaluation,
        ProjectExecutionState,
        ProjectMemoryConfidence,
        ProjectMemoryEntry,
        ProjectMemoryKind,
        ProjectMemorySourceType,
        ProjectMemorySupersession,
        ProjectMilestone,
        ProjectMilestoneStatus,
        ProjectPlanRevision,
        ProjectPlanRevisionApprover,
        ProjectPlanRevisionTrigger,
        ProjectPlanState,
        ProjectRecoveryIncident,
        ProjectRecoveryIncidentStatus,
        ProjectStatus,
        ProjectStatusWire,
        ProjectSummary,
        TaskResult,
        ProjectVerificationMode,
        TaskReadiness;

export 'package:hermes/features/project/application/contracts/project_snapshot_models.dart'
    show projectTaskFingerprint;
