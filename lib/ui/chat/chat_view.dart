import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat_client.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/service_provider.dart';
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
  final controller = TextEditingController();
  final List<Bubble> messages = [
    Bubble(id: uuid.v7(), role: 'system', text: 'You are a helpful assistant.'),
  ];

  final LlamaServerManager serverManager = serviceProvider
      .get<LlamaServerManager>();

  late final composerFocusNode = FocusNode()..onKeyEvent = onKey;

  StreamSubscription<String>? streamSub;
  ChatClient? currentClient;
  bool isStreaming = false;
  String? streamingId;

  final scroll = ScrollController();

  GlobalKey? activeAnchorKey;
  double? activeAnchorAlign;
  bool anchorRestoreScheduled = false;

  final Map<String, GlobalKey> rowKeys = {};
  GlobalKey rowKeyFor(String id) => rowKeys.putIfAbsent(id, () => GlobalKey());

  bool get isReady => serverManager.current != null;

  @override
  void dispose() {
    streamSub?.cancel();
    currentClient?.dispose();
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final index = messages.length - 1 - i;
                  final b = messages[index];
                  final isUser = b.role == 'user';
                  final rowKey = rowKeyFor(b.id);

                  return Padding(
                    key: rowKey,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: MessageRow(
                      isUser: isUser,
                      bubble: MessageBubble(
                        key: ValueKey('bubble_${index}_${b.id}'),
                        b: b,
                        onSave: (newText) {
                          setState(() {
                            messages[index] = Bubble(
                              id: b.id,
                              role: b.role,
                              text: newText,
                            );
                          });
                        },
                        editable: !isStreaming,
                      ),
                      actions: _RowActionsPlaceholder(isUser: isUser),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ValueListenableBuilder<LlamaServerHandle?>(
          valueListenable: serverManager.handle,
          builder: (_, handle, __) {
            final ready = handle != null;
            return Composer(
              controller: controller,
              focusNode: composerFocusNode,
              enabled: ready,
              isStreaming: isStreaming,
              onSubmitted: send,
              onCancel: stopStreaming,
            );
          },
        ),
      ],
    );
  }

  void send(String text) {
    if (isStreaming) return;
    final t = text.trim();
    if (t.isEmpty) return;

    final assistantId = uuid.v7();

    setState(() {
      messages.add(Bubble(id: uuid.v7(), role: 'user', text: t));
      messages.add(Bubble(id: assistantId, role: 'assistant', text: ''));
      isStreaming = true;
    });

    controller.clear();

    streamingId = assistantId;

    streamAssistantResponse();
  }

  Future<void> streamAssistantResponse() async {
    final handle = serverManager.current!;
    final client = ChatClient(
      baseUrl: handle.baseUrl.toString(),
      model: handle.model,
    );
    currentClient = client;

    final int assistantIndex = messages.length - 1;

    final payload = messages
        .take(assistantIndex)
        .where(
          (b) =>
              b.role == 'system' || b.role == 'user' || b.role == 'assistant',
        )
        .map((b) => ChatMessage(role: b.role, content: b.text))
        .toList();

    try {
      streamSub = client
          .streamMessage(messages: payload)
          .listen(
            (token) {
              if (!mounted || token.isEmpty) return;

              setState(() {
                final current = messages[assistantIndex];
                messages[assistantIndex] = Bubble(
                  id: current.id,
                  role: current.role,
                  text: current.text + token,
                );
              });
            },
            onError: (e, st) {
              if (!mounted) return;

              setState(() {
                messages[assistantIndex] = Bubble(
                  id: uuid.v7(),
                  role: 'assistant',
                  text: 'Something went wrong: $e',
                );
              });
            },
            cancelOnError: true,
          );

      await streamSub!.asFuture<void>();
    } finally {
      streamSub = null;
      streamingId = null;
      currentClient?.dispose();
      currentClient = null;

      if (mounted) {
        setState(() => isStreaming = false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            composerFocusNode.requestFocus();
          }
        });
      }
    }
  }

  void stopStreaming() {
    streamSub?.cancel();
    currentClient?.dispose();
    streamSub = null;
    currentClient = null;
    setState(() => isStreaming = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        composerFocusNode.requestFocus();
      }
    });
  }

  KeyEventResult onKey(node, event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }

    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!shift && !isStreaming) {
      FocusScope.of(context).unfocus();
      send(controller.text.trim());
      return KeyEventResult.handled;
    }

    if (shift) {
      final text = controller.text;
      final sel = controller.selection;
      final updated = text.replaceRange(sel.start, sel.end, '\n');
      controller.text = updated;
      controller.selection = TextSelection.collapsed(offset: sel.start + 1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

class _RowActionsPlaceholder extends StatelessWidget {
  final bool isUser;
  const _RowActionsPlaceholder({required this.isUser});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;

    return Opacity(
      opacity: 0.6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.more_horiz, size: 20, color: color),
          const SizedBox(width: 4),
          Icon(isUser ? Icons.person : Icons.smart_toy, size: 18, color: color),
        ],
      ),
    );
  }
}
