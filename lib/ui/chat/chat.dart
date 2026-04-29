import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/overlays/chat_list.dart';
import 'package:hermes/ui/chat/chat_view.dart';
import 'package:hermes/ui/chat/model_picker.dart';
import 'package:hermes/ui/overlays/settings.dart';
import 'package:hermes/ui/overlays/workspace_panel.dart';

class Chat extends StatefulWidget {
  const Chat({super.key});

  @override
  State<StatefulWidget> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final _tabs = serviceProvider.get<ChatTabsService>();

  var isChatListOpen = false;
  var isSettingsOpen = false;
  var isWorkspaceOpen = false;

  void toggleChatList() {
    setState(() {
      isChatListOpen = !isChatListOpen;
      if (isChatListOpen) {
        isWorkspaceOpen = false;
        isSettingsOpen = false;
      }
    });
  }

  void toggleSettings() {
    setState(() {
      isSettingsOpen = !isSettingsOpen;
      if (isSettingsOpen) {
        isChatListOpen = false;
        isWorkspaceOpen = false;
      }
    });
  }

  void toggleWorkspace() {
    setState(() {
      isWorkspaceOpen = !isWorkspaceOpen;
      if (isWorkspaceOpen) {
        isChatListOpen = false;
        isSettingsOpen = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Chats',
          icon: const Icon(Icons.menu),
          onPressed: () => toggleChatList(),
        ),
        actions: [
          ModelPicker(),
          IconButton(
            tooltip: 'Workspace',
            icon: AnimatedBuilder(
              animation: _tabs,
              builder: (_, _) {
                final workspace = _tabs.activeChat?.workspace;
                return Icon(
                  workspace == null
                      ? Icons.folder_open_outlined
                      : workspace.missing
                      ? Icons.folder_off_outlined
                      : Icons.folder_special_outlined,
                );
              },
            ),
            onPressed: () => toggleWorkspace(),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => toggleSettings(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) {
          final activeChat = _tabs.activeChat;

          return Column(
            children: [
              _ChatTabStrip(
                tabs: _tabs.tabs,
                activeTabId: _tabs.activeTabId,
                onSelect: (tab) => unawaited(_tabs.selectTab(tab.tabId)),
                onClose: (tab) => unawaited(_closeTab(tab)),
              ),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: activeChat == null
                          ? const SizedBox.shrink()
                          : ChatView(
                              key: ValueKey('chat_${activeChat.tabId}'),
                              chat: activeChat,
                              onOpenWorkspace: _selectWorkspaceForActiveChat,
                            ),
                    ),

                    if (isChatListOpen ||
                        isSettingsOpen ||
                        isWorkspaceOpen) ...[
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            isChatListOpen = false;
                            isSettingsOpen = false;
                            isWorkspaceOpen = false;
                          }),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.1),
                            ),
                          ),
                        ),
                      ),
                    ],

                    _SideSheet(
                      side: AxisDirection.left,
                      open: isChatListOpen,
                      width: 360,
                      child: ChatList(
                        onOpenChat: _openSavedChatInCurrentTab,
                        onOpenChatInNewTab: _openSavedChatInNewTab,
                        onNewChat: () {
                          _tabs.newTab();
                          setState(() => isChatListOpen = false);
                        },
                      ),
                    ),

                    _SideSheet(
                      side: AxisDirection.right,
                      open: isWorkspaceOpen,
                      width: 420,
                      child: WorkspacePanel(
                        chat: activeChat,
                        onSelectWorkspace: _selectWorkspaceForActiveChat,
                      ),
                    ),

                    _SideSheet(
                      side: AxisDirection.right,
                      open: isSettingsOpen,
                      width: 420,
                      child: const Settings(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSavedChatInCurrentTab(String chatId) async {
    if (!_tabs.isSavedChatOpen(chatId) &&
        (_tabs.activeChat?.isUnsavedNonEmpty ?? false)) {
      final choice = await showDialog<_UnsavedTabAction>(
        context: context,
        builder: (_) => const _ReplaceUnsavedTabDialog(),
      );
      if (choice == null || choice == _UnsavedTabAction.cancel) return;

      if (choice == _UnsavedTabAction.save) {
        try {
          await _tabs.activeChat?.saveCurrentChat();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to save chat: $e')));
          return;
        }
      }
    }

    final opened = await _tabs.openSavedChat(
      chatId,
      target: OpenChatTarget.currentTab,
    );
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat not found')));
      return;
    }
    setState(() => isChatListOpen = false);
  }

  Future<void> _selectWorkspaceForActiveChat() async {
    final activeChat = _tabs.activeChat;
    if (activeChat == null || activeChat.chatStream.isStreaming) return;

    final directory = await getDirectoryPath(
      confirmButtonText: 'Open workspace',
    );
    if (directory == null) return;

    try {
      await activeChat.attachWorkspace(directory);
      if (!mounted) return;
      setState(() => isWorkspaceOpen = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Workspace attached')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to attach workspace: $e')));
    }
  }

  Future<void> _openSavedChatInNewTab(String chatId) async {
    final opened = await _tabs.openSavedChat(
      chatId,
      target: OpenChatTarget.newTab,
    );
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat not found')));
      return;
    }
    setState(() => isChatListOpen = false);
  }

  Future<void> _closeTab(ChatService tab) async {
    if (tab.isUnsavedNonEmpty) {
      final choice = await showDialog<_UnsavedTabAction>(
        context: context,
        builder: (_) => const _CloseUnsavedTabDialog(),
      );
      if (choice == null || choice == _UnsavedTabAction.cancel) return;

      if (choice == _UnsavedTabAction.save) {
        try {
          await _tabs.saveAndCloseTab(tab.tabId);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to save chat: $e')));
        }
        return;
      }
    }

    await _tabs.closeTab(tab.tabId);
  }
}

class _ChatTabStrip extends StatelessWidget {
  final List<ChatService> tabs;
  final String? activeTabId;
  final ValueChanged<ChatService> onSelect;
  final ValueChanged<ChatService> onClose;

  const _ChatTabStrip({
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 44,
      width: double.infinity,
      child: Material(
        color: scheme.surfaceContainerLow,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final selected = tab.tabId == activeTabId;
            return _ChatTab(
              tab: tab,
              selected: selected,
              onSelect: () => onSelect(tab),
              onClose: () => onClose(tab),
            );
          },
        ),
      ),
    );
  }
}

class _ChatTab extends StatelessWidget {
  final ChatService tab;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _ChatTab({
    required this.tab,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.surface
        : scheme.surfaceContainerHighest.withValues(alpha: 0.62);
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.65)
        : scheme.outlineVariant.withValues(alpha: 0.65);

    return AnimatedBuilder(
      animation: Listenable.merge([tab, tab.messageStore, tab.chatStream]),
      builder: (context, _) {
        return Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderColor),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: selected ? null : onSelect,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 148, maxWidth: 240),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.isUnsavedNonEmpty) ...[
                      Icon(Icons.circle, size: 8, color: scheme.primary),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        tab.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Close tab',
                      icon: const Icon(Icons.close),
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _UnsavedTabAction { discard, save, cancel }

class _CloseUnsavedTabDialog extends StatelessWidget {
  const _CloseUnsavedTabDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Close unsaved chat?'),
      content: const Text(
        'This chat has not been saved. The chat session will be lost if you continue.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedTabAction.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedTabAction.discard),
          child: const Text('Close without saving'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedTabAction.save),
          child: const Text('Save chat and close'),
        ),
      ],
    );
  }
}

class _ReplaceUnsavedTabDialog extends StatelessWidget {
  const _ReplaceUnsavedTabDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Replace unsaved chat?'),
      content: const Text(
        'This chat has not been saved. The chat session will be lost if you continue.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedTabAction.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedTabAction.discard),
          child: const Text('Close without saving'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_UnsavedTabAction.save),
          child: const Text('Save chat and open'),
        ),
      ],
    );
  }
}

class _SideSheet extends StatelessWidget {
  final AxisDirection side;
  final bool open;
  final double width;
  final Widget child;

  const _SideSheet({
    required this.side,
    required this.open,
    required this.width,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final fromLeft = side == AxisDirection.left;

    return Align(
      alignment: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: open
              ? Offset.zero
              : (fromLeft ? const Offset(-1, 0) : const Offset(1, 0)),
          child: Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
