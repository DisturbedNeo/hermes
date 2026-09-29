import 'package:hermes/features/chat/application/chat_controller.dart';
import 'package:hermes/features/chat/runtime/chat_workspace_controller.dart';

/// Concrete public workspace-level chat application facade.
class ChatWorkspaceController extends ChatRuntimeWorkspaceController {
  ChatWorkspaceController({
    required dynamic serverManager,
    required dynamic chatLibrary,
    required dynamic systemPromptLibrary,
    required dynamic toolService,
    required dynamic taskController,
    required dynamic projectApplication,
    required dynamic workspaceService,
    required dynamic preferencesService,
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
