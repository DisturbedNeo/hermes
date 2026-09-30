import 'package:hermes/features/chat/runtime/chat_controller.dart';

/// Concrete public chat application facade.
///
/// Runtime orchestration remains below this boundary and receives only typed
/// feature ports.
class ChatController extends ChatRuntimeController {
  ChatController({
    super.tabId,
    required super.serverManager,
    required super.toolService,
    required super.taskController,
    required super.projectApplication,
    required super.chatLibrary,
    required super.workspaceService,
    required super.preferencesService,
    super.commandCoordinator,
    super.toolExecution,
    super.initialSystemPromptSnapshot,
  });
}
