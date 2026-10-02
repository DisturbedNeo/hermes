import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/features/chat/infrastructure/chat_library_repository.dart';
import 'package:hermes/features/chat/infrastructure/system_prompt_library_repository.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';
import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/app/modules/model_module.dart';
import 'package:hermes/app/modules/workspace_tools_module.dart';

/// Chat session, prompt, persistence, and command capabilities.
class ChatModule {
  ChatModule._({
    required this.chatLibrary,
    required this.systemPromptLibrary,
    required this.workspaceController,
  });

  factory ChatModule.create({
    required PreferencesService preferences,
    required ModelModule model,
    required WorkspaceToolsModule workspace,
    required TaskController task,
    required ProjectApplication project,
    required TaskWorkflowPort taskWorkflow,
    required ProjectWorkflowPort projectWorkflow,
  }) {
    final chatLibrary = ChatLibraryService(
      repository: ChatLibraryRepository(preferencesService: preferences),
    );
    final systemPromptLibrary = SystemPromptLibraryService(
      repository: SystemPromptLibraryRepository(
        preferencesService: preferences,
      ),
    );
    final workspaceController = ChatWorkspaceController(
      serverManager: model.manager,
      chatLibrary: chatLibrary,
      systemPromptLibrary: systemPromptLibrary,
      toolService: workspace.tools,
      toolProtocol: workspace.toolProtocol,
      toolExecution: ChatToolExecutionService(protocol: workspace.toolProtocol),
      taskQueries: task,
      taskSessions: task,
      taskPresentation: task,
      panelProtocol: const ChatPanelProtocolAdapter(),
      taskPlanning: taskWorkflow,
      taskExecution: taskWorkflow,
      taskRecovery: taskWorkflow,
      projectQueries: project,
      projectSessions: project,
      projectPlanning: projectWorkflow,
      projectCommands: projectWorkflow,
      projectExecution: projectWorkflow,
      projectRecovery: projectWorkflow,
      workspaceService: workspace.workspace,
      preferencesService: preferences,
    );
    return ChatModule._(
      chatLibrary: chatLibrary,
      systemPromptLibrary: systemPromptLibrary,
      workspaceController: workspaceController,
    );
  }

  final ChatLibraryService chatLibrary;
  final SystemPromptLibraryService systemPromptLibrary;
  final ChatWorkspaceController workspaceController;
}
