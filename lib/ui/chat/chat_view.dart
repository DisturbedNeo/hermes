import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/chat/message/message_actions.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/message/message_bubble.dart';
import 'package:hermes/ui/chat/message/message_row.dart';

class ChatView extends StatefulWidget {
  final String chatId;
  const ChatView({super.key, required this.chatId});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _chat = serviceProvider.get<ChatService>();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _chat,
      builder: (_, _) {
        return Column(
          children: [
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
                    itemCount: _chat.messages.length,
                    itemBuilder: (_, i) {
                      final index = _chat.messages.length - 1 - i;
                      final b = _chat.messages[index];
                      final isUser = b.role == MessageRole.user;

                      return Padding(
                        key: ValueKey('message_${b.id}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: MessageRow(
                          isUser: isUser,
                          bubble: MessageBubble(
                            key: ValueKey('bubble_${b.id}'),
                            b: b,
                            onSave: (newText) {
                              _chat.updateMessage(b, newText);
                            },
                            editable: !_chat.isStreaming,
                          ),
                          actions: MessageActions(
                            key: ValueKey('actions_${b.id}'),
                            message: b,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ValueListenableBuilder<LlamaServerHandle?>(
              valueListenable: _chat.serverManager.handle,
              builder: (_, handle, __) {
                return Composer(
                  enabled: handle != null,
                  isStreaming: _chat.isStreaming,
                  lastWasAssistant:
                      _chat.messages.isNotEmpty &&
                      _chat.messages.last.role == MessageRole.assistant,
                  onSend: _chat.send,
                  onGenerate: _chat.generateOrContinue,
                  onContinue: _chat.generateOrContinue,
                  onCancel: _chat.stopStreaming,
                );
              },
            ),
          ],
        );
      },
    );
  }
}
