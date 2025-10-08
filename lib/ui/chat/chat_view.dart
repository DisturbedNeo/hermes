import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/delete_choice.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat_client.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/chat/message/actions_row.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/message/delete_message_dialog.dart';
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
    Bubble(
      id: uuid.v7(),
      role: MessageRole.system,
      text: 'You are a helpful assistant.',
    ),
  ];

  final LlamaServerManager serverManager = serviceProvider
      .get<LlamaServerManager>();

  late final composerFocusNode = FocusNode()..onKeyEvent = onKey;

  StreamSubscription<String>? streamSub;
  ChatClient? currentClient;
  bool isStreaming = false;
  String? streamingId;

  final scroll = ScrollController();

  @override
  void dispose() {
    streamSub?.cancel();
    currentClient?.dispose();
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send(String text) {
    if (isStreaming) return;
    final t = text.trim();
    if (t.isEmpty) return;

    setState(() {
      messages.add(Bubble(id: uuid.v7(), role: MessageRole.user, text: t));
      isStreaming = true;
    });

    controller.clear();
    streamingId = null;

    streamAssistantResponse(assistantIndex: null);
  }

  void generateOrContinue() {
    if (isStreaming || messages.isEmpty) return;

    final lastMessage = messages.last;

    if (lastMessage.role == MessageRole.assistant) {
      setState(() => isStreaming = true);
      streamingId = lastMessage.id;

      streamAssistantResponse(
        assistantIndex: messages.length - 1,
        addGenerationPrompt: true,
      );
    } else {
      setState(() => isStreaming = true);
      streamingId = null;

      streamAssistantResponse(
        assistantIndex: null,
        addGenerationPrompt: lastMessage.role != MessageRole.user,
      );
    }
  }

  Future<void> streamAssistantResponse({
    required int? assistantIndex,
    bool addGenerationPrompt = false,
  }) async {
    final handle = serverManager.current!;

    final client = ChatClient(
      baseUrl: handle.baseUrl.toString(),
      model: handle.model,
    );

    currentClient = client;

    final takeCount = (assistantIndex == null)
        ? messages.length
        : (assistantIndex + 1);

    final payload = messages
        .take(takeCount)
        .where(
          (b) =>
              b.role == MessageRole.system ||
              b.role == MessageRole.user ||
              b.role == MessageRole.assistant,
        )
        .map((b) => ChatMessage(role: b.role.wire, content: b.text))
        .toList();

    final extraParams = <String, dynamic>{
      if (addGenerationPrompt) 'add_generation_prompt': true,
    };

    final buf = StringBuffer();
    Timer? flushTimer;

    void flushNow() {
      if (buf.isEmpty) return;

      setState(() {
        if (assistantIndex == null) {
          final id = uuid.v7();
          messages.add(Bubble(id: id, role: MessageRole.assistant, text: ''));
          assistantIndex = messages.length - 1;
          streamingId = id;
        }

        final current = messages[assistantIndex!];

        messages[assistantIndex!] = current.copyWith(
          text: current.text + buf.toString(),
        );

        buf.clear();
      });
    }

    void scheduleFlush() {
      flushTimer ??= Timer(const Duration(milliseconds: 33), () {
        flushTimer = null;
        flushNow();
      });
    }

    try {
      streamSub = client
          .streamMessage(messages: payload, extraParams: extraParams)
          .listen(
            (token) {
              if (!mounted || token.isEmpty) return;
              buf.write(token);
              scheduleFlush();
            },
            onError: (e, st) {
              if (!mounted) return;
              flushTimer?.cancel();
              buf.clear();
              setState(() {
                if (assistantIndex == null) {
                  final id = uuid.v7();
                  messages.add(
                    Bubble(id: id, role: MessageRole.assistant, text: ''),
                  );
                  assistantIndex = messages.length - 1;
                }
                messages[assistantIndex!] = messages[assistantIndex!].copyWith(
                  text: 'Something went wrong: $e',
                );
              });
            },
            cancelOnError: true,
          );

      await streamSub!.asFuture<void>();
    } finally {
      flushTimer?.cancel();
      flushNow();

      streamSub = null;
      streamingId = null;
      currentClient?.dispose();
      currentClient = null;

      if (mounted) {
        setState(() => isStreaming = false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) composerFocusNode.requestFocus();
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

    if (HardwareKeyboard.instance.isShiftPressed) {
      final text = controller.text;
      final sel = controller.selection;
      final updated = text.replaceRange(sel.start, sel.end, '\n');
      controller.text = updated;
      controller.selection = TextSelection.collapsed(offset: sel.start + 1);
      return KeyEventResult.handled;
    }

    if (!isStreaming) {
      final trimmed = controller.text.trim();
      FocusScope.of(context).unfocus();
      if (trimmed.isNotEmpty) {
        send(trimmed);
      } else {
        generateOrContinue();
      }

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  List<ActionSpec> getActionsForRole(MessageRole role) {
    List<ActionSpec> actions = [];
    MediaQueryData mq = MediaQuery.of(context);

    ActionSpec copyText = ActionSpec(
      icon: Icons.copy_rounded,
      tooltip: 'Copy Text',
      onTap: (message) {
        if (streamingId == message.id) return;
        Clipboard.setData(ClipboardData(text: message.text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied to clipboard'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadiusGeometry.circular(24)),
            margin: EdgeInsets.only(bottom: mq.size.height - 120, left: mq.size.width / 4, right: mq.size.width / 4),
          ),
        );
      },
    );

    actions.add(copyText);

    if (role == MessageRole.assistant) {
      ActionSpec regenerate = ActionSpec(
        icon: Icons.replay_rounded,
        tooltip: 'Regenerate',
        isEnabled: !isStreaming,
        onTap: (message) {
          final messageIndex = messages.indexWhere((m) => m.id == message.id);

          messages.removeRange(messageIndex, messages.length);

          generateOrContinue();
        },
      );

      actions.add(regenerate);
    }

    if (role == MessageRole.user || role == MessageRole.assistant) {
      ActionSpec deleteMessage = ActionSpec(
        icon: Icons.delete_forever_rounded,
        tooltip: 'Delete',
        isEnabled: !isStreaming,
        onTap: (message) async {
          final messageIndex = messages.indexWhere((m) => m.id == message.id);
          if (messageIndex == -1) return;

          final choice = await showDialog<DeleteChoice>(
            context: context, 
            builder: (_) => DeleteMessageDialog(),
          );

          if (choice == null) return;

          setState(() {
            if (choice == DeleteChoice.thisOnly) {
              messages.removeAt(messageIndex);
            } else if (choice == DeleteChoice.includeSubsequent) {
              messages.removeRange(messageIndex, messages.length);
            }
          });
        },
      );

      actions.add(deleteMessage);
    }

    return actions;
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
                      actions: ActionsRow(
                        key: ValueKey('actions_${b.id}'),
                        actions: getActionsForRole(b.role),
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
          valueListenable: serverManager.handle,
          builder: (_, handle, __) {
            return Composer(
              controller: controller,
              focusNode: composerFocusNode,
              enabled: handle != null,
              isStreaming: isStreaming,
              lastWasAssistant:
                  messages.isNotEmpty &&
                  messages.last.role == MessageRole.assistant,
              onSend: send,
              onGenerate: generateOrContinue,
              onContinue: generateOrContinue,
              onCancel: stopStreaming,
            );
          },
        ),
      ],
    );
  }
}
