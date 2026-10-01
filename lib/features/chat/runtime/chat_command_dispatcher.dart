/// Typed representation of a chat slash command.
class ChatSlashCommand {
  const ChatSlashCommand({
    required this.name,
    required this.argument,
    required this.raw,
  });

  final String name;
  final String argument;
  final String raw;
}

/// Parses and dispatches chat commands without owning session state.
class ChatCommandDispatcher {
  const ChatCommandDispatcher();

  ChatSlashCommand? parse(String text) {
    final match = RegExp(
      r'^/(continue-project|project|task|plan|refine|continue)\b(.*)$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return ChatSlashCommand(
      name: match.group(1)!.toLowerCase(),
      argument: match.group(2)?.trim() ?? '',
      raw: text.trim(),
    );
  }

  Future<void> dispatch(
    ChatSlashCommand command, {
    required void Function(String raw, String message) insertUserAndAssistant,
    required Future<void> Function(String prompt, {required bool runFirstPhase})
    startTask,
    required Future<void> Function(
      String prompt, {
      required bool runAfterCreation,
    })
    startProject,
    required Future<void> Function(ChatSlashCommand command) refine,
    required Future<void> Function(String raw) continueTask,
    required Future<void> Function(String raw) continueProject,
  }) async {
    switch (command.name) {
      case 'task':
        if (command.argument.trim().isEmpty) {
          insertUserAndAssistant(
            command.raw,
            'Usage: `/task <request>` creates and runs a structured task.',
          );
          return;
        }
        await startTask(command.argument, runFirstPhase: true);
      case 'plan':
        if (command.argument.trim().isEmpty) {
          insertUserAndAssistant(
            command.raw,
            'Usage: `/plan <request>` creates a task plan without running it.',
          );
          return;
        }
        await startTask(command.argument, runFirstPhase: false);
      case 'refine':
        await refine(command);
      case 'continue':
        await continueTask(command.raw);
      case 'project':
        if (command.argument.trim().isEmpty) {
          insertUserAndAssistant(
            command.raw,
            'Usage: `/project <goal>` creates and runs a supervised project.',
          );
          return;
        }
        await startProject(command.argument, runAfterCreation: true);
      case 'continue-project':
        await continueProject(command.raw);
      default:
        throw StateError('Unknown slash command: ${command.name}');
    }
  }
}
