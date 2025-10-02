import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/ui/chat_list.dart';
import 'package:hermes/ui/chat_view.dart';
import 'package:hermes/ui/settings.dart';

class Chat extends StatefulWidget {
  const Chat({super.key});
  
  @override
  State<StatefulWidget> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final chatId = ValueNotifier<String>('new');
  
  var isChatListOpen = false;
  var isSettingsOpen = false;

  void toggleChatList() {
    setState(() => isChatListOpen = !isChatListOpen);
  }

  void toggleSettings() {
    setState(() => isSettingsOpen = !isSettingsOpen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Chats',
          icon: const Icon(Icons.menu),
          onPressed: () => toggleChatList(),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Model: (unset)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => toggleSettings(),
          ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<String>(
              valueListenable: chatId,
              builder: (_, id, __) => ChatView(chatId: id),
            ),
          ),

          if (isChatListOpen || isSettingsOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() {
                  isChatListOpen = false;
                  isSettingsOpen = false;
                }),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                  child: Container(color: Colors.black.withValues(alpha: 0.1)),
                ),
              ),
            ),
          ],

          // Left overlay: Chats
          _SideSheet(
            side: AxisDirection.left,
            open: isChatListOpen,
            width: 360,
            child: ChatList(
              onOpenChat: (id) {
                chatId.value = id;
                setState(() => isChatListOpen = false);
              },
              onNewChat: () {
                final id = uuid.v7();
                chatId.value = id;
                setState(() => isChatListOpen = false);
              },
            ),
          ),

          // Right overlay: Settings
          _SideSheet(
            side: AxisDirection.right,
            open: isSettingsOpen,
            width: 420,
            child: const Settings(),
          ),
        ],
      ),
    );
  }
}

class _SideSheet extends StatelessWidget {
  final AxisDirection side; // left or right
  final bool open;
  final double width;
  final Widget child;

  const _SideSheet({
    required this.side,
    required this.open,
    required this.width,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final fromLeft = side == AxisDirection.left;

    return Align(
      alignment: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: IgnorePointer(
        // prevent interacting when closed (but still let it animate)
        ignoring: !open,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          // slide fully off-screen horizontally when closed
          offset: open
              ? Offset.zero
              : (fromLeft ? const Offset(-1, 0) : const Offset(1, 0)),
          child: Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(width: width, height: double.infinity, child: child),
          ),
        ),
      ),
    );
  }
}
