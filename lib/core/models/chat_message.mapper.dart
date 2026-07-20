// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'chat_message.dart';

/// @nodoc
class ChatMessageMapper extends ClassMapperBase<ChatMessage> {
  ChatMessageMapper._();

  static ChatMessageMapper? _instance;
  static ChatMessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatMessageMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ChatMessage';

  static String _$role(ChatMessage v) => v.role;
  static const Field<ChatMessage, String> _f$role = Field('role', _$role);
  static String _$content(ChatMessage v) => v.content;
  static const Field<ChatMessage, String> _f$content = Field(
    'content',
    _$content,
  );
  static String _$reasoningContent(ChatMessage v) => v.reasoningContent;
  static const Field<ChatMessage, String> _f$reasoningContent = Field(
    'reasoningContent',
    _$reasoningContent,
    key: r'reasoning_content',
    opt: true,
    def: '',
  );
  static String _$toolCallId(ChatMessage v) => v.toolCallId;
  static const Field<ChatMessage, String> _f$toolCallId = Field(
    'toolCallId',
    _$toolCallId,
    key: r'tool_call_id',
    opt: true,
    def: '',
  );
  static List<Map<String, dynamic>> _$toolCalls(ChatMessage v) => v.toolCalls;
  static const Field<ChatMessage, List<Map<String, dynamic>>> _f$toolCalls =
      Field(
        'toolCalls',
        _$toolCalls,
        key: r'tool_calls',
        opt: true,
        def: const [],
      );

  @override
  final MappableFields<ChatMessage> fields = const {
    #role: _f$role,
    #content: _f$content,
    #reasoningContent: _f$reasoningContent,
    #toolCallId: _f$toolCallId,
    #toolCalls: _f$toolCalls,
  };

  @override
  final MappingHook hook = const JsonModelHook(
    omitEmpty: {'tool_calls'},
    omitEmptyStrings: {'reasoning_content', 'tool_call_id'},
  );
  static ChatMessage _instantiate(DecodingData data) {
    return ChatMessage(
      role: data.dec(_f$role),
      content: data.dec(_f$content),
      reasoningContent: data.dec(_f$reasoningContent),
      toolCallId: data.dec(_f$toolCallId),
      toolCalls: data.dec(_f$toolCalls),
    );
  }

  @override
  final Function instantiate = _instantiate;
}

/// @nodoc
mixin ChatMessageMappable {
  String toJson() {
    return ChatMessageMapper.ensureInitialized().encodeJson<ChatMessage>(
      this as ChatMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return ChatMessageMapper.ensureInitialized().encodeMap<ChatMessage>(
      this as ChatMessage,
    );
  }
}

