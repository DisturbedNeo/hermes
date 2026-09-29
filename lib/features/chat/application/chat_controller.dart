import 'package:hermes/features/chat/runtime/chat_controller.dart';
import '../../model/application/model_server_port.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import '../../task/application/task_application/task_ports.dart';
import '../../project/application/project_application/project_ports.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';
import 'package:hermes/shared_kernel/preferences_port.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_command_coordinator.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/shared_kernel/system_prompt.dart';

/// Concrete public chat application facade.
///
/// Runtime orchestration remains below this boundary and receives only typed
/// feature ports.
class ChatController extends ChatRuntimeController {
  ChatController({
    String? tabId,
    required ModelServerPort serverManager,
    required ToolRegistryPort toolService,
    required TaskChatPort taskController,
    required ProjectChatPort projectApplication,
    required ChatLibraryService chatLibrary,
    required WorkspacePort workspaceService,
    required PreferencesPort preferencesService,
    ChatCommandCoordinator? commandCoordinator,
    ChatToolExecutionPort? toolExecution,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : super(
         tabId: tabId,
         serverManager: serverManager,
         toolService: toolService,
         taskController: taskController,
         projectApplication: projectApplication,
         chatLibrary: chatLibrary,
         workspaceService: workspaceService,
         preferencesService: preferencesService,
         commandCoordinator: commandCoordinator,
         toolExecution: toolExecution,
         initialSystemPromptSnapshot: initialSystemPromptSnapshot,
       );
}
