import 'package:flutter/material.dart';

class MessageTimestamp extends StatelessWidget {
  final DateTime createdAt;

  const MessageTimestamp({super.key, required this.createdAt});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall;
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.78);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        formatMessageTimestamp(createdAt),
        style: textStyle?.copyWith(color: color),
      ),
    );
  }
}

String formatMessageTimestamp(DateTime dateTime) {
  final local = dateTime.toLocal();
  final day = _twoDigits(local.day);
  final month = _twoDigits(local.month);
  final year = _twoDigits(local.year % 100);
  final hour = _twoDigits(local.hour);
  final minute = _twoDigits(local.minute);

  return '$day/$month/$year $hour:$minute';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
