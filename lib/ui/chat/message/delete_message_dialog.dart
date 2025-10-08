import 'package:flutter/material.dart';
import 'package:hermes/core/enums/delete_choice.dart';

class DeleteMessageDialog extends StatefulWidget {
  const DeleteMessageDialog({ super.key });

  @override
  State<StatefulWidget> createState() => _DeleteMessageDialogState();
}

class _DeleteMessageDialogState extends State<DeleteMessageDialog> {
  DeleteChoice choice = DeleteChoice.thisOnly;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Message?'),
      content: RadioGroup<DeleteChoice>(
        groupValue: choice,
        onChanged: (value) {
          if (value != null) {
            setState(() => choice = value);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<DeleteChoice>(
              value: DeleteChoice.thisOnly,
              selected: choice == DeleteChoice.thisOnly,
              title: const Text('Just this message'),
            ),
            RadioListTile<DeleteChoice>(
              value: DeleteChoice.includeSubsequent,
              selected: choice == DeleteChoice.includeSubsequent,
              title: const Text('Include subsequent messages'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<DeleteChoice>(null),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          onPressed: () => Navigator.of(context).pop<DeleteChoice>(choice),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
