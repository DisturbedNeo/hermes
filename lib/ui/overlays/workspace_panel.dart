import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/common/state_display.dart';
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
  static const double _shortPanelHeight = 180;
  static const double _compactBodyHeight = 160;
  static const double _compactActionWidth = 240;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final compactHeight =
            !boundedHeight || constraints.maxHeight < _shortPanelHeight;
        final body = _buildBody(canMutate);
        final content = Column(
          mainAxisSize: compactHeight ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _buildHeader(workspace, canMutate),
            _buildActions(chat, workspace, canMutate),
            const Divider(height: 1),
            if (compactHeight)
              SizedBox(height: _compactBodyHeight, child: body)
            else
              Expanded(child: body),
          ],
        );

        if (!compactHeight) return content;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: boundedHeight ? constraints.maxHeight : 0,
            ),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildHeader(WorkspaceAttachment? workspace, bool canMutate) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth && constraints.maxWidth < 220;
        return ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
          title: const Text(
            'Workspace',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: workspace == null
              ? const Text(
                  'No folder attached',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  workspace.rootPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: compact
              ? null
              : IconButton(
                  tooltip: 'Open in file explorer',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: canMutate && workspace != null
                      ? () => _openInExplorer(workspace.rootPath)
                      : null,
                ),
        );
      },
    );
  }

  Widget _buildActions(
    ChatService? chat,
    WorkspaceAttachment? workspace,
    bool canMutate,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.hasBoundedWidth &&
              constraints.maxWidth < _compactActionWidth;

          if (compact) {
            return Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.outlined(
                      tooltip: workspace == null
                          ? 'Attach workspace'
                          : 'Change workspace',
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: canMutate
                          ? () => widget.onSelectWorkspace()
                          : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Detach workspace',
                      icon: const Icon(Icons.link_off),
                      onPressed: workspace != null && canMutate
                          ? chat?.detachWorkspace
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }

          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(workspace == null ? 'Attach' : 'Change'),
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
                  onPressed: workspace != null && canMutate
                      ? chat?.detachWorkspace
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(bool canMutate) {
    final hasData =
        _entries.isNotEmpty ||
        (widget.chat?.availableProjects.isNotEmpty ?? false) ||
        (widget.chat?.availableTasks.isNotEmpty ?? false) ||
        _recent.isNotEmpty;

    return StateDisplay(
      state: _loading
          ? DisplayState.loading
          : (_error != null
                ? DisplayState.error
                : (hasData ? DisplayState.content : DisplayState.empty)),
      content: ListView(
        children: [
          if (_entries.isNotEmpty) ...[
            const _SectionHeader(label: 'Files'),
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
          if ((widget.chat?.availableProjects.isNotEmpty ?? false)) ...[
            const _SectionHeader(label: 'Projects In This Chat'),
            for (final project in widget.chat!.availableProjects.take(12))
              ListTile(
                dense: true,
                leading: const Icon(Icons.rocket_launch_outlined),
                title: Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${project.status.wire} - ${project.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: canMutate
                    ? () => unawaited(widget.chat?.loadProject(project.id))
                    : null,
              ),
          ],
          if ((widget.chat?.availableTasks.isNotEmpty ?? false)) ...[
            const _SectionHeader(label: 'Tasks In This Chat'),
            for (final task in widget.chat!.availableTasks.take(12))
              ListTile(
                dense: true,
                leading: Icon(_iconForTaskStatus(task.status)),
                title: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${task.status.wire} - ${task.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: canMutate
                    ? () => unawaited(widget.chat?.loadTask(task.id))
                    : null,
              ),
          ],
          if (_recent.isNotEmpty) ...[
            const _SectionHeader(label: 'Recent'),
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
        ],
      ),
      errorMessage: 'Failed to load workspace: $_error',
      emptyMessage: 'No recent workspaces',
      onRetry: _error != null ? () => _load() : null,
    );
  }
}

IconData _iconForTaskStatus(TaskStatus status) => switch (status) {
  TaskStatus.completed => Icons.check_circle_outline,
  TaskStatus.running => Icons.sync,
  TaskStatus.paused => Icons.pause_circle_outline,
  TaskStatus.blocked => Icons.block,
  TaskStatus.failed => Icons.error_outline,
  TaskStatus.cancelled => Icons.cancel_outlined,
  TaskStatus.draft || TaskStatus.planned => Icons.account_tree_outlined,
};

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

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
