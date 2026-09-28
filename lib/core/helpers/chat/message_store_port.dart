import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/models/bubble.dart';

/// Shared mutation port used by chat streaming utilities.
///
/// The concrete message store is owned by the chat feature. Keeping this
/// protocol in the shared layer prevents streaming helpers from importing the
/// chat application implementation.
abstract interface class MessageStorePort {
  List<Bubble> get messages;
  Bubble? get currentMessage;
  ToolCaller get toolCaller;

  void insertAt(int index, Bubble message);
  bool replaceById(String id, Bubble message);
  void markCoveredBySummary({
    required Iterable<String> messageIds,
    required String summaryId,
  });
  void upsert(Bubble message);
}
