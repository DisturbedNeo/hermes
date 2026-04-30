import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';
import 'package:hermes/ui/chat/message/message_actions.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/diagnostics_bar.dart';
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
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return AnimatedBuilder(
      animation: Listenable.merge([chat, chat.messageStore, chat.chatStream]),
      builder: (_, _) {
        final displayItems = _displayItems(chat.messageStore.messages);
        return Column(
          children: [
            if (chat.pendingModelRestore != null)
              _ModelRestoreBanner(chat: chat),
            WorkspaceBar(chat: chat, onOpenWorkspace: widget.onOpenWorkspace),
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    itemCount: displayItems.length,
                    itemBuilder: (_, i) {
                      final item = displayItems[displayItems.length - 1 - i];
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
                                    chat.messageStore.upsert(
                                      b.copyWith(
                                        reasoning: newReasoning,
                                        text: newText,
                                      ),
                                    );
                                  },
                                  editable: !chat.chatStream.isStreaming,
                                ),
                          actions: MessageActions(
                            key: ValueKey('actions_${b.id}'),
                            message: b,
                            chat: chat,
                          ),
                        ),
                      );
                    },
                  ),
                ],
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
