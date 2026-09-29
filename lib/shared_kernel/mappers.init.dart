// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../platform/tools/calculator_tool.dart' as p0;
import 'chat_message.dart' as p1;
import 'context_summary_prompt.dart' as p2;
import 'model_configuration.dart' as p3;
import 'model_load_configuration.dart' as p4;
import 'planning_metrics.dart' as p5;
import 'project.dart' as p6;
import 'project_planning_contracts.dart' as p7;
import 'project_task_models.dart' as p8;
import 'project_workspace_graph.dart' as p9;
import 'question_policy_service.dart' as p10;
import 'system_prompt.dart' as p11;
import 'task.dart' as p12;
import 'task_execution_contracts.dart' as p13;
import 'task_planning_models.dart' as p14;
import 'task_planning_types.dart' as p15;
import 'task_tool_contracts.dart' as p16;
import 'workspace_discovery_profile.dart' as p17;

/// @nodoc
void initializeMappers() {
  p0.CalculatorOperationMapper.ensureInitialized();
  p1.ChatMessageMapper.ensureInitialized();
  p2.ContextSummaryMapper.ensureInitialized();
  p3.ModelConfigurationSnapshotMapper.ensureInitialized();
  p4.ModelLoadConfigurationMapper.ensureInitialized();
  p5.PlanningMetricsMapper.ensureInitialized();
  p6.ProjectDiagnosticsMapper.ensureInitialized();
  p6.ProjectCriterionMapper.ensureInitialized();
  p6.ProjectEvidenceMapper.ensureInitialized();
  p6.ProjectMilestoneMapper.ensureInitialized();
  p6.ProjectMemoryEntryMapper.ensureInitialized();
  p6.ProjectMemorySupersessionMapper.ensureInitialized();
  p6.ProjectDesiredPlanMapper.ensureInitialized();
  p6.ProjectPlanRevisionMapper.ensureInitialized();
  p6.PendingProjectPlanApprovalMapper.ensureInitialized();
  p6.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
  p6.ProjectBoundaryMapper.ensureInitialized();
  p6.ProjectAggregateMapper.ensureInitialized();
  p6.ProjectRecoveryIncidentMapper.ensureInitialized();
  p6.ProjectDecisionRecordMapper.ensureInitialized();
  p6.ProjectBlockerMapper.ensureInitialized();
  p6.PendingProjectQuestionMapper.ensureInitialized();
  p6.ProjectStatusMapper.ensureInitialized();
  p6.ProjectCriterionStatusMapper.ensureInitialized();
  p6.ProjectVerificationModeMapper.ensureInitialized();
  p6.ProjectEvidenceStatusMapper.ensureInitialized();
  p6.ProjectEvidenceStrengthMapper.ensureInitialized();
  p6.ProjectMilestoneStatusMapper.ensureInitialized();
  p6.TaskReadinessMapper.ensureInitialized();
  p6.ProjectMemoryKindMapper.ensureInitialized();
  p6.ProjectMemorySourceTypeMapper.ensureInitialized();
  p6.ProjectMemoryConfidenceMapper.ensureInitialized();
  p6.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p6.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p6.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p6.ProjectBlockerTypeMapper.ensureInitialized();
  p6.ProjectDecisionTypeMapper.ensureInitialized();
  p6.ProjectControlOutcomeMapper.ensureInitialized();
  p6.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p7.ProjectPlanApprovalPolicyMapper.ensureInitialized();
  p8.ProjectTaskNodeMapper.ensureInitialized();
  p9.ProjectWorkspaceNodeMapper.ensureInitialized();
  p9.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p9.ProjectWorkspaceGraphMapper.ensureInitialized();
  p9.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p9.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p10.AgentQuestionMapper.ensureInitialized();
  p10.QuestionKindMapper.ensureInitialized();
  p11.PromptModuleMapper.ensureInitialized();
  p11.PromptPresetMapper.ensureInitialized();
  p11.SystemPromptSnapshotMapper.ensureInitialized();
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
  p13.TaskGateMapper.ensureInitialized();
  p13.TaskEvidenceExpectationMapper.ensureInitialized();
  p13.TaskArtifactMapper.ensureInitialized();
  p13.TaskGateResultMapper.ensureInitialized();
  p13.TaskFailureMapper.ensureInitialized();
  p13.TaskEvidenceClaimMapper.ensureInitialized();
  p13.TaskGateStatusMapper.ensureInitialized();
  p13.TaskGateFailureDispositionMapper.ensureInitialized();
  p13.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p13.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p14.TaskPlanningContextMapper.ensureInitialized();
  p14.WorkspaceMetadataMapper.ensureInitialized();
  p15.TaskStatusMapper.ensureInitialized();
  p15.TaskPriorityMapper.ensureInitialized();
  p15.TaskRiskMapper.ensureInitialized();
  p15.ProjectRiskReductionMapper.ensureInitialized();
  p15.TaskEffortMapper.ensureInitialized();
  p15.ProjectEvidenceTypeMapper.ensureInitialized();
  p16.TaskToolErrorMapper.ensureInitialized();
  p16.TaskToolErrorDispositionMapper.ensureInitialized();
  p17.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p17.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p17.WorkspaceFileExcerptMapper.ensureInitialized();
}

