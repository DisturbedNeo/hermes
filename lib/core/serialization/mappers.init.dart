// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element

import '../../features/project/domain/project.dart' as p10;
import '../../features/project/domain/project_task_models.dart' as p11;
import '../../features/task/domain/task.dart' as p12;
import '../../features/task/domain/task_planning_models.dart' as p13;
import '../../shared_kernel/project_planning_contracts.dart' as p14;
import '../../shared_kernel/task_execution_contracts.dart' as p15;
import '../../shared_kernel/task_planning_types.dart' as p16;
import '../helpers/chat/context_summary_prompt.dart' as p0;
import '../models/chat_message.dart' as p1;
import '../models/model_configuration_snapshot.dart' as p2;
import '../models/model_load_configuration.dart' as p3;
import '../models/planning_metrics.dart' as p4;
import '../models/project_workspace_graph.dart' as p5;
import '../models/system_prompt.dart' as p6;
import '../services/question_policy_service.dart' as p7;
import '../services/workspace_discovery_profile.dart' as p8;
import '../tools/calculator_tool.dart' as p9;

/// @nodoc
void initializeMappers() {
  p0.ContextSummaryMapper.ensureInitialized();
  p1.ChatMessageMapper.ensureInitialized();
  p2.ModelConfigurationSnapshotMapper.ensureInitialized();
  p3.ModelLoadConfigurationMapper.ensureInitialized();
  p4.PlanningMetricsMapper.ensureInitialized();
  p5.ProjectWorkspaceNodeMapper.ensureInitialized();
  p5.ProjectWorkspaceEdgeMapper.ensureInitialized();
  p5.ProjectWorkspaceGraphMapper.ensureInitialized();
  p5.ProjectWorkspaceSourceTypeMapper.ensureInitialized();
  p5.ProjectWorkspaceConfidenceMapper.ensureInitialized();
  p6.PromptModuleMapper.ensureInitialized();
  p6.PromptPresetMapper.ensureInitialized();
  p6.SystemPromptSnapshotMapper.ensureInitialized();
  p7.AgentQuestionMapper.ensureInitialized();
  p7.QuestionKindMapper.ensureInitialized();
  p8.WorkspaceDiscoveryProfileMapper.ensureInitialized();
  p8.WorkspaceRequiredContextIssueMapper.ensureInitialized();
  p8.WorkspaceFileExcerptMapper.ensureInitialized();
  p9.CalculatorOperationMapper.ensureInitialized();
  p10.ProjectDiagnosticsMapper.ensureInitialized();
  p10.ProjectCriterionMapper.ensureInitialized();
  p10.ProjectEvidenceMapper.ensureInitialized();
  p10.ProjectMilestoneMapper.ensureInitialized();
  p10.ProjectMemoryEntryMapper.ensureInitialized();
  p10.ProjectMemorySupersessionMapper.ensureInitialized();
  p10.ProjectDesiredPlanMapper.ensureInitialized();
  p10.ProjectPlanRevisionMapper.ensureInitialized();
  p10.PendingProjectPlanApprovalMapper.ensureInitialized();
  p10.ProjectCompletionReviewCheckpointMapper.ensureInitialized();
  p10.ProjectBoundaryMapper.ensureInitialized();
  p10.ProjectStateMapper.ensureInitialized();
  p10.ProjectRecoveryIncidentMapper.ensureInitialized();
  p10.ProjectDecisionRecordMapper.ensureInitialized();
  p10.ProjectBlockerMapper.ensureInitialized();
  p10.PendingProjectQuestionMapper.ensureInitialized();
  p10.ProjectStatusMapper.ensureInitialized();
  p10.ProjectCriterionStatusMapper.ensureInitialized();
  p10.ProjectVerificationModeMapper.ensureInitialized();
  p10.ProjectEvidenceStatusMapper.ensureInitialized();
  p10.ProjectEvidenceStrengthMapper.ensureInitialized();
  p10.ProjectMilestoneStatusMapper.ensureInitialized();
  p10.TaskReadinessMapper.ensureInitialized();
  p10.ProjectMemoryKindMapper.ensureInitialized();
  p10.ProjectMemorySourceTypeMapper.ensureInitialized();
  p10.ProjectMemoryConfidenceMapper.ensureInitialized();
  p10.ProjectPlanRevisionTriggerMapper.ensureInitialized();
  p10.ProjectCompletionReviewReasonMapper.ensureInitialized();
  p10.ProjectPlanRevisionApproverMapper.ensureInitialized();
  p10.ProjectBlockerTypeMapper.ensureInitialized();
  p10.ProjectDecisionTypeMapper.ensureInitialized();
  p10.ProjectControlOutcomeMapper.ensureInitialized();
  p10.ProjectRecoveryIncidentStatusMapper.ensureInitialized();
  p11.ProjectTaskNodeMapper.ensureInitialized();
  p12.TaskProjectCriterionMapper.ensureInitialized();
  p12.TaskProjectEvidenceExpectationMapper.ensureInitialized();
  p12.RefinedTaskBriefMapper.ensureInitialized();
  p12.TaskMapper.ensureInitialized();
  p12.TaskStepMapper.ensureInitialized();
  p12.TaskRunMapper.ensureInitialized();
  p12.TaskToolErrorMapper.ensureInitialized();
  p12.TaskToolCallRecordMapper.ensureInitialized();
  p12.PendingTaskApprovalMapper.ensureInitialized();
  p12.PendingTaskQuestionMapper.ensureInitialized();
  p12.TaskStepStatusMapper.ensureInitialized();
  p12.TaskRunStatusMapper.ensureInitialized();
  p12.TaskToolCallOutcomeMapper.ensureInitialized();
  p12.TaskToolErrorDispositionMapper.ensureInitialized();
  p13.TaskPlanningContextMapper.ensureInitialized();
  p13.WorkspaceMetadataMapper.ensureInitialized();
  p14.ProjectPlanApprovalPolicyMapper.ensureInitialized();
  p15.TaskGateMapper.ensureInitialized();
  p15.TaskEvidenceExpectationMapper.ensureInitialized();
  p15.TaskArtifactMapper.ensureInitialized();
  p15.TaskGateResultMapper.ensureInitialized();
  p15.TaskFailureMapper.ensureInitialized();
  p15.TaskEvidenceClaimMapper.ensureInitialized();
  p15.TaskGateStatusMapper.ensureInitialized();
  p15.TaskGateFailureDispositionMapper.ensureInitialized();
  p15.TaskEvidenceClaimTypeMapper.ensureInitialized();
  p15.TaskEvidenceClaimStrengthMapper.ensureInitialized();
  p16.TaskStatusMapper.ensureInitialized();
  p16.TaskPriorityMapper.ensureInitialized();
  p16.TaskRiskMapper.ensureInitialized();
  p16.ProjectRiskReductionMapper.ensureInitialized();
  p16.TaskEffortMapper.ensureInitialized();
  p16.ProjectEvidenceTypeMapper.ensureInitialized();
}

