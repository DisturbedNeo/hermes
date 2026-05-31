import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/sentinel.dart';

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
  final int? summarySchemaVersion;

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
    this.summarySchemaVersion,
  });

  Bubble copyWith({
    String? id,
    MessageRole? role,
    String? text,
    String? reasoning,
    Map<int, BubbleToolCall>? tools,
    Object? createdAt = kSentinel,
    bool? omittedFromModelPayload,
    Object? summaryId = kSentinel,
    bool? isSummaryMemory,
    Object? summarySchemaVersion = kSentinel,
  }) {
    return Bubble(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      tools: tools ?? this.tools,
      createdAt: identical(createdAt, kSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      omittedFromModelPayload:
          omittedFromModelPayload ?? this.omittedFromModelPayload,
      summaryId: identical(summaryId, kSentinel)
          ? this.summaryId
          : summaryId as String?,
      isSummaryMemory: isSummaryMemory ?? this.isSummaryMemory,
      summarySchemaVersion: identical(summarySchemaVersion, kSentinel)
          ? this.summarySchemaVersion
          : summarySchemaVersion as int?,
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
