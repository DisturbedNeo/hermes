import 'package:hermes/core/enums/message_role.dart';

class Bubble {
  final String id;
  final MessageRole role;
  final String text;
  final String reasoning;
  final Map<int, BubbleToolCall> tools;
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
    bool? omittedFromModelPayload,
    Object? summaryId = _sentinel,
    bool? isSummaryMemory,
    Object? summarySchemaVersion = _sentinel,
  }) {
    return Bubble(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      tools: tools ?? this.tools,
      omittedFromModelPayload:
          omittedFromModelPayload ?? this.omittedFromModelPayload,
      summaryId: identical(summaryId, _sentinel)
          ? this.summaryId
          : summaryId as String?,
      isSummaryMemory: isSummaryMemory ?? this.isSummaryMemory,
      summarySchemaVersion: identical(summarySchemaVersion, _sentinel)
          ? this.summarySchemaVersion
          : summarySchemaVersion as int?,
    );
  }
}

const Object _sentinel = Object();

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
