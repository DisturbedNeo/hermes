import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/helpers/scroll.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';
import 'package:hermes/ui/chat/message/message_actions.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/diagnostics_bar.dart';
import 'package:hermes/ui/chat/job_panel.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';
import 'package:hermes/ui/chat/message/message_bubble.dart';
import 'package:hermes/ui/chat/message/message_row.dart';
import 'package:hermes/ui/chat/workspace_bar.dart';

class ChatView extends StatefulWidget {
  final ChatService chat;
  final VoidCallback onOpenWorkspace;

  const ChatView({
    super.key,
    required this.chat,
    required this.onOpenWorkspace,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = SmartScrollController();
  bool _jobPanelExpanded = false;
  bool _autoScrollEnabled = true;
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    widget.chat.messageStore.addListener(_onMessagesChanged);
    widget.chat.chatStream.addListener(_onStreamStateChanged);
  }

  @override
  void dispose() {
    widget.chat.messageStore.removeListener(_onMessagesChanged);
    widget.chat.chatStream.removeListener(_onStreamStateChanged);
    _scroll.dispose();
    _scrollDebounceTimer?.cancel();
    super.dispose();
  }

  void _onMessagesChanged() {
    // Debounce rapid message updates (e.g., streaming text chunks) to avoid
    // excessive scroll animations during active generation.
    _scrollDebounceTimer?.cancel();
    if (_autoScrollEnabled && mounted) {
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && _autoScrollEnabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scroll.scrollToBottom(duration: const Duration(milliseconds: 150));
          });
        }
      });
    }
  }

  void _onStreamStateChanged() {
    // When streaming ends, ensure auto-scroll is enabled and scroll to bottom
    if (widget.chat.chatStream.state == StreamState.idle) {
      setState(() => _autoScrollEnabled = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scroll.scrollToBottom();
      });
    }
  }

  void _handleScrollToBottom() {
    setState(() => _autoScrollEnabled = true);
    _scroll.enableAutoScroll();
    _scroll.scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return AnimatedBuilder(
      animation: Listenable.merge([chat, chat.messageStore, chat.chatStream]),
      builder: (_, _) {
        final displayItems = _displayItems(chat.messageStore.messages);
        final showJobPanel = _showJobPanel(chat);
        return Column(
          children: [
            if (chat.pendingModelRestore != null)
              _ModelRestoreBanner(chat: chat),
            WorkspaceBar(chat: chat, onOpenWorkspace: widget.onOpenWorkspace),
            if (showJobPanel && !_jobPanelExpanded)
              JobPanel(
                chat: chat,
                expanded: false,
                onToggleExpanded: _toggleJobPanel,
              ),
            if (showJobPanel && _jobPanelExpanded)
              Expanded(
                child: JobPanel(
                  chat: chat,
                  expanded: true,
                  onToggleExpanded: _toggleJobPanel,
                ),
              ),
            Expanded(
              child: _MessageList(
                scroll: _scroll,
                displayItems: displayItems,
                chat: chat,
                autoScrollEnabled: _autoScrollEnabled,
                onScrollToBottom: _handleScrollToBottom,
              ),
            ),
            const Divider(height: 1),
            const DiagnosticsBar(),
            ValueListenableBuilder<LlamaServerHandle?>(
              valueListenable: chat.serverManager.handle,
              builder: (_, handle, _) {
                return Composer(chat: chat, enabled: handle != null);
              },
            ),
          ],
        );
      },
    );
  }

  void _toggleJobPanel() {
    setState(() => _jobPanelExpanded = !_jobPanelExpanded);
  }

  bool _showJobPanel(ChatService chat) {
    return chat.activeJob != null ||
        chat.availableJobs.isNotEmpty ||
        chat.jobBusy;
  }

  List<_DisplayItem> _displayItems(List<Bubble> messages) {
    final bySummary = <String, List<Bubble>>{};
    for (final message in messages) {
      final summaryId = message.summaryId;
      if (message.omittedFromModelPayload && summaryId != null) {
        bySummary.putIfAbsent(summaryId, () => []).add(message);
      }
    }

    return [
      for (final message in messages)
        if (message.isSummaryMemory)
          _SummaryDisplayItem(
            message,
            coveredMessages: bySummary[message.id] ?? const [],
          )
        else if (!message.omittedFromModelPayload)
          _MessageDisplayItem(message),
    ];
  }
}

class _MessageList extends StatefulWidget {
  final SmartScrollController scroll;
  final List<_DisplayItem> displayItems;
  final ChatService chat;
  final bool autoScrollEnabled;
  final VoidCallback onScrollToBottom;

  const _MessageList({
    required this.scroll,
    required this.displayItems,
    required this.chat,
    required this.autoScrollEnabled,
    required this.onScrollToBottom,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  bool _showScrollButton = false;

  void _attachListener() {
    final position = widget.scroll.positions.firstOrNull;
    if (position != null) {
      position.isScrollingNotifier.addListener(_onScrollingChanged);
    }
  }

  void _detachListener() {
    final position = widget.scroll.positions.firstOrNull;
    if (position != null) {
      position.isScrollingNotifier.removeListener(_onScrollingChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    // Defer listener attachment until after the first build when the controller
    // is attached to its scroll position.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attachListener());
  }

  @override
  void didUpdateWidget(_MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scroll != oldWidget.scroll) {
      _detachListener();
      _attachListener();
    }
  }

  @override
  void dispose() {
    _detachListener();
    super.dispose();
  }

  void _onScrollingChanged() {
    final position = widget.scroll.positions.firstOrNull;
    if (position == null) return;
    if (!position.isScrollingNotifier.value) {
      final atBottom = position.pixels >= position.maxScrollExtent - 50;
      // Only show button when auto-scroll is enabled and user scrolled away
      setState(() {
        _showScrollButton = !atBottom && widget.autoScrollEnabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView.builder(
          controller: widget.scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          itemCount: widget.displayItems.length,
          itemBuilder: (_, i) {
            final item = widget.displayItems[widget.displayItems.length - 1 - i];
            final b = item.message;
            final isUser = item is _SummaryDisplayItem
                ? false
                : b.role == MessageRole.user;

            return Padding(
              key: ValueKey('message_${b.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MessageRow(
                isUser: isUser,
                bubble: item is _SummaryDisplayItem
                    ? _SummaryMemoryGroup(
                        key: ValueKey('summary_${b.id}'),
                        summary: b,
                        coveredMessages: item.coveredMessages,
                      )
                    : MessageBubble(
                        key: ValueKey('bubble_${b.id}'),
                        b: b,
                        onSave: (newReasoning, newText) {
                          widget.chat.messageStore.upsert(
                            b.copyWith(reasoning: newReasoning, text: newText),
                          );
                        },
                        editable: !widget.chat.chatStream.isStreaming,
                      ),
                actions: MessageActions(
                  key: ValueKey('actions_${b.id}'),
                  message: b,
                  chat: widget.chat,
                ),
              ),
            );
          },
        ),
        // Floating scroll-to-bottom button that appears when user scrolls away
        if (_showScrollButton)
          Positioned(
            bottom: 16,
            right: 16,
            child: Material(
              elevation: 4,
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onScrollToBottom,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.expand_more,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Scroll to bottom',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DisplayItem {
  final Bubble message;

  const _DisplayItem(this.message);
}

class _MessageDisplayItem extends _DisplayItem {
  const _MessageDisplayItem(super.message);
}

class _SummaryDisplayItem extends _DisplayItem {
  final List<Bubble> coveredMessages;

  const _SummaryDisplayItem(super.message, {required this.coveredMessages});
}

class _SummaryMemoryGroup extends StatefulWidget {
  final Bubble summary;
  final List<Bubble> coveredMessages;

  const _SummaryMemoryGroup({
    super.key,
    required this.summary,
    required this.coveredMessages,
  });

  @override
  State<_SummaryMemoryGroup> createState() => _SummaryMemoryGroupState();
}

class _SummaryMemoryGroupState extends State<_SummaryMemoryGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = getColorsForRole(scheme, MessageRole.system);
    final count = widget.coveredMessages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BubbleSurface(
          borderRadius: BorderRadius.circular(8),
          background: bg,
          onTap: count == 0
              ? null
              : () => setState(() => _expanded = !_expanded),
          enabled: count > 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                    color: fg,
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.assignment_outlined, size: 18, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$count messages summarised',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: MarkdownView(data: widget.summary.text),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          for (final message in widget.coveredMessages)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 8),
              child: Opacity(
                opacity: 0.82,
                child: MessageRow(
                  isUser: message.role == MessageRole.user,
                  bubble: MessageBubble(b: message, editable: false),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ModelRestoreBanner extends StatelessWidget {
  final ChatService chat;

  const _ModelRestoreBanner({required this.chat});

  @override
  Widget build(BuildContext context) {
    final snapshot = chat.pendingModelRestore!;
    final issue = chat.pendingModelRestoreIssue;

    return MaterialBanner(
      content: Text(
        issue ??
            'This chat was saved with ${snapshot.modelName}. Restore its saved model configuration?',
      ),
      actions: [
        if (issue == null)
          TextButton(
            onPressed: () async {
              try {
                await chat.restorePendingModel();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to restore model: $e')),
                );
              }
            },
            child: const Text('Restore'),
          ),
        TextButton(
          onPressed: chat.dismissPendingModelRestore,
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
