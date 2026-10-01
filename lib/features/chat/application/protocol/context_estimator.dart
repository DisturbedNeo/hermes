import 'dart:convert';

import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/chat/application/protocol/chat_message_wire_adapter.dart';
import 'package:hermes/features/model/application/model_request.dart';

class ContextEstimator {
  const ContextEstimator._();

  static const _wireAdapter = ChatMessageWireAdapter();

  static int estimateChatCompletionRequest({
    required List<ChatMessage> messages,
    ModelRequestOptions extraParams = const ModelRequestOptions.empty(),
  }) {
    if (messages.isEmpty && extraParams.isEmpty) return 0;

    final payload = <String, dynamic>{
      'messages': messages.map(_wireAdapter.encode).toList(),
      if (extraParams.addGenerationPrompt != null)
        'add_generation_prompt': extraParams.addGenerationPrompt,
      if (extraParams.tools.isNotEmpty)
        'tools': [for (final tool in extraParams.tools) tool.id],
      if (extraParams.toolChoice != null) 'tool_choice': extraParams.toolChoice,
      if (extraParams.maxTokens != null) 'max_tokens': extraParams.maxTokens,
      if (extraParams.temperature != null)
        'temperature': extraParams.temperature,
      if (extraParams.streamOptions != null)
        'stream_options': {
          for (final option in extraParams.streamOptions!.custom)
            option.name: option.value,
        },
      if (extraParams.chatTemplate != null)
        'chat_template_kwargs': {
          if (extraParams.chatTemplate!.enableThinking != null)
            'enable_thinking': extraParams.chatTemplate!.enableThinking,
          if (extraParams.chatTemplate!.reasoningBudget != null)
            'reasoning_budget': extraParams.chatTemplate!.reasoningBudget,
        },
    };

    return estimateText(jsonEncode(payload));
  }

  static int estimateText(String text) {
    if (text.isEmpty) return 0;
    var asciiBytes = 0;
    var nonAsciiBytes = 0;
    for (final byte in utf8.encode(text)) {
      if (byte < 0x80) {
        asciiBytes++;
      } else {
        nonAsciiBytes++;
      }
    }
    return (asciiBytes / 3).ceil() + (nonAsciiBytes / 2).ceil();
  }
}
