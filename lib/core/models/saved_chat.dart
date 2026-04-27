import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';

class SavedChat {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final ModelConfigurationSnapshot? modelSnapshot;

  const SavedChat({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
    this.modelSnapshot,
  });
}

class SavedChatSnapshot {
  final SavedChat chat;
  final List<Bubble> messages;

  const SavedChatSnapshot({required this.chat, required this.messages});
}
