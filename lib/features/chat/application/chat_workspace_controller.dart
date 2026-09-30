import 'package:hermes/features/chat/application/chat_controller.dart';
import 'package:hermes/features/chat/runtime/chat_workspace_controller.dart';

/// Concrete public workspace-level chat application facade.
class ChatWorkspaceController extends ChatRuntimeWorkspaceController {
  ChatWorkspaceController({
    required super.serverManager,
    required super.chatLibrary,
    required super.systemPromptLibrary,
    required super.toolService,
    required super.taskController,
    required super.projectApplication,
    required super.workspaceService,
    required super.preferencesService,
  }) : super(
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
