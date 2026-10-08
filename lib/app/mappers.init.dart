// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../core/contracts/acceptance.dart' as p0;
import '../features/chat/application/contracts/system_prompt.dart' as p1;
import '../features/chat/application/protocol/context_summary_prompt.dart'
    as p2;
import '../features/model/application/model_configuration.dart' as p3;
import '../features/model/application/model_load_configuration.dart' as p4;
import '../features/persistence/infrastructure/dto/project_state_models.dart'
    as p5;
import '../features/persistence/infrastructure/dto/task_state_models.dart'
    as p6;
import '../features/project/application/contracts/project_task_models.dart'
    as p7;
import '../features/project/application/contracts/project_workspace_graph.dart'
    as p8;
import '../features/task/application/contracts/planning_metrics.dart' as p9;
import '../features/task/application/contracts/question_policy_service.dart'
    as p10;
import '../features/task/application/contracts/task_execution_contracts.dart'
    as p11;
import '../features/task/application/contracts/task_planning_models.dart'
    as p12;
import '../features/task/application/contracts/task_planning_types.dart' as p13;
import '../features/task/application/contracts/task_tool_contracts.dart' as p14;
import '../features/workspace/application/workspace_discovery_profile.dart'
    as p15;
import '../platform/tools/calculator_tool.dart' as p16;

/// @nodoc
void initializeMappers() {
  p0.AcceptanceVerifierMapper.ensureInitialized();
  p0.AcceptanceItemMapper.ensureInitialized();
  p0.AcceptanceVerifierKindMapper.ensureInitialized();
  p1.PromptModuleMapper.ensureInitialized();
  p1.PromptPresetMapper.ensureInitialized();
  p1.SystemPromptSnapshotMapper.ensureInitialized();
  p2.ContextSummaryMapper.ensureInitialized();
  p3.ModelConfigurationSnapshotMapper.ensureInitialized();
  p4.ModelLoadConfigurationMapper.ensureInitialized();
  p5.ProjectDiagnosticsMapper.ensureInitialized();
  p5.ProjectCriterionMapper.ensureInitialized();
  p5.ProjectEvidenceMapper.ensureInitialized();
  p5.ProjectMilestoneMapper.ensureInitialized();
  p5.ProjectMemoryEntryMapper.ensureInitialized();
  p5.ProjectMemorySupersessionMapper.ensureInitialized();
  p5.ProjectDesiredPlanMapper.ensureInitialized();
  p5.ProjectPlanRevisionMapper.ensureInitialized();
  p5.PendingProjectPlanApprovalMapper.ensureInitialized();
  p5.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
  p5.ProjectBoundaryMapper.ensureInitialized();
  p5.ProjectSnapshotAggregateMapper.ensureInitialized();
  p5.ProjectRecoveryIncidentMapper.ensureInitialized();
  p5.ProjectDecisionRecordMapper.ensureInitialized();
  p5.ProjectBlockerMapper.ensureInitialized();
  p5.PendingProjectQuestionMapper.ensureInitialized();
  p5.ProjectStatusMapper.ensureInitialized();
  p5.ProjectCriterionStatusMapper.ensureInitialized();
  p5.ProjectVerificationModeMapper.ensureInitialized();
  p5.ProjectEvidenceStatusMapper.ensureInitialized();
  p5.ProjectEvidenceStrengthMapper.ensureInitialized();
  p5.ProjectMilestoneStatusMapper.ensureInitialized();
  p5.TaskReadinessMapper.ensureInitialized();
  p5.ProjectMemoryKindMapper.ensureInitialized();
  p5.ProjectMemorySourceTypeMapper.ensureInitialized();
  p5.ProjectMemoryConfidenceMapper.ensureInitialized();
  p5.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p5.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p5.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p5.ProjectBlockerTypeMapper.ensureInitialized();
  p5.ProjectDecisionTypeMapper.ensureInitialized();
  p5.ProjectControlOutcomeMapper.ensureInitialized();
  p5.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p6.TaskProjectCriterionMapper.ensureInitialized();
  p6.RefinedTaskBriefMapper.ensureInitialized();
  p6.TaskSnapshotAggregateMapper.ensureInitialized();
  p6.TaskStepMapper.ensureInitialized();
  p6.TaskRunMapper.ensureInitialized();
  p6.TaskToolCallRecordMapper.ensureInitialized();
  p6.PendingTaskApprovalMapper.ensureInitialized();
  p6.PendingTaskQuestionMapper.ensureInitialized();
  p6.TaskStepStatusMapper.ensureInitialized();
  p6.TaskRunStatusMapper.ensureInitialized();
  p6.TaskToolCallOutcomeMapper.ensureInitialized();
  p7.ProjectTaskNodeMapper.ensureInitialized();
  p8.ProjectWorkspaceNodeMapper.ensureInitialized();
  p8.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p8.ProjectWorkspaceGraphMapper.ensureInitialized();
  p8.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p8.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p9.PlanningMetricsMapper.ensureInitialized();
  p10.AgentQuestionMapper.ensureInitialized();
  p10.QuestionKindMapper.ensureInitialized();
  p11.TaskGateMapper.ensureInitialized();
  p11.TaskArtifactMapper.ensureInitialized();
  p11.TaskGateResultMapper.ensureInitialized();
  p11.TaskFailureMapper.ensureInitialized();
  p11.TaskEvidenceClaimMapper.ensureInitialized();
  p11.TaskGateStatusMapper.ensureInitialized();
  p11.TaskGateFailureDispositionMapper.ensureInitialized();
  p11.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p11.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p12.TaskPlanningContextMapper.ensureInitialized();
  p12.WorkspaceMetadataMapper.ensureInitialized();
  p13.TaskStatusMapper.ensureInitialized();
  p13.TaskPriorityMapper.ensureInitialized();
  p13.TaskRiskMapper.ensureInitialized();
  p13.ProjectRiskReductionMapper.ensureInitialized();
  p13.TaskEffortMapper.ensureInitialized();
  p13.ProjectEvidenceTypeMapper.ensureInitialized();
  p14.TaskToolErrorMapper.ensureInitialized();
  p14.TaskToolErrorDispositionMapper.ensureInitialized();
  p15.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p15.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p15.WorkspaceFileExcerptMapper.ensureInitialized();
  p16.CalculatorOperationMapper.ensureInitialized();
}

