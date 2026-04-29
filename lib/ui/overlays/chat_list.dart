import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/service_provider.dart';

class ChatList extends StatefulWidget {
  final FutureOr<void> Function(String chatId) onOpenChat;
  final FutureOr<void> Function(String chatId) onOpenChatInNewTab;
  final FutureOr<void> Function() onNewChat;

  const ChatList({
    super.key,
    required this.onOpenChat,
    required this.onOpenChatInNewTab,
    required this.onNewChat,
  });

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  final _tabs = serviceProvider.get<ChatTabsService>();
  final _library = serviceProvider.get<ChatLibraryService>();
  final _searchController = TextEditingController();

  List<SavedChat> _chats = const [];
  bool _loading = true;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _tabs.addListener(_refresh);
    _library.addListener(_refresh);
    unawaited(_reloadChats());
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _tabs.removeListener(_refresh);
    _library.removeListener(_refresh);
    super.dispose();
  }

  Future<List<SavedChat>> _loadChats() {
    return _query.isEmpty ? _library.listChats() : _library.searchChats(_query);
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _query) return;
    setState(() => _query = next);
    unawaited(_reloadChats());
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(_reloadChats(showLoading: false));
  }

  Future<void> _reloadChats({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final chats = await _loadChats();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _saveCurrentChat() async {
    try {
      await _tabs.saveCurrentChat();
      await _reloadChats(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save chat: $e')));
    }
  }

  Future<void> _renameChat(SavedChat chat) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameChatDialog(initialTitle: chat.title),
    );
    if (title == null) return;
    await _library.renameChat(chat.id, title);
    await _reloadChats(showLoading: false);
  }

  Future<void> _deleteChat(SavedChat chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteChatDialog(title: chat.title),
    );
    if (confirmed != true) return;
    await _tabs.deleteSavedChat(chat.id);
    await _reloadChats(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final activeChat = _tabs.activeChat;
    final canMutate = !(activeChat?.chatStream.isStreaming ?? false);
    final canSave = canMutate && activeChat?.currentChatId == null;

    return Column(
      children: [
        ListTile(
          title: const Text(
            'Chats',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activeChat?.currentChatId == null)
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  onPressed: canSave ? _saveCurrentChat : null,
                  tooltip: 'Save current chat',
                ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: canMutate ? () => widget.onNewChat() : null,
                tooltip: 'New chat',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search saved chats',
              isDense: true,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildChatList(canMutate)),
      ],
    );
  }

  Widget _buildChatList(bool canMutate) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load chats: $error'),
        ),
      );
    }

    if (_chats.isEmpty) {
      return Center(
        child: Text(_query.isEmpty ? 'No saved chats' : 'No matching chats'),
      );
    }

    return ListView.separated(
      itemCount: _chats.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = _chats[i];
        final active = c.id == _tabs.activeChat?.currentChatId;
        final open = _tabs.isSavedChatOpen(c.id);

        return ListTile(
          selected: active,
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                active || open ? Icons.chat_bubble : Icons.chat_bubble_outline,
              ),
              if (c.workspace != null)
                const Positioned(
                  right: -6,
                  bottom: -4,
                  child: Icon(Icons.folder, size: 14),
                ),
            ],
          ),
          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_formatDate(c.updatedAt)),
          onTap: canMutate ? () => widget.onOpenChat(c.id) : null,
          trailing: PopupMenuButton<_ChatAction>(
            tooltip: 'Chat actions',
            enabled: canMutate,
            onSelected: (action) {
              switch (action) {
                case _ChatAction.rename:
                  unawaited(_renameChat(c));
                  break;
                case _ChatAction.openInNewTab:
                  unawaited(Future.sync(() => widget.onOpenChatInNewTab(c.id)));
                  break;
                case _ChatAction.delete:
                  unawaited(_deleteChat(c));
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ChatAction.openInNewTab,
                child: Text('Open in new tab'),
              ),
              PopupMenuItem(value: _ChatAction.rename, child: Text('Rename')),
              PopupMenuItem(value: _ChatAction.delete, child: Text('Delete')),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

enum _ChatAction { openInNewTab, rename, delete }

class _RenameChatDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameChatDialog({required this.initialTitle});

  @override
  State<_RenameChatDialog> createState() => _RenameChatDialogState();
}

class _RenameChatDialogState extends State<_RenameChatDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename chat'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Title'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(title);
  }
}

class _DeleteChatDialog extends StatelessWidget {
  final String title;

  const _DeleteChatDialog({required this.title});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete chat'),
      content: Text('Delete "$title"? This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
