import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Storage contract consumed by the chat application service.
abstract interface class ChatLibraryPort {
  Future<void> dispose();
  Future<List<SavedChat>> listChats();
  Future<List<SavedChat>> searchChats(String query);
  Future<SavedChatSnapshot?> getChat(String chatId);

  Future<SavedChat> saveChatData({
    String? chatId,
    required String title,
    required DateTime now,
    required ModelConfigurationSnapshot? modelSnapshot,
    required WorkspaceAttachment? workspace,
    required List<Bubble> messages,
  });

  Future<void> renameChatData(String chatId, String title);
  Future<void> deleteChatData(String chatId);
  Future<void> markOpened(String chatId);
  Future<int> countChats();
}
