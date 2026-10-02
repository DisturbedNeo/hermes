import 'package:hermes/core/contracts/model_conversation.dart';

/// Chat/task model state shared by streaming and compaction runtimes.
///
/// This is an application value object, not a persistence DTO or a widget
/// model. Chat presentation may add its own projections around it.
class Bubble {
  final String id;
  final MessageRole role;
  final String text;
  final String reasoning;
  final Map<int, BubbleToolCall> tools;
  final DateTime? createdAt;
  final bool omittedFromModelPayload;
  final String? summaryId;
  final bool isSummaryMemory;

  const Bubble({
    required this.id,
    required this.role,
    required this.text,
    required this.reasoning,
    this.tools = const {},
    this.createdAt,
    this.omittedFromModelPayload = false,
    this.summaryId,
    this.isSummaryMemory = false,
  });

  Bubble copyWith({
    String? id,
    MessageRole? role,
    String? text,
    String? reasoning,
    Map<int, BubbleToolCall>? tools,
    Object? createdAt = _bubbleSentinel,
    bool? omittedFromModelPayload,
    Object? summaryId = _bubbleSentinel,
    bool? isSummaryMemory,
  }) {
    return Bubble(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      tools: tools ?? this.tools,
      createdAt: identical(createdAt, _bubbleSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      omittedFromModelPayload:
          omittedFromModelPayload ?? this.omittedFromModelPayload,
      summaryId: identical(summaryId, _bubbleSentinel)
          ? this.summaryId
          : summaryId as String?,
      isSummaryMemory: isSummaryMemory ?? this.isSummaryMemory,
    );
  }
}

class BubbleToolCall {
  final String? id;
  final String? name;
  final String? arguments;
  final String? result;

  const BubbleToolCall({this.id, this.name, this.arguments, this.result});

  BubbleToolCall copyWith({
    String? id,
    String? name,
    String? arguments,
    String? result,
  }) {
    return BubbleToolCall(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
    );
  }
}

abstract interface class ToolCallerPort {
  Map<int, BubbleToolCall> applyDelta({
    required String messageId,
    required ToolCallDelta delta,
    required Map<int, BubbleToolCall> currentTools,
  });

  void clearForMessage(String messageId);
  void clearAll();
}

/// Focused mutation capability used by model streaming and compaction.
abstract interface class MessageStorePort {
  List<Bubble> get messages;
  Bubble? get currentMessage;
  ToolCallerPort get toolCaller;

  void insertAt(int index, Bubble message);
  bool replaceById(String id, Bubble message);
  void markCoveredBySummary({
    required Iterable<String> messageIds,
    required String summaryId,
  });
  void upsert(Bubble message);
}

const _bubbleSentinel = Object();
