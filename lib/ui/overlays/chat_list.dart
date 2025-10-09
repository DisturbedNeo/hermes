import 'package:flutter/material.dart';

class ChatList extends StatelessWidget {
  final void Function(String chatId) onOpenChat;
  final VoidCallback onNewChat;

  const ChatList({super.key, required this.onOpenChat, required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    final chats = [];

    return Column(
      children: [
        ListTile(
          title: const Text('Chats', style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: IconButton(icon: const Icon(Icons.add), onPressed: onNewChat, tooltip: 'New chat'),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = chats[i];
              return ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(c.title),
                onTap: () => onOpenChat(c.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
