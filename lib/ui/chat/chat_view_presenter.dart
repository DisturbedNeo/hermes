import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';
import 'package:hermes/ui/chat/message/message_actions.dart';
import 'package:hermes/ui/chat/message/message_bubble.dart';
import 'package:hermes/ui/chat/message/message_row.dart';
import 'package:hermes/ui/chat/message/message_timestamp.dart';

// -----------------------------------------------------------------------------
// Message list widget (scrollable list + floating scroll-to-bottom button)
// -----------------------------------------------------------------------------

/// Scrollable message list with a floating "scroll to bottom" button.
class MessageListWidget extends StatefulWidget {
  final List<dynamic> displayItems;
  final Map<String, int> displayItemIndices;
  final Widget Function(dynamic item, int index) itemBuilder;
  final ScrollController controller;
  final VoidCallback onScrollToBottom;
  final bool showScrollButton;

  const MessageListWidget({
    super.key,
    required this.displayItems,
    required this.displayItemIndices,
    required this.itemBuilder,
    required this.controller,
    required this.onScrollToBottom,
    required this.showScrollButton,
  });

  @override
  State<MessageListWidget> createState() => _MessageListWidgetState();
}

class _MessageListWidgetState extends State<MessageListWidget> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // Scroll notification handling is managed by the parent view.
            return false;
          },
          child: ListView.builder(
            controller: widget.controller,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: widget.displayItems.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              return widget.displayItemIndices[key.value];
            },
            itemBuilder: (_, i) =>
                widget.itemBuilder(widget.displayItems[i], i),
          ),
        ),
        if (widget.showScrollButton)
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
}

// -----------------------------------------------------------------------------
// Live message item widget
// -----------------------------------------------------------------------------

/// Renders a single live chat message with its bubble and actions.
class LiveMessageItemWidget extends StatefulWidget {
  final ChatService chat;
  final String messageId;
  final bool isSummary;
  final List<String> coveredMessageIds;

  const LiveMessageItemWidget({
    super.key,
    required this.chat,
    required this.messageId,
    required this.isSummary,
    this.coveredMessageIds = const [],
  });

  @override
  State<LiveMessageItemWidget> createState() => _LiveMessageItemWidgetState();
}

class _LiveMessageItemWidgetState extends State<LiveMessageItemWidget> {
  Bubble? _message;

  @override
  void initState() {
    super.initState();
    _message = widget.chat.messageStore.messageById(widget.messageId);
    widget.chat.messageStore.addListener(_handleMessageStoreChanged);
  }

  @override
  void didUpdateWidget(covariant LiveMessageItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chat != oldWidget.chat) {
      oldWidget.chat.messageStore.removeListener(_handleMessageStoreChanged);
      widget.chat.messageStore.addListener(_handleMessageStoreChanged);
    }

    if (widget.chat != oldWidget.chat ||
        widget.messageId != oldWidget.messageId) {
      _message = widget.chat.messageStore.messageById(widget.messageId);
    }
  }

  @override
  void dispose() {
    widget.chat.messageStore.removeListener(_handleMessageStoreChanged);
    super.dispose();
  }

  void _handleMessageStoreChanged() {
    final next = widget.chat.messageStore.messageById(widget.messageId);
    if (identical(next, _message)) return;
    setState(() => _message = next);
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();

    final coveredMessages = widget.coveredMessageIds
        .map(widget.chat.messageStore.messageById)
        .whereType<Bubble>()
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MessageRow(
        isUser: !widget.isSummary && message.role == MessageRole.user,
        bubble: widget.isSummary
            ? SummaryMemoryGroupWidget(
                key: ValueKey('summary_${message.id}'),
                summary: message,
                coveredMessages: coveredMessages,
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

// -----------------------------------------------------------------------------
// Summary memory group widget
// -----------------------------------------------------------------------------

/// Expandable summary memory group showing a collapsed preview and optional
/// expanded child messages.
class SummaryMemoryGroupWidget extends StatefulWidget {
  final Bubble summary;
  final List<Bubble> coveredMessages;

  const SummaryMemoryGroupWidget({
    super.key,
    required this.summary,
    required this.coveredMessages,
  });

  @override
  State<SummaryMemoryGroupWidget> createState() =>
      _SummaryMemoryGroupWidgetState();
}

class _SummaryMemoryGroupWidgetState extends State<SummaryMemoryGroupWidget> {
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

// -----------------------------------------------------------------------------
// Model restore banner widget
// -----------------------------------------------------------------------------

/// Banner shown when a chat was saved with a different model configuration.
class ModelRestoreBannerWidget extends StatelessWidget {
  final String? issue;
  final String modelName;
  final VoidCallback onRestore;
  final VoidCallback onDismiss;

  const ModelRestoreBannerWidget({
    super.key,
    required this.issue,
    required this.modelName,
    required this.onRestore,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(
        issue ??
            'This chat was saved with $modelName. Restore its saved model configuration?',
      ),
      actions: [
        if (issue == null)
          TextButton(onPressed: onRestore, child: const Text('Restore')),
        TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
      ],
    );
  }
}

class SaveFailureBannerWidget extends StatelessWidget {
  const SaveFailureBannerWidget({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: Icon(
        Icons.sync_problem,
        color: Theme.of(context).colorScheme.error,
      ),
      content: Text('Changes haven’t been saved.\n$error'),
      actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
    );
  }
}
