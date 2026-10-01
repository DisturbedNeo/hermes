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
    required super.toolProtocol,
    required super.toolExecution,
    required super.taskQueries,
    required super.taskSessions,
    required super.taskPresentation,
    required super.panelProtocol,
    required super.taskPlanning,
    required super.taskExecution,
    required super.taskRecovery,
    required super.projectQueries,
    required super.projectSessions,
    required super.projectPlanning,
    required super.projectCommands,
    required super.projectExecution,
    required super.projectRecovery,
    required super.chatLibrary,
    required super.workspaceService,
    required super.preferencesService,
    super.commandCoordinator,
    super.initialSystemPromptSnapshot,
  });
}
