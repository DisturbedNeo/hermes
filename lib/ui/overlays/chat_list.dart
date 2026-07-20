import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/ui/common/state_display.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';

class ChatList extends StatefulWidget {
  final FutureOr<void> Function(String chatId) onOpenChat;
  final FutureOr<void> Function(String chatId) onOpenChatInNewTab;
  final FutureOr<void> Function() onNewChat;
  final ChatTabsService tabs;
  final ChatLibraryService library;

  const ChatList({
    super.key,
    required this.tabs,
    required this.library,
    required this.onOpenChat,
    required this.onOpenChatInNewTab,
    required this.onNewChat,
  });

  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  static const double _shortPanelHeight = 160;
  static const double _hideSearchHeight = 120;
  static const double _compactListHeight = 160;
  static const double _tinyPanelHeight = 48;
  static const double _tinyPanelWidth = 80;
  static const double _compactHeaderWidth = 220;

  final _searchController = TextEditingController();

  ChatTabsService get _tabs => widget.tabs;
  ChatLibraryService get _library => widget.library;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final boundedWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite;

        if ((boundedHeight && constraints.maxHeight <= 0) ||
            (boundedWidth && constraints.maxWidth <= 0)) {
          return const SizedBox.shrink();
        }

        final tiny =
            (boundedHeight && constraints.maxHeight < _tinyPanelHeight) ||
            (boundedWidth && constraints.maxWidth < _tinyPanelWidth);
        if (tiny) {
          return const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Icon(Icons.chat_bubble_outline),
            ),
          );
        }

        final compactHeight =
            !boundedHeight || constraints.maxHeight < _shortPanelHeight;
        final hideSearch =
            boundedHeight && constraints.maxHeight < _hideSearchHeight;
        final list = _buildChatList(canMutate);
        final content = Column(
          mainAxisSize: compactHeight ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _buildHeader(canSave: canSave, canMutate: canMutate),
            if (!hideSearch) _buildSearchField(),
            const Divider(height: 1),
            if (compactHeight)
              SizedBox(height: _compactListHeight, child: list)
            else
              Expanded(child: list),
          ],
        );

        if (!compactHeight) return content;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: boundedHeight ? constraints.maxHeight : 0,
            ),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildHeader({required bool canSave, required bool canMutate}) {
    final activeChat = _tabs.activeChat;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth &&
            constraints.maxWidth < _compactHeaderWidth;

        return ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
          title: const Text(
            'Chats',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: compact
              ? PopupMenuButton<_ChatListHeaderAction>(
                  tooltip: 'Chat list actions',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    switch (action) {
                      case _ChatListHeaderAction.save:
                        unawaited(_saveCurrentChat());
                        break;
                      case _ChatListHeaderAction.newChat:
                        unawaited(Future.sync(widget.onNewChat));
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    if (activeChat?.currentChatId == null)
                      PopupMenuItem(
                        value: _ChatListHeaderAction.save,
                        enabled: canSave,
                        child: const Text('Save current chat'),
                      ),
                    PopupMenuItem(
                      value: _ChatListHeaderAction.newChat,
                      enabled: canMutate,
                      child: const Text('New chat'),
                    ),
                  ],
                )
              : Row(
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
        );
      },
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AccessibleWidget(
        label: 'Search saved chats',
        isButton: false,
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search saved chats',
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _buildChatList(bool canMutate) {
    final state = _loading
        ? DisplayState.loading
        : (_error != null
              ? DisplayState.error
              : (_chats.isEmpty ? DisplayState.empty : DisplayState.content));

    Widget buildListView() {
      return ListView.separated(
        itemCount: _chats.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = _chats[i];
          final active = c.id == _tabs.activeChat?.currentChatId;
          final open = _tabs.isSavedChatOpen(c.id);

          return AccessibleWidget(
            label: 'Chat: ${c.title}${active ? ', currently active' : ''}',
            value: _formatDate(c.updatedAt),
            selected: active,
            enabled: canMutate,

            child: ListTile(
              selected: active,
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    active || open
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                  ),
                  if (c.workspace != null)
                    const Positioned(
                      right: -6,
                      bottom: -4,
                      child: Icon(Icons.folder, size: 14),
                    ),
                ],
              ),
              title: Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_formatDate(c.updatedAt)),
              onTap: canMutate ? () => widget.onOpenChat(c.id) : null,
              trailing: AccessibleWidget(
                label: 'Chat actions',
                isButton: true,
                enabled: canMutate,
                child: PopupMenuButton<_ChatAction>(
                  tooltip: 'Chat actions',
                  enabled: canMutate,
                  onSelected: (action) {
                    switch (action) {
                      case _ChatAction.rename:
                        unawaited(_renameChat(c));
                        break;
                      case _ChatAction.openInNewTab:
                        unawaited(
                          Future.sync(() => widget.onOpenChatInNewTab(c.id)),
                        );
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
                    PopupMenuItem(
                      value: _ChatAction.rename,
                      child: Text('Rename'),
                    ),
                    PopupMenuItem(
                      value: _ChatAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return StateDisplay(
      state: state,
      content: buildListView(),
      errorMessage: 'Failed to load chats: $_error',
      emptyMessage: _query.isEmpty ? 'No saved chats' : 'No matching chats',
      emptyHint: _query.isEmpty
          ? 'Create a new chat to get started'
          : 'Try a different search term',
      onRetry: _loading || _error != null ? _reloadChats : null,
      icon: Icons.chat_bubble_outline,
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

enum _ChatListHeaderAction { save, newChat }

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
