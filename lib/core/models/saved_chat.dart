import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';

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
