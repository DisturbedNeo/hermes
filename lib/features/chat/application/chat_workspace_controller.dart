import 'package:hermes/features/chat/application/chat_controller.dart';
import 'package:hermes/features/chat/runtime/chat_workspace_controller.dart';
import '../../model/application/model_server_port.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import '../../task/application/task_application/task_ports.dart';
import '../../project/application/project_application/project_ports.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';
import 'package:hermes/shared_kernel/preferences_port.dart';

/// Concrete public workspace-level chat application facade.
class ChatWorkspaceController extends ChatRuntimeWorkspaceController {
  ChatWorkspaceController({
    required ModelServerPort serverManager,
    required ChatLibraryService chatLibrary,
    required SystemPromptLibraryService systemPromptLibrary,
    required ToolRegistryPort toolService,
    required TaskChatPort taskController,
    required ProjectChatPort projectApplication,
    required WorkspacePort workspaceService,
    required PreferencesPort preferencesService,
  }) : super(
         serverManager: serverManager,
         chatLibrary: chatLibrary,
         systemPromptLibrary: systemPromptLibrary,
         toolService: toolService,
         taskController: taskController,
         projectApplication: projectApplication,
         workspaceService: workspaceService,
         preferencesService: preferencesService,
         tabFactory:
             ({
               required serverManager,
               required toolService,
               required taskController,
               required projectApplication,
               required chatLibrary,
               required workspaceService,
               required preferencesService,
               initialSystemPromptSnapshot,
             }) => ChatController(
               serverManager: serverManager,
               toolService: toolService,
               taskController: taskController,
               projectApplication: projectApplication,
               chatLibrary: chatLibrary,
               workspaceService: workspaceService,
               preferencesService: preferencesService,
               initialSystemPromptSnapshot: initialSystemPromptSnapshot,
             ),
       );
}
