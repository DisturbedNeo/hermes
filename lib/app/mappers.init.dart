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
import '../features/persistence/infrastructure/dto/project_state_models.dart'
    as p4;
import '../features/persistence/infrastructure/dto/task_state_models.dart'
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
  p4.ProjectSnapshotAggregateMapper.ensureInitialized();
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
  p5.TaskProjectCriterionMapper.ensureInitialized();
  p5.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p5.RefinedTaskBriefMapper.ensureInitialized();
  p5.TaskSnapshotAggregateMapper.ensureInitialized();
  p5.TaskStepMapper.ensureInitialized();
  p5.TaskRunMapper.ensureInitialized();
  p5.TaskToolCallRecordMapper.ensureInitialized();
  p5.PendingTaskApprovalMapper.ensureInitialized();
  p5.PendingTaskQuestionMapper.ensureInitialized();
  p5.TaskStepStatusMapper.ensureInitialized();
  p5.TaskRunStatusMapper.ensureInitialized();
  p5.TaskToolCallOutcomeMapper.ensureInitialized();
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
  p13.TaskToolErrorMapper.ensureInitialized();
  p13.TaskToolErrorDispositionMapper.ensureInitialized();
  p14.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p14.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p14.WorkspaceFileExcerptMapper.ensureInitialized();
  p15.CalculatorOperationMapper.ensureInitialized();
}

