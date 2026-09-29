part of 'chat_controller.dart';

class _SlashCommand {
  final String name;
  final String argument;
  final String raw;

  const _SlashCommand({
    required this.name,
    required this.argument,
    required this.raw,
  });
}

class _PendingScopeMove {
  const _PendingScopeMove({
    required this.previousScopeId,
    required this.savedChatId,
    required this.workspace,
    required this.activeTaskId,
    required this.activeProjectId,
  });

  final String previousScopeId;
  final String savedChatId;
  final WorkspaceAttachment? workspace;
  final String? activeTaskId;
  final String? activeProjectId;
}
