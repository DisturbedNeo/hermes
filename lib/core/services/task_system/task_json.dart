import 'dart:convert';

class TaskJson {
  const TaskJson._();

  static Map<String, dynamic> parseObject(String rawJson) {
    final parsed = tryParseObject(rawJson);
    if (parsed == null) {
      throw const FormatException('Expected one valid JSON object.');
    }
    return parsed;
  }

  static Map<String, dynamic>? tryParseObject(String raw) {
    final trimmed = _stripCodeFence(raw.trim());
    final direct = _decodeMap(trimmed);
    if (direct != null) return direct;
    final extracted = _extractFirstJsonObject(trimmed);
    if (extracted == null) return null;
    return _decodeMap(extracted);
  }

  static Object decodeJsonOrString(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  static Map<String, dynamic>? _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _stripCodeFence(String value) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? value;
  }

  static String? _extractFirstJsonObject(String value) {
    final start = value.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < value.length; i++) {
      final char = value[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return value.substring(start, i + 1);
      }
    }
    return null;
  }
}
