import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/ui/chat/message/message_actions.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/diagnostics_bar.dart';
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
                    itemCount: chat.messageStore.messages.length,
                    itemBuilder: (_, i) {
                      final index = chat.messageStore.messages.length - 1 - i;
                      final b = chat.messageStore.messages[index];
                      final isUser = b.role == MessageRole.user;

                      return Padding(
                        key: ValueKey('message_${b.id}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: MessageRow(
                          isUser: isUser,
                          bubble: MessageBubble(
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
