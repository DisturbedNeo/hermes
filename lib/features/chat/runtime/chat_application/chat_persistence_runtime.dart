import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Owns the typed chat-snapshot persistence call used by a chat session.
/// Revision queues, scope moves, and reducer transitions remain in the session
/// coordinator; this class only adapts the persistence request.
class ChatPersistenceRuntime {
  const ChatPersistenceRuntime({required ChatLibraryService library})
    : _library = library;

  final ChatLibraryService _library;

  Future<SavedChat> save(ChatPersistenceRequest request) =>
      _library.saveChatSnapshot(
        chatId: request.chatId,
        title: request.title,
        messages: request.messages,
        modelSnapshot: request.modelSnapshot,
        workspace: request.workspace,
      );
}

class ChatPersistenceRequest {
  const ChatPersistenceRequest({
    required this.messages,
    required this.modelSnapshot,
    required this.workspace,
    this.chatId,
    this.title,
  });

  final String? chatId;
  final String? title;
  final List<Bubble> messages;
  final ModelConfigurationSnapshot? modelSnapshot;
  final WorkspaceAttachment? workspace;
}
