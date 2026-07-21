import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/chat_library_repository.dart';

import '../disposable.dart';

/// Orchestrator for chat library operations.
///
/// Handles business rules, state management (ChangeNotifier), and delegates
/// all data access to [ChatLibraryRepository].  This class has a single
/// responsibility: coordinating high-level service methods while maintaining
/// reactive state.
class ChatLibraryService extends ChangeNotifier implements Disposable {
  final ChatLibraryRepository _repository;
  bool _disposed = false;

  ChatLibraryService({
    required ChatLibraryRepository repository,
  }) : _repository = repository;

  // ── Public API (delegated to repository) ───────────────────────────────

  Future<List<SavedChat>> listChats() => _repository.listChats();

  Future<List<SavedChat>> searchChats(String query) =>
      _repository.searchChats(query);

  Future<SavedChatSnapshot?> getChat(String chatId) =>
      _repository.getChat(chatId);

  /// Saves a chat snapshot, applying business rules (title derivation, etc.)
  /// before delegating data persistence to the repository.
  Future<SavedChat> saveChatSnapshot({
    required List<Bubble> messages,
    required ModelConfigurationSnapshot? modelSnapshot,
    required WorkspaceAttachment? workspace,
    required SystemPromptSnapshot? systemPromptSnapshot,
    String? chatId,
    String? title,
  }) async {
    final now = DateTime.now();

    // Derive the resolved title: use provided title if valid, derive from
    // messages for new chats.  For existing chats with no provided title,
    // pass an empty string so the repository preserves the existing one.
    final resolvedTitle = _resolveTitle(
      chatId: chatId,
      providedTitle: title,
      messages: messages,
    );

    final saved = await _repository.saveChatData(
      chatId: chatId,
      title: resolvedTitle,
      now: now,
      modelSnapshotJson: modelSnapshot == null
          ? null
          : ModelJson.encodeString(modelSnapshot),
      workspace: workspace,
      systemPromptSnapshot: systemPromptSnapshot,
      messages: messages,
    );

    notifyListeners();
    return saved;
  }

  /// Renames a chat after validating the title.
  Future<void> renameChat(String chatId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    await _repository.renameChatData(chatId, trimmed);
    notifyListeners();
  }

  /// Deletes a chat and its associated data.
  Future<void> deleteChat(String chatId) async {
    await _repository.deleteChatData(chatId);
    notifyListeners();
  }

  /// Marks a chat as recently opened.
  Future<void> markOpened(String chatId) async {
    await _repository.markOpened(chatId);
    notifyListeners();
  }

  /// Returns the total number of chats.
  Future<int> countChats() => _repository.countChats();

  // ── Business logic ─────────────────────────────────────────────────────

  /// Derives a chat title from the first non-system message with content.
  String _deriveTitle(List<Bubble> messages) {
    final first = messages
        .where((m) => m.role != MessageRole.system && m.text.trim().isNotEmpty)
        .map((m) => m.text.trim().replaceAll(RegExp(r'\s+'), ' '))
        .firstOrNull;

    if (first == null) return 'Untitled chat';
    return first.length <= 64 ? first : '${first.substring(0, 61)}...';
  }

  /// Resolves the title to persist: uses provided title if valid, derives
  /// from messages for new chats, or returns empty string for existing chats
  /// (signaling the repository to preserve the existing title).
  String _resolveTitle({
    required String? chatId,
    required String? providedTitle,
    required List<Bubble> messages,
  }) {
    if ((providedTitle?.trim().isNotEmpty ?? false)) {
      return providedTitle!.trim();
    }
    // Existing chat with no new title → preserve existing.
    if (chatId != null) return '';
    // New chat → derive from first meaningful message.
    return _deriveTitle(messages);
  }

  // ── Disposable ─────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _repository.dispose();
    super.dispose();
  }
}
