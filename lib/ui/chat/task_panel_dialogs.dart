import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hermes/core/services/chat/chat_service.dart';

/// Dialog for editing a project's JSON plan.
///
/// Shows a [TextField] pre-filled with the current project JSON,
/// validates it on save, and calls [onSave] if valid.
class EditProjectDialog extends StatefulWidget {
  final String initialJson;
  final Future<void> Function(String json) onSave;

  const EditProjectDialog({
    super.key,
    required this.initialJson,
    required this.onSave,
  });

  /// Shows the edit-project dialog and returns whether the user saved.
  static Future<bool> show(BuildContext context, {
    required String initialJson,
    required Future<void> Function(String json) onSave,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => EditProjectDialog(
        initialJson: initialJson,
        onSave: onSave,
      ),
    ).then((result) => result ?? false);
  }

  @override
  State<EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends State<EditProjectDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialJson);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      jsonDecode(_controller.text);
      await widget.onSave(_controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Project'),
      content: SizedBox(
        width: 820,
        child: TextField(
          controller: _controller,
          minLines: 16,
          maxLines: 22,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
          onPressed: _saving ? null : _handleSave,
        ),
      ],
    );
  }
}

/// Dialog for editing a task's JSON plan.
///
/// Shows a [TextField] pre-filled with the current task JSON,
/// validates it on save, and calls [onSave] if valid.
class EditPlanDialog extends StatefulWidget {
  final String initialJson;
  final Future<void> Function(String json) onSave;

  const EditPlanDialog({
    super.key,
    required this.initialJson,
    required this.onSave,
  });

  /// Shows the edit-plan dialog and returns whether the user saved.
  static Future<bool> show(BuildContext context, {
    required String initialJson,
    required Future<void> Function(String json) onSave,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => EditPlanDialog(
        initialJson: initialJson,
        onSave: onSave,
      ),
    ).then((result) => result ?? false);
  }

  @override
  State<EditPlanDialog> createState() => _EditPlanDialogState();
}

class _EditPlanDialogState extends State<EditPlanDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialJson);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      jsonDecode(_controller.text);
      await widget.onSave(_controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Plan'),
      content: SizedBox(
        width: 820,
        child: TextField(
          controller: _controller,
          minLines: 16,
          maxLines: 22,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save'),
          onPressed: _saving ? null : _handleSave,
        ),
      ],
    );
  }
}

/// Dialog for viewing an artifact's file content.
class ArtifactViewerDialog extends StatefulWidget {
  final String path;
  final ChatService chat;
  final void Function(String error)? onError;

  const ArtifactViewerDialog({
    super.key,
    required this.path,
    required this.chat,
    this.onError,
  });

  /// Shows the artifact viewer dialog.
  static Future<void> show(BuildContext context, {
    required String path,
    required ChatService chat,
    void Function(String error)? onError,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => ArtifactViewerDialog(
        path: path,
        chat: chat,
        onError: onError,
      ),
    );
  }

  @override
  State<ArtifactViewerDialog> createState() => _ArtifactViewerDialogState();
}

class _ArtifactViewerDialogState extends State<ArtifactViewerDialog> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final content = await widget.chat.readTaskArtifact(widget.path);
      if (mounted) setState(() => _content = content);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        widget.onError?.call(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.path),
      content: _content != null
          ? SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: SelectableText(
                  _content!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            )
          : _error != null
              ? Text('Failed to load: $_error')
              : const Center(child: CircularProgressIndicator()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
