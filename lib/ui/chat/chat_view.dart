import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/responsive.dart';
import 'package:hermes/core/helpers/scroll.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/keyboard_shortcuts.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/diagnostics_bar.dart';
import 'package:hermes/ui/chat/task_panel.dart';
import 'package:hermes/ui/chat/workspace_bar.dart';
import 'package:hermes/ui/chat/chat_view_presenter.dart';

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
        if (chat.saveFailure != null)
          SaveFailureBannerWidget(
            error: chat.saveFailure!.error,
            onRetry: () => unawaited(_retrySave(chat)),
          ),
        if (chat.pendingModelRestore != null) _buildModelRestoreBanner(chat),
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
        Expanded(child: _buildMessageList(chat)),
        const Divider(height: 1),
        _buildFooter(
          chat: chat,
          scrollable: useScrollableFooter,
          maxHeight: footerMaxHeight,
        ),
      ],
    );
  }

  Future<void> _retrySave(ChatService chat) async {
    try {
      await chat.retrySave();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save chat: $error')));
    }
  }

  Widget _buildModelRestoreBanner(ChatService chat) {
    final snapshot = chat.pendingModelRestore!;
    final issue = chat.pendingModelRestoreIssue;

    return ModelRestoreBannerWidget(
      issue: issue,
      modelName: snapshot.modelName,
      onRestore: () async {
        try {
          await chat.restorePendingModel();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to restore model: $e')),
          );
        }
      },
      onDismiss: chat.dismissPendingModelRestore,
    );
  }

  Widget _buildMessageList(ChatService chat) {
    return _MessageListPresenter(
      scroll: _scroll,
      chat: chat,
      onScrollToBottom: _handleScrollToBottom,
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

// ---------------------------------------------------------------------------
// Display item data classes (used by business logic in _MessageListPresenterState)
// ---------------------------------------------------------------------------

/// Base class for items in the message display list.
class _DisplayItem {
  final String messageId;

  const _DisplayItem(this.messageId);
}

/// Represents a regular chat message bubble.
class _MessageDisplayItem extends _DisplayItem {
  const _MessageDisplayItem(super.messageId);
}

/// Represents a summarised memory group with its covered message IDs.
class _SummaryDisplayItem extends _DisplayItem {
  final List<String> coveredMessageIds;

  const _SummaryDisplayItem(super.messageId, {required this.coveredMessageIds});
}

// ---------------------------------------------------------------------------
// Message list presenter — manages display-item computation and message store
// subscriptions (business logic + state), delegates rendering to presenter.
// ---------------------------------------------------------------------------

/// Internal widget that owns the message-list state: display item computation,
/// message-store subscriptions, and scroll-button visibility. It delegates pure
/// UI rendering to [MessageListWidget] from the presenter module.
class _MessageListPresenter extends StatefulWidget {
  final ChatScrollController scroll;
  final ChatService chat;
  final VoidCallback onScrollToBottom;

  const _MessageListPresenter({
    required this.scroll,
    required this.chat,
    required this.onScrollToBottom,
  });

  @override
  State<_MessageListPresenter> createState() => _MessageListPresenterState();
}

class _MessageListPresenterState extends State<_MessageListPresenter> {
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
  void didUpdateWidget(_MessageListPresenter oldWidget) {
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
          child: MessageListWidget(
            displayItems: _displayItems,
            displayItemIndices: _displayItemIndices,
            controller: widget.scroll,
            itemBuilder: (_, i) {
              final item = _displayItems[i];
              return LiveMessageItemWidget(
                key: ValueKey('message_${item.messageId}'),
                chat: widget.chat,
                messageId: item.messageId,
                isSummary: item is _SummaryDisplayItem,
                coveredMessageIds: item is _SummaryDisplayItem
                    ? item.coveredMessageIds
                    : const [],
              );
            },
            onScrollToBottom: widget.onScrollToBottom,
            showScrollButton: _showScrollButton,
          ),
        ),
      ],
    );
  }

  // -- Business logic: display item computation --------------------------------

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
