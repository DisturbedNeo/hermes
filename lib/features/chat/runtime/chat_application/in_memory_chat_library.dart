import 'package:hermes/shared_kernel/bubble.dart';
import 'package:hermes/shared_kernel/model_configuration.dart';
import 'package:hermes/shared_kernel/saved_chat.dart';
import 'package:hermes/shared_kernel/system_prompt.dart';
import 'package:hermes/shared_kernel/chat_library_port.dart';
import 'package:hermes/shared_kernel/model_json.dart';
import 'package:hermes/shared_kernel/workspace.dart';

/// Small chat repository double for application tests.
class InMemoryChatLibrary implements ChatLibraryPort {
  final Map<String, SavedChat> _chats = {};
  final Map<String, List<Bubble>> _messages = {};

  @override
  Future<void> dispose() async {}

  @override
  Future<List<SavedChat>> listChats() async => _sortedChats();

  @override
  Future<List<SavedChat>> searchChats(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return listChats();
    return _sortedChats()
        .where((chat) => chat.title.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Future<SavedChatSnapshot?> getChat(String chatId) async {
    final chat = _chats[chatId];
    return chat == null
        ? null
        : SavedChatSnapshot(
            chat: chat,
            messages: List.unmodifiable(_messages[chatId] ?? const []),
          );
  }

  @override
  Future<SavedChat> saveChatData({
    String? chatId,
    required String title,
    required DateTime now,
    required String? modelSnapshotJson,
    required WorkspaceAttachment? workspace,
    required SystemPromptSnapshot? systemPromptSnapshot,
    required List<Bubble> messages,
  }) async {
    final id = chatId ?? 'chat_${_chats.length + 1}';
    final existing = _chats[id];
    final chat = SavedChat(
      id: id,
      title: title.isEmpty && existing != null ? existing.title : title,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastOpenedAt: existing?.lastOpenedAt,
      modelSnapshot: modelSnapshotJson == null
          ? null
          : ModelJson.decodeString<ModelConfigurationSnapshot>(
              modelSnapshotJson,
            ),
      workspace: workspace,
      systemPromptSnapshot: systemPromptSnapshot,
    );
    _chats[id] = chat;
    _messages[id] = List.of(messages);
    return chat;
  }

  @override
  Future<void> renameChatData(String chatId, String title) async {
    final chat = _chats[chatId];
    if (chat == null) return;
    _chats[chatId] = SavedChat(
      id: chat.id,
      title: title,
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
      lastOpenedAt: chat.lastOpenedAt,
      modelSnapshot: chat.modelSnapshot,
      workspace: chat.workspace,
      systemPromptSnapshot: chat.systemPromptSnapshot,
    );
  }

  @override
  Future<void> deleteChatData(String chatId) async {
    _chats.remove(chatId);
    _messages.remove(chatId);
  }

  @override
  Future<void> markOpened(String chatId) async {
    final chat = _chats[chatId];
    if (chat == null) return;
    _chats[chatId] = SavedChat(
      id: chat.id,
      title: chat.title,
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
      lastOpenedAt: DateTime.now(),
      modelSnapshot: chat.modelSnapshot,
      workspace: chat.workspace,
      systemPromptSnapshot: chat.systemPromptSnapshot,
    );
  }

  @override
  Future<int> countChats() async => _chats.length;

  List<SavedChat> _sortedChats() =>
      _chats.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
