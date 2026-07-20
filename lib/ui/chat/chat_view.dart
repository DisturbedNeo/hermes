import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/responsive.dart';
import 'package:hermes/core/helpers/scroll.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/keyboard_shortcuts.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';
import 'package:hermes/ui/chat/message/message_actions.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/diagnostics_bar.dart';
import 'package:hermes/ui/chat/task_panel.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';
import 'package:hermes/ui/chat/message/message_bubble.dart';
import 'package:hermes/ui/chat/message/message_row.dart';
import 'package:hermes/ui/chat/message/message_timestamp.dart';
import 'package:hermes/ui/chat/workspace_bar.dart';

class ChatView extends StatefulWidget {
  final ChatService chat;
  final PreferencesService preferencesService;
  final ToolService toolService;
  final VoidCallback onOpenWorkspace;

  const ChatView({
    super.key,
    required this.chat,
    required this.preferencesService,
    required this.toolService,
    required this.onOpenWorkspace,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  static const double _shortHeightBreakpoint = 420;
  static const double _shortFooterHeightRatio = 0.62;
  static const double _tinyHeightBreakpoint = 48;
  static const double _tinyWidthBreakpoint = 80;

  final _scroll = ChatScrollController();
  final _shortcuts = KeyboardShortcutsService();
  final _composerFocusNode = FocusNode();
  bool _taskPanelExpanded = false;
  late int _historyRevision;
  PageStorageBucket? _pageStorageBucket;
  bool _restoredScrollState = false;

  @override
  void initState() {
    super.initState();
    _historyRevision = widget.chat.historyRevision;
    _shortcuts.register(HermesShortcut.toggleTaskPanel, _toggleTaskPanel);
    _shortcuts.register(HermesShortcut.focusComposer, _focusComposer);
    widget.chat.messageStore.addListener(_onMessagesChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageStorageBucket = PageStorage.maybeOf(context);
    if (_restoredScrollState) return;
    _restoredScrollState = true;

    final saved = _pageStorageBucket?.readState(
      context,
      identifier: _scrollStorageIdentifier,
    );
    if (saved is ChatScrollSnapshot &&
        saved.historyRevision == _historyRevision) {
      _scroll.restoreSnapshot(saved);
    }
  }

  @override
  void deactivate() {
    _storeScrollState();
    super.deactivate();
  }

  @override
  void dispose() {
    _storeScrollState();
    widget.chat.messageStore.removeListener(_onMessagesChanged);
    _shortcuts.dispose();
    _composerFocusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMessagesChanged() {
    final nextRevision = widget.chat.historyRevision;
    if (nextRevision == _historyRevision) return;
    _historyRevision = nextRevision;
    _scroll.resetToLatest();
  }

  void _handleScrollToBottom() {
    unawaited(
      _scroll.returnToLatest(animate: !MediaQuery.disableAnimationsOf(context)),
    );
  }

  Object get _scrollStorageIdentifier => 'chat-scroll:${widget.chat.tabId}';

  void _storeScrollState() {
    _pageStorageBucket?.writeState(
      context,
      _scroll.snapshot(historyRevision: _historyRevision),
      identifier: _scrollStorageIdentifier,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final isNarrow = Responsive.isNarrow(context);

    return Shortcuts(
      shortcuts: _shortcuts.activeShortcuts,
      child: Actions(
        actions: _shortcuts.actionsWithFallback(context),
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: Listenable.merge([chat, chat.chatStream]),
            builder: (_, _) {
              final showTaskPanel = _showTaskPanel(chat);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final boundedHeight =
                      constraints.hasBoundedHeight &&
                      constraints.maxHeight.isFinite;
                  final boundedWidth =
                      constraints.hasBoundedWidth &&
                      constraints.maxWidth.isFinite;

                  if ((boundedHeight &&
                          constraints.maxHeight < _tinyHeightBreakpoint) ||
                      (boundedWidth &&
                          constraints.maxWidth < _tinyWidthBreakpoint)) {
                    return const SizedBox.shrink();
                  }

                  final useScrollableFooter =
                      boundedHeight &&
                      constraints.maxHeight < _shortHeightBreakpoint;
                  final footerMaxHeight = useScrollableFooter
                      ? constraints.maxHeight * _shortFooterHeightRatio
                      : null;

                  final mainColumn = _buildMainColumn(
                    chat: chat,
                    showTaskPanel: showTaskPanel,
                    includeInlineTaskPanel:
                        !(isNarrow && _taskPanelExpanded && showTaskPanel),
                    useScrollableFooter: useScrollableFooter,
                    footerMaxHeight: footerMaxHeight,
                  );

                  // On narrow screens, task panel becomes a bottom sheet overlay.
                  if (isNarrow && _taskPanelExpanded && showTaskPanel) {
                    return Stack(
                      children: [
                        mainColumn,
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: DraggableScrollableSheet(
                            initialChildSize: 0.5,
                            minChildSize: 0.3,
                            maxChildSize: 0.85,
                            builder: (context, scrollController) {
                              return TaskPanel(
                                chat: chat,
                                expanded: true,
                                onToggleExpanded: _toggleTaskPanel,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  return mainColumn;
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainColumn({
    required ChatService chat,
    required bool showTaskPanel,
    required bool includeInlineTaskPanel,
    required bool useScrollableFooter,
    required double? footerMaxHeight,
  }) {
    return Column(
      children: [
        if (chat.pendingModelRestore != null) _ModelRestoreBanner(chat: chat),
        WorkspaceBar(chat: chat, onOpenWorkspace: widget.onOpenWorkspace),
        if (includeInlineTaskPanel && showTaskPanel && !_taskPanelExpanded)
          TaskPanel(
            chat: chat,
            expanded: false,
            onToggleExpanded: _toggleTaskPanel,
          ),
        if (includeInlineTaskPanel && showTaskPanel && _taskPanelExpanded)
          Expanded(
            child: TaskPanel(
              chat: chat,
              expanded: true,
              onToggleExpanded: _toggleTaskPanel,
            ),
          ),
        Expanded(
          child: _MessageList(
            scroll: _scroll,
            chat: chat,
            onScrollToBottom: _handleScrollToBottom,
          ),
        ),
        const Divider(height: 1),
        _buildFooter(
          chat: chat,
          scrollable: useScrollableFooter,
          maxHeight: footerMaxHeight,
        ),
      ],
    );
  }

  Widget _buildFooter({
    required ChatService chat,
    required bool scrollable,
    required double? maxHeight,
  }) {
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DiagnosticsBar(
          diagnostics: chat.serverManager.diagnostics,
          preferencesService: widget.preferencesService,
        ),
        ValueListenableBuilder<LlamaServerHandle?>(
          valueListenable: chat.serverManager.handle,
          builder: (_, handle, _) {
            return Composer(
              chat: chat,
              toolService: widget.toolService,
              enabled: handle != null,
              focusNode: _composerFocusNode,
            );
          },
        ),
      ],
    );

    if (!scrollable || maxHeight == null) return footer;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: footer),
    );
  }

  void _toggleTaskPanel() {
    if (!_showTaskPanel(widget.chat)) return;
    setState(() => _taskPanelExpanded = !_taskPanelExpanded);
  }

  void _focusComposer() {
    if (!mounted) return;
    _composerFocusNode.requestFocus();
  }

  bool _showTaskPanel(ChatService chat) {
    return chat.activeProject != null ||
        chat.availableProjects.isNotEmpty ||
        chat.activeTask != null ||
        chat.availableTasks.isNotEmpty ||
        chat.taskBusy;
  }
}

class _MessageList extends StatefulWidget {
  final ChatScrollController scroll;
  final ChatService chat;
  final VoidCallback onScrollToBottom;

  const _MessageList({
    required this.scroll,
    required this.chat,
    required this.onScrollToBottom,
  });

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  bool _showScrollButton = false;
  late List<_DisplayItem> _displayItems;
  late Map<String, int> _displayItemIndices;
  late int _displayRevision;

  @override
  void initState() {
    super.initState();
    _displayRevision = widget.chat.messageStore.displayRevision;
    _displayItems = _buildDisplayItems(widget.chat.messageStore.messages);
    _displayItemIndices = _buildDisplayItemIndices(_displayItems);
    widget.chat.messageStore.addListener(_handleMessageStoreChanged);
    widget.scroll.addListener(_updateScrollButton);
    _scheduleScrollButtonUpdate();
  }

  @override
  void didUpdateWidget(_MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chat != oldWidget.chat) {
      oldWidget.chat.messageStore.removeListener(_handleMessageStoreChanged);
      _displayRevision = widget.chat.messageStore.displayRevision;
      _displayItems = _buildDisplayItems(widget.chat.messageStore.messages);
      _displayItemIndices = _buildDisplayItemIndices(_displayItems);
      widget.chat.messageStore.addListener(_handleMessageStoreChanged);
      _scheduleScrollButtonUpdate();
    }

    if (widget.scroll != oldWidget.scroll) {
      oldWidget.scroll.removeListener(_updateScrollButton);
      widget.scroll.addListener(_updateScrollButton);
      _scheduleScrollButtonUpdate();
    }
  }

  @override
  void dispose() {
    widget.chat.messageStore.removeListener(_handleMessageStoreChanged);
    widget.scroll.removeListener(_updateScrollButton);
    super.dispose();
  }

  void _handleMessageStoreChanged() {
    final nextRevision = widget.chat.messageStore.displayRevision;
    if (nextRevision == _displayRevision) return;

    final oldLength = _displayItems.length;
    final nextItems = _buildDisplayItems(widget.chat.messageStore.messages);
    setState(() {
      _displayRevision = nextRevision;
      _displayItems = nextItems;
      _displayItemIndices = _buildDisplayItemIndices(nextItems);
    });

    if (nextItems.length != oldLength) {
      _scheduleScrollButtonUpdate();
    }
  }

  void _scheduleScrollButtonUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateScrollButton();
    });
  }

  void _updateScrollButton() {
    if (!mounted) return;
    final shouldShow = widget.scroll.needsReturnToLatest;
    if (shouldShow != _showScrollButton) {
      setState(() => _showScrollButton = shouldShow);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    widget.scroll.handleScrollNotification(notification);
    _updateScrollButton();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: ListView.builder(
            controller: widget.scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: _displayItems.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              return _displayItemIndices[key.value];
            },
            itemBuilder: (_, i) {
              final item = _displayItems[i];

              return _LiveMessageItem(
                key: ValueKey('message_${item.messageId}'),
                item: item,
                chat: widget.chat,
              );
            },
          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
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

  List<_DisplayItem> _buildDisplayItems(List<Bubble> messages) {
    final bySummary = <String, List<String>>{};
    for (final message in messages) {
      final summaryId = message.summaryId;
      if (message.omittedFromModelPayload && summaryId != null) {
        bySummary.putIfAbsent(summaryId, () => []).add(message.id);
      }
    }

    return [
      for (final message in messages)
        if (message.isSummaryMemory)
          _SummaryDisplayItem(
            message.id,
            coveredMessageIds: bySummary[message.id] ?? const [],
          )
        else if (!message.omittedFromModelPayload)
          _MessageDisplayItem(message.id),
    ];
  }

  Map<String, int> _buildDisplayItemIndices(List<_DisplayItem> items) {
    return {
      for (var i = 0; i < items.length; i++) 'message_${items[i].messageId}': i,
    };
  }
}

class _DisplayItem {
  final String messageId;

  const _DisplayItem(this.messageId);
}

class _MessageDisplayItem extends _DisplayItem {
  const _MessageDisplayItem(super.messageId);
}

class _SummaryDisplayItem extends _DisplayItem {
  final List<String> coveredMessageIds;

  const _SummaryDisplayItem(super.messageId, {required this.coveredMessageIds});
}

class _LiveMessageItem extends StatefulWidget {
  final _DisplayItem item;
  final ChatService chat;

  const _LiveMessageItem({super.key, required this.item, required this.chat});

  @override
  State<_LiveMessageItem> createState() => _LiveMessageItemState();
}

class _LiveMessageItemState extends State<_LiveMessageItem> {
  Bubble? _message;

  @override
  void initState() {
    super.initState();
    _message = widget.chat.messageStore.messageById(widget.item.messageId);
    widget.chat.messageStore.addListener(_handleMessageStoreChanged);
  }

  @override
  void didUpdateWidget(covariant _LiveMessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chat != oldWidget.chat) {
      oldWidget.chat.messageStore.removeListener(_handleMessageStoreChanged);
      widget.chat.messageStore.addListener(_handleMessageStoreChanged);
    }

    if (widget.chat != oldWidget.chat ||
        widget.item.messageId != oldWidget.item.messageId) {
      _message = widget.chat.messageStore.messageById(widget.item.messageId);
    }
  }

  @override
  void dispose() {
    widget.chat.messageStore.removeListener(_handleMessageStoreChanged);
    super.dispose();
  }

  void _handleMessageStoreChanged() {
    final next = widget.chat.messageStore.messageById(widget.item.messageId);
    if (identical(next, _message)) return;
    setState(() => _message = next);
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();

    final item = widget.item;
    final isSummary = item is _SummaryDisplayItem;
    final isUser = !isSummary && message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MessageRow(
        isUser: isUser,
        bubble: isSummary
            ? _SummaryMemoryGroup(
                key: ValueKey('summary_${message.id}'),
                summary: message,
                coveredMessages: item.coveredMessageIds
                    .map(widget.chat.messageStore.messageById)
                    .whereType<Bubble>()
                    .toList(growable: false),
              )
            : MessageBubble(
                key: ValueKey('bubble_${message.id}'),
                b: message,
                onSave: (newReasoning, newText) {
                  widget.chat.messageStore.upsert(
                    message.copyWith(reasoning: newReasoning, text: newText),
                  );
                },
                editable: !widget.chat.chatStream.isStreaming,
              ),
        actions: MessageActions(
          key: ValueKey('actions_${message.id}'),
          message: message,
          chat: widget.chat,
        ),
      ),
    );
  }
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
        if (widget.summary.createdAt != null) ...[
          const SizedBox(height: 2),
          MessageTimestamp(createdAt: widget.summary.createdAt!),
        ],
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
