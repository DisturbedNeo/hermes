import 'package:hermes/features/chat/application/contracts/prompt_assembler.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Builds the model-facing system prompt from the immutable prompt snapshot
/// and the current workspace policy. It has no session or persistence state.
class ChatPromptConstructionService {
  const ChatPromptConstructionService({
    this.assembler = const PromptAssembler(),
  });

  static const defaultText = 'You are a helpful assistant.';

  final PromptAssembler assembler;

  String build({
    required SystemPromptSnapshot? snapshot,
    required WorkspaceAttachment? workspace,
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) {
    if (snapshot?.preset != null) {
      final result = assembler.assemble(
        PromptAssemblyRequest(
          preset: snapshot!.preset,
          availableModules: snapshot.modules,
          selectedModuleIds: {
            ...snapshot.selectedModuleIds,
            ...additionalModuleIds,
          }.toList(),
          autoModuleIds: _autoModuleIds(workspace),
          workspaceRootPath: workspace?.rootPath,
          workspaceMissing: workspace?.missing ?? false,
          commandExecutionApproved: workspace?.commandExecutionApproved == true,
          currentUserRequest: currentUserRequest,
        ),
      );
      if (result.text.trim().isNotEmpty) return result.text;
      if (snapshot.text.trim().isNotEmpty) return snapshot.text.trim();
    }

    final base = snapshot?.text.trim().isNotEmpty == true
        ? snapshot!.text.trim()
        : defaultText;
    if (workspace == null) return base;
    if (workspace.missing) {
      return '$base\n\nA workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.';
    }

    final terminalStatus = workspace.commandExecutionApproved
        ? 'enabled for this chat'
        : 'disabled for this chat until the user enables it from the workspace chip';
    return '''
$base

This chat has an attached workspace. The workspace root is:
${workspace.rootPath}

Workspace rules:
- Use workspace tools for file and folder operations.
- Only operate inside the attached workspace and use workspace-relative paths.
- Inspect relevant files before editing them.
- Prefer small, precise changes.
- Explain destructive file operations before performing them.
- Host terminal commands run with the application's host permissions, are not confined to the workspace, and are currently $terminalStatus.
'''
        .trim();
  }

  List<String> _autoModuleIds(WorkspaceAttachment? workspace) {
    if (workspace == null) return const [];
    return workspace.missing
        ? const [BuiltInPromptIds.workspaceMissingModule]
        : const [BuiltInPromptIds.workspaceRulesModule];
  }
}
