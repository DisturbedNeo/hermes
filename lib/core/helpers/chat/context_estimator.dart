import 'dart:convert';

import 'package:hermes/core/models/chat_message.dart';

class ContextEstimator {
  const ContextEstimator._();

  static int estimateChatCompletionRequest({
    required List<ChatMessage> messages,
    Map<String, dynamic> extraParams = const {},
  }) {
    if (messages.isEmpty && extraParams.isEmpty) return 0;

    final payload = <String, dynamic>{
      'messages': messages.map((m) => m.toJson()).toList(),
      if (extraParams.isNotEmpty) ...extraParams,
    };

    return estimateText(jsonEncode(payload));
  }

  static int estimateText(String text) {
    if (text.isEmpty) return 0;

    return (text.length / 4).ceil();
  }
}
