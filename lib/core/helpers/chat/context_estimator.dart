import 'dart:convert';

import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/serialization/model_json.dart';

class ContextEstimator {
  const ContextEstimator._();

  static int estimateChatCompletionRequest({
    required List<ChatMessage> messages,
    Map<String, dynamic> extraParams = const {},
  }) {
    if (messages.isEmpty && extraParams.isEmpty) return 0;

    final payload = <String, dynamic>{
      'messages': messages.map(ModelJson.encode).toList(),
      if (extraParams.isNotEmpty) ...extraParams,
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
