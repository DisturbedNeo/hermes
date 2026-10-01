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
import '../features/project/application/contracts/project_planning_contracts.dart'
    as p4;
import '../features/project/application/contracts/project_snapshot_models.dart'
    as p5;
import '../features/project/application/contracts/project_task_models.dart'
    as p6;
import '../features/project/application/contracts/project_workspace_graph.dart'
    as p7;
import '../features/task/application/contracts/planning_metrics.dart' as p8;
import '../features/task/application/contracts/question_policy_service.dart'
    as p9;
import '../features/task/application/contracts/task_execution_contracts.dart'
    as p10;
import '../features/task/application/contracts/task_planning_models.dart'
    as p11;
import '../features/task/application/contracts/task_planning_types.dart' as p12;
import '../features/task/application/contracts/task_snapshot_models.dart'
    as p13;
import '../features/task/application/contracts/task_tool_contracts.dart' as p14;
import '../features/workspace/application/workspace_discovery_profile.dart'
    as p15;
import '../platform/tools/calculator_tool.dart' as p16;

/// @nodoc
void initializeMappers() {
  p0.PromptModuleMapper.ensureInitialized();
  p0.PromptPresetMapper.ensureInitialized();
  p0.SystemPromptSnapshotMapper.ensureInitialized();
  p1.ContextSummaryMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ModelLoadConfigurationMapper.ensureInitialized();
  p4.ProjectPlanApprovalPolicyMapper.ensureInitialized();
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
  p5.ProjectAggregateMapper.ensureInitialized();
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
  p6.ProjectTaskNodeMapper.ensureInitialized();
  p7.ProjectWorkspaceNodeMapper.ensureInitialized();
  p7.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p7.ProjectWorkspaceGraphMapper.ensureInitialized();
  p7.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p7.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p8.PlanningMetricsMapper.ensureInitialized();
  p9.AgentQuestionMapper.ensureInitialized();
  p9.QuestionKindMapper.ensureInitialized();
  p10.TaskGateMapper.ensureInitialized();
  p10.TaskEvidenceExpectationMapper.ensureInitialized();
  p10.TaskArtifactMapper.ensureInitialized();
  p10.TaskGateResultMapper.ensureInitialized();
  p10.TaskFailureMapper.ensureInitialized();
  p10.TaskEvidenceClaimMapper.ensureInitialized();
  p10.TaskGateStatusMapper.ensureInitialized();
  p10.TaskGateFailureDispositionMapper.ensureInitialized();
  p10.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p10.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p11.TaskPlanningContextMapper.ensureInitialized();
  p11.WorkspaceMetadataMapper.ensureInitialized();
  p12.TaskStatusMapper.ensureInitialized();
  p12.TaskPriorityMapper.ensureInitialized();
  p12.TaskRiskMapper.ensureInitialized();
  p12.ProjectRiskReductionMapper.ensureInitialized();
  p12.TaskEffortMapper.ensureInitialized();
  p12.ProjectEvidenceTypeMapper.ensureInitialized();
  p13.TaskProjectCriterionMapper.ensureInitialized();
  p13.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p13.RefinedTaskBriefMapper.ensureInitialized();
  p13.TaskAggregateMapper.ensureInitialized();
  p13.TaskStepMapper.ensureInitialized();
  p13.TaskRunMapper.ensureInitialized();
  p13.TaskToolCallRecordMapper.ensureInitialized();
  p13.PendingTaskApprovalMapper.ensureInitialized();
  p13.PendingTaskQuestionMapper.ensureInitialized();
  p13.TaskStepStatusMapper.ensureInitialized();
  p13.TaskRunStatusMapper.ensureInitialized();
  p13.TaskToolCallOutcomeMapper.ensureInitialized();
  p14.TaskToolErrorMapper.ensureInitialized();
  p14.TaskToolErrorDispositionMapper.ensureInitialized();
  p15.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p15.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p15.WorkspaceFileExcerptMapper.ensureInitialized();
  p16.CalculatorOperationMapper.ensureInitialized();
}
