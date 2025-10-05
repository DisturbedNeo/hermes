import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/services/chat_client.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/chat/composer.dart';
import 'package:hermes/ui/chat/message_bubble.dart';

class ChatView extends StatefulWidget {
  final String chatId;
  const ChatView({super.key, required this.chatId});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final List<Bubble> messages = [
    Bubble(role: 'system', text: 'You are a helpful assistant.'),
  ];

  final LlamaServerManager serverManager = serviceProvider
      .get<LlamaServerManager>();

  StreamSubscription<String>? streamSub;
  ChatClient? currentClient;
  bool isStreaming = false;

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
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: messages.length,
            itemBuilder: (_, i) => MessageBubble(
              key: ValueKey('bubble_${i}_${messages[i].text.hashCode}'),
              b: messages[i],
              onSave: (newText) {
                setState(() {
                  messages[i] = Bubble(role: messages[i].role, text: newText);
                });
              },
              editable: true && !isStreaming,
            ),
          ),
        ),

        const Divider(height: 1),

        ValueListenableBuilder<LlamaServerHandle?>(
          valueListenable: serverManager.handle,
          builder: (_, handle, __) {
            final ready = handle != null;
            return Composer(
              controller: controller,
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

    setState(() {
      messages.add(Bubble(role: 'user', text: t));
      messages.add(Bubble(role: 'assistant', text: ''));
      isStreaming = true;
    });

    controller.clear();
    scrollToBottom();

    streamAssistantResponse();
  }

  Future<void> streamAssistantResponse() async {
    final handle = serverManager.current!;
    final baseUrl = handle.baseUrl;
    final client = ChatClient(baseUrl: baseUrl.toString(), model: handle.model);
    currentClient = client;

    final int assistantIndex = messages.length - 1;

    final List<ChatMessage> payload = messages
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
                  role: current.role,
                  text: current.text + token,
                );
              });
            },
            onError: (e, st) {
              if (!mounted) return;
              setState(() {
                messages[assistantIndex] = Bubble(
                  role: 'assistant',
                  text: 'Something went wrong: $e',
                );
              });
            },
            cancelOnError: true,
          );

      await streamSub!.asFuture<void>();

      if (mounted && messages[assistantIndex].text.isEmpty) {
        setState(() {
          messages[assistantIndex] = Bubble(
            role: 'assistant',
            text: '(no response)',
          );
        });
      }
    } on HttpException catch (e) {
      if (!mounted) return;
      setState(() {
        messages[assistantIndex] = Bubble(
          role: 'assistant',
          text: 'Error ${e.message}',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages[assistantIndex] = Bubble(
          role: 'assistant',
          text: 'Something went wrong: $e',
        );
      });
    } finally {
      streamSub = null;
      currentClient?.dispose();
      currentClient = null;

      if (mounted) {
        setState(() => isStreaming = false);
        scrollToBottom();
      }
    }
  }

  void stopStreaming() {
    streamSub?.cancel();
    currentClient?.dispose();
    streamSub = null;
    currentClient = null;
    setState(() => isStreaming = false);
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}
