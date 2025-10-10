import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/delete_choice.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/action_spec.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/services/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/chat/message/delete_message_dialog.dart';

class MessageActions extends StatelessWidget {
  final int _maxInline;
  final double _iconSize;
  final EdgeInsetsGeometry _padding;
  final Bubble _message;

  const MessageActions({
    super.key,
    required Bubble message,
    int maxInline = 3,
    double iconSize = 18,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 4),
  }) : _message = message,
       _padding = padding,
       _iconSize = iconSize,
       _maxInline = maxInline;

  List<ActionSpec> _getActionsForRole(
    BuildContext context,
    ChatService chat,
    MessageRole role,
  ) {
    List<ActionSpec> actions = [];
    MediaQueryData mq = MediaQuery.of(context);

    ActionSpec copyText = ActionSpec(
      icon: Icons.copy_rounded,
      tooltip: 'Copy Text',
      onTap: (message) {
        if (chat.isStreaming && chat.messages.last.id == message.id) return;
        Clipboard.setData(ClipboardData(text: message.text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied to clipboard'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadiusGeometry.circular(24),
            ),
            margin: EdgeInsets.only(
              bottom: mq.size.height - 120,
              left: mq.size.width / 4,
              right: mq.size.width / 4,
            ),
          ),
        );
      },
    );

    actions.add(copyText);

    if (role == MessageRole.assistant) {
      ActionSpec regenerate = ActionSpec(
        icon: Icons.replay_rounded,
        tooltip: 'Regenerate',
        isEnabled: !chat.isStreaming,
        onTap: (message) {
          chat.deleteMessages(message.id);
          chat.generateOrContinue();
        },
      );

      actions.add(regenerate);
    }

    if (role == MessageRole.user || role == MessageRole.assistant) {
      ActionSpec deleteMessage = ActionSpec(
        icon: Icons.delete_forever_rounded,
        tooltip: 'Delete',
        isEnabled: !chat.isStreaming,
        onTap: (message) async {
          final choice = await showDialog<DeleteChoice>(
            context: context,
            builder: (_) => DeleteMessageDialog(),
          );

          if (choice == null) return;

          chat.deleteMessages(message.id, deleteChoice: choice);
        },
      );

      actions.add(deleteMessage);
    }

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final chat = serviceProvider.get<ChatService>();

    return AnimatedBuilder(
      animation: chat,
      builder: (_, _) {
        final actions = _getActionsForRole(context, chat, _message.role);

        final inline = actions.take(_maxInline).toList();
        final overflow = actions.skip(_maxInline).toList();

        return Padding(
          padding: _padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final a in inline) _iconButton(context, a),
              if (overflow.isNotEmpty) _overflowButton(context, overflow),
            ],
          ),
        );
      },
    );
  }

  Widget _iconButton(BuildContext context, ActionSpec action) {
    return Tooltip(
      message: action.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: IconButton(
        icon: Icon(action.icon, color: action.iconColor),
        iconSize: _iconSize,
        padding: EdgeInsets.symmetric(horizontal: 2),
        constraints: const BoxConstraints(),
        onPressed: action.isEnabled ? () => action.onTap(_message) : null,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }

  Widget _overflowButton(BuildContext context, List<ActionSpec> overflow) {
    return PopupMenuButton<int>(
      tooltip: 'More',
      itemBuilder: (ctx) => [
        for (int i = 0; i < overflow.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: overflow[i].isEnabled,
            child: Row(
              children: [
                Icon(overflow[i].icon, size: 18, color: overflow[i].iconColor),
                const SizedBox(width: 8),
                Text(overflow[i].tooltip),
              ],
            ),
          ),
      ],
      onSelected: (i) => overflow[i].onTap(_message),
      icon: Icon(
        Icons.more_horiz,
        size: _iconSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      padding: EdgeInsets.zero,
    );
  }
}
