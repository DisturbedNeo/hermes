import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/services/chat/chat_service.dart';

class WorkspaceBar extends StatelessWidget {
  final ChatService chat;
  final VoidCallback onOpenWorkspace;

  const WorkspaceBar({
    super.key,
    required this.chat,
    required this.onOpenWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    final workspace = chat.workspace;
    if (workspace == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final missing = workspace.missing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth && constraints.maxWidth < 320;

        return Material(
          color: missing
              ? scheme.errorContainer.withValues(alpha: 0.7)
              : scheme.secondaryContainer.withValues(alpha: 0.7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  missing
                      ? Icons.folder_off_outlined
                      : Icons.folder_open_outlined,
                  size: 18,
                  color: missing
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Tooltip(
                    message: workspace.rootPath,
                    child: AccessibleWidget(
                      label: missing
                          ? 'Workspace ${workspace.displayName} is missing'
                          : 'Active workspace: ${workspace.displayName}',
                      value: workspace.rootPath,
                      child: Text(
                        missing
                            ? '${workspace.displayName} missing'
                            : workspace.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: missing
                              ? scheme.onErrorContainer
                              : scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (compact)
                  _WorkspaceActionsMenu(
                    chat: chat,
                    missing: missing,
                    onOpenWorkspace: onOpenWorkspace,
                  )
                else ...[
                  if (!missing)
                    AccessibleWidget(
                      label:
                          'Terminal execution${workspace.commandExecutionApproved ? '' : ' not'} approved',
                      selected: workspace.commandExecutionApproved,

                      child: FilterChip(
                        label: const Text('Terminal'),
                        avatar: const Icon(Icons.terminal, size: 16),
                        selected: workspace.commandExecutionApproved,
                        onSelected: chat.chatStream.isStreaming
                            ? null
                            : chat.setCommandExecutionApproved,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  AccessibleWidget(
                    label: 'Change workspace',
                    isButton: true,
                    child: IconButton(
                      tooltip: 'Change Workspace',
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: onOpenWorkspace,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  AccessibleWidget(
                    label: 'Detach workspace',
                    isButton: true,
                    enabled: !chat.chatStream.isStreaming,
                    child: IconButton(
                      tooltip: 'Detach workspace',
                      icon: const Icon(Icons.close),
                      onPressed: chat.chatStream.isStreaming
                          ? null
                          : chat.detachWorkspace,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceActionsMenu extends StatelessWidget {
  final ChatService chat;
  final bool missing;
  final VoidCallback onOpenWorkspace;

  const _WorkspaceActionsMenu({
    required this.chat,
    required this.missing,
    required this.onOpenWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    return AccessibleWidget(
      label: 'Workspace actions',
      isButton: true,
      child: PopupMenuButton<_WorkspaceAction>(
        tooltip: 'Workspace actions',
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case _WorkspaceAction.toggleTerminal:
              final workspace = chat.workspace;
              if (workspace == null || workspace.missing) return;
              chat.setCommandExecutionApproved(
                !workspace.commandExecutionApproved,
              );
              break;
            case _WorkspaceAction.change:
              onOpenWorkspace();
              break;
            case _WorkspaceAction.detach:
              chat.detachWorkspace();
              break;
          }
        },
        itemBuilder: (_) => [
          if (!missing)
            CheckedPopupMenuItem(
              value: _WorkspaceAction.toggleTerminal,
              checked: chat.workspace?.commandExecutionApproved ?? false,
              enabled: !chat.chatStream.isStreaming,
              child: const Text('Terminal execution'),
            ),
          const PopupMenuItem(
            value: _WorkspaceAction.change,
            child: Text('Change workspace'),
          ),
          PopupMenuItem(
            value: _WorkspaceAction.detach,
            enabled: !chat.chatStream.isStreaming,
            child: const Text('Detach workspace'),
          ),
        ],
      ),
    );
  }
}

enum _WorkspaceAction { toggleTerminal, change, detach }
