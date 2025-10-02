import 'package:flutter/material.dart';

class ChatView extends StatefulWidget {
  final String chatId;
  const ChatView({super.key, required this.chatId});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Bubble> _messages = [
    _Bubble(role: 'system', text: 'You are a helpful assistant.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _MessageBubble(b: _messages[i]),
          ),
        ),
        const Divider(height: 1),
        _Composer(
          controller: _controller,
          onSubmitted: _send,
        ),
      ],
    );
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() {
      _messages.add(_Bubble(role: 'user', text: t));
      _messages.add(const _Bubble(role: 'assistant', text: '…thinking…'));
    });
    _controller.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  const _Composer({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.send,
                onSubmitted: onSubmitted,
                decoration: const InputDecoration(
                  hintText: 'Message the model…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send'),
              onPressed: () => onSubmitted(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble {
  final String role; // 'user' | 'assistant' | 'system'
  final String text;
  const _Bubble({required this.role, required this.text});
}

class _MessageBubble extends StatelessWidget {
  final _Bubble b;
  const _MessageBubble({required this.b});
  @override
  Widget build(BuildContext context) {
    final isUser = b.role == 'user';
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = switch (b.role) {
      'user' => Theme.of(context).colorScheme.primaryContainer,
      'assistant' => Theme.of(context).colorScheme.secondaryContainer,
      'system' => Theme.of(context).colorScheme.tertiaryContainer,
      'tool' => Theme.of(context).colorScheme.errorContainer,
      _ => Theme.of(context).colorScheme.surface,
    };
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 900),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Text(b.text),
        ),
      ],
    );
  }
}
