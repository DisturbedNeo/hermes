import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

class SavedChat {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final ModelConfigurationSnapshot? modelSnapshot;
  final WorkspaceAttachment? workspace;
  final SystemPromptSnapshot? systemPromptSnapshot;

  const SavedChat({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
    this.modelSnapshot,
    this.workspace,
    this.systemPromptSnapshot,
  });
}

class SavedChatSnapshot {
  final SavedChat chat;
  final List<Bubble> messages;

  const SavedChatSnapshot({required this.chat, required this.messages});
}
