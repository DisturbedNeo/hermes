import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkspacePanel extends StatefulWidget {
  final ChatService? chat;
  final FutureOr<void> Function() onSelectWorkspace;

  const WorkspacePanel({
    super.key,
    required this.chat,
    required this.onSelectWorkspace,
  });

  @override
  State<WorkspacePanel> createState() => _WorkspacePanelState();
}

class _WorkspacePanelState extends State<WorkspacePanel> {
  final WorkspaceService _workspaceService = serviceProvider
      .get<WorkspaceService>();

  List<WorkspaceAttachment> _recent = const [];
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _workspaceService.addListener(_reload);
    widget.chat?.addListener(_reload);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WorkspacePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat == widget.chat) return;
    oldWidget.chat?.removeListener(_reload);
    widget.chat?.addListener(_reload);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.chat?.removeListener(_reload);
    _workspaceService.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    unawaited(_load(showLoading: false));
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final recent = await _workspaceService.recentWorkspaces();
      final workspace = widget.chat?.workspace;
      final entries = workspace == null || workspace.missing
          ? const <Map<String, dynamic>>[]
          : await _workspaceService.sandbox.listDirectory(
              workspace.rootPath,
              '.',
            );
      if (!mounted) return;
      setState(() {
        _recent = recent;
        _entries = entries;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _attachRecent(WorkspaceAttachment workspace) async {
    try {
      await widget.chat?.attachWorkspace(workspace.rootPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open workspace: $e')));
    }
  }

  Future<void> _openInExplorer(String path) async {
    final uri = Uri.directory(path);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open file explorer')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final workspace = chat?.workspace;
    final canMutate = !(chat?.chatStream.isStreaming ?? false);

    return Column(
      children: [
        ListTile(
          title: const Text(
            'Workspace',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: workspace == null
              ? const Text('No folder attached')
              : Text(
                  workspace.rootPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: IconButton(
            tooltip: 'Open in file explorer',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: canMutate && workspace != null
                ? () => _openInExplorer(workspace.rootPath)
                : null,
          ),
        ),
        if (workspace != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Change'),
                    onPressed: canMutate
                        ? () => widget.onSelectWorkspace()
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.link_off),
                    label: const Text('Detach'),
                    onPressed: canMutate ? chat?.detachWorkspace : null,
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _buildBody(canMutate)),
      ],
    );
  }

  Widget _buildBody(bool canMutate) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load workspace: $_error'),
        ),
      );
    }

    return ListView(
      children: [
        if (_entries.isNotEmpty) ...[
          const _SectionHeader('Files'),
          for (final entry in _entries.take(80))
            ListTile(
              dense: true,
              leading: Icon(
                entry['type'] == 'directory'
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
              ),
              title: Text(
                entry['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(entry['path'] as String),
            ),
        ],
        if (_recent.isNotEmpty) ...[
          const _SectionHeader('Recent'),
          for (final workspace in _recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                workspace.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                workspace.rootPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: canMutate
                  ? () => unawaited(_attachRecent(workspace))
                  : null,
            ),
        ],
        if (_entries.isEmpty && _recent.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No recent workspaces')),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
