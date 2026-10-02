// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../features/chat/application/contracts/system_prompt.dart' as p0;
import '../features/chat/application/protocol/context_summary_prompt.dart'
    as p1;
import '../features/model/application/model_configuration.dart' as p2;
import '../features/model/application/model_load_configuration.dart' as p3;
import '../features/project/application/contracts/project_snapshot_models.dart'
    as p4;
import '../features/project/application/contracts/project_task_models.dart'
    as p5;
import '../features/project/application/contracts/project_workspace_graph.dart'
    as p6;
import '../features/task/application/contracts/planning_metrics.dart' as p7;
import '../features/task/application/contracts/question_policy_service.dart'
    as p8;
import '../features/task/application/contracts/task_execution_contracts.dart'
    as p9;
import '../features/task/application/contracts/task_planning_models.dart'
    as p10;
import '../features/task/application/contracts/task_planning_types.dart' as p11;
import '../features/task/application/contracts/task_snapshot_models.dart'
    as p12;
import '../features/task/application/contracts/task_tool_contracts.dart' as p13;
import '../features/workspace/application/workspace_discovery_profile.dart'
    as p14;
import '../platform/tools/calculator_tool.dart' as p15;

/// @nodoc
void initializeMappers() {
  p0.PromptModuleMapper.ensureInitialized();
  p0.PromptPresetMapper.ensureInitialized();
  p0.SystemPromptSnapshotMapper.ensureInitialized();
  p1.ContextSummaryMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ModelLoadConfigurationMapper.ensureInitialized();
  p4.ProjectDiagnosticsMapper.ensureInitialized();
  p4.ProjectCriterionMapper.ensureInitialized();
  p4.ProjectEvidenceMapper.ensureInitialized();
  p4.ProjectMilestoneMapper.ensureInitialized();
  p4.ProjectMemoryEntryMapper.ensureInitialized();
  p4.ProjectMemorySupersessionMapper.ensureInitialized();
  p4.ProjectDesiredPlanMapper.ensureInitialized();
  p4.ProjectPlanRevisionMapper.ensureInitialized();
  p4.PendingProjectPlanApprovalMapper.ensureInitialized();
  p4.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
  p4.ProjectBoundaryMapper.ensureInitialized();
  p4.ProjectAggregateMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentMapper.ensureInitialized();
  p4.ProjectDecisionRecordMapper.ensureInitialized();
  p4.ProjectBlockerMapper.ensureInitialized();
  p4.PendingProjectQuestionMapper.ensureInitialized();
  p4.ProjectStatusMapper.ensureInitialized();
  p4.ProjectCriterionStatusMapper.ensureInitialized();
  p4.ProjectVerificationModeMapper.ensureInitialized();
  p4.ProjectEvidenceStatusMapper.ensureInitialized();
  p4.ProjectEvidenceStrengthMapper.ensureInitialized();
  p4.ProjectMilestoneStatusMapper.ensureInitialized();
  p4.TaskReadinessMapper.ensureInitialized();
  p4.ProjectMemoryKindMapper.ensureInitialized();
  p4.ProjectMemorySourceTypeMapper.ensureInitialized();
  p4.ProjectMemoryConfidenceMapper.ensureInitialized();
  p4.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p4.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p4.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p4.ProjectBlockerTypeMapper.ensureInitialized();
  p4.ProjectDecisionTypeMapper.ensureInitialized();
  p4.ProjectControlOutcomeMapper.ensureInitialized();
  p4.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p5.ProjectTaskNodeMapper.ensureInitialized();
  p6.ProjectWorkspaceNodeMapper.ensureInitialized();
  p6.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p6.ProjectWorkspaceGraphMapper.ensureInitialized();
  p6.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p6.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p7.PlanningMetricsMapper.ensureInitialized();
  p8.AgentQuestionMapper.ensureInitialized();
  p8.QuestionKindMapper.ensureInitialized();
  p9.TaskGateMapper.ensureInitialized();
  p9.TaskEvidenceExpectationMapper.ensureInitialized();
  p9.TaskArtifactMapper.ensureInitialized();
  p9.TaskGateResultMapper.ensureInitialized();
  p9.TaskFailureMapper.ensureInitialized();
  p9.TaskEvidenceClaimMapper.ensureInitialized();
  p9.TaskGateStatusMapper.ensureInitialized();
  p9.TaskGateFailureDispositionMapper.ensureInitialized();
  p9.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p9.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p10.TaskPlanningContextMapper.ensureInitialized();
  p10.WorkspaceMetadataMapper.ensureInitialized();
  p11.TaskStatusMapper.ensureInitialized();
  p11.TaskPriorityMapper.ensureInitialized();
  p11.TaskRiskMapper.ensureInitialized();
  p11.ProjectRiskReductionMapper.ensureInitialized();
  p11.TaskEffortMapper.ensureInitialized();
  p11.ProjectEvidenceTypeMapper.ensureInitialized();
  p12.TaskProjectCriterionMapper.ensureInitialized();
  p12.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p12.RefinedTaskBriefMapper.ensureInitialized();
  p12.TaskAggregateMapper.ensureInitialized();
  p12.TaskStepMapper.ensureInitialized();
  p12.TaskRunMapper.ensureInitialized();
  p12.TaskToolCallRecordMapper.ensureInitialized();
  p12.PendingTaskApprovalMapper.ensureInitialized();
  p12.PendingTaskQuestionMapper.ensureInitialized();
  p12.TaskStepStatusMapper.ensureInitialized();
  p12.TaskRunStatusMapper.ensureInitialized();
  p12.TaskToolCallOutcomeMapper.ensureInitialized();
  p13.TaskToolErrorMapper.ensureInitialized();
  p13.TaskToolErrorDispositionMapper.ensureInitialized();
  p14.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p14.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p14.WorkspaceFileExcerptMapper.ensureInitialized();
  p15.CalculatorOperationMapper.ensureInitialized();
}

