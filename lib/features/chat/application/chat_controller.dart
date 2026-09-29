import 'package:hermes/features/chat/runtime/chat_controller.dart';

/// Concrete public chat application facade.
///
/// Runtime orchestration remains below this boundary. The dynamic constructor
/// parameters intentionally keep infrastructure types out of the application
/// package; the composition root supplies the concrete implementations.
class ChatController extends ChatRuntimeController {
  ChatController({
    String? tabId,
    required dynamic serverManager,
    required dynamic toolService,
    required dynamic taskController,
    required dynamic projectApplication,
    required dynamic chatLibrary,
    required dynamic workspaceService,
    required dynamic preferencesService,
    dynamic commandCoordinator,
    dynamic toolExecution,
    dynamic initialSystemPromptSnapshot,
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
