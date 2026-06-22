/// Consolidated JSON parsing helpers used across models and services.
///
/// Each function handles type coercion, nullability, and empty-string edge
/// cases consistently. Where the original code had slight variations (e.g.
/// [_stringList] in task.dart handled Map items with a `question` key), this
/// module preserves that richer behavior as the default.
library;

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

/// Parses a non-nullable string, returning [fallback] when the value is null
/// or whitespace-only.
String jsonString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final string = value.toString();
  return string.trim().isEmpty ? fallback : string;
}

/// Parses a nullable string. Returns `null` when the value is null or
/// whitespace-only.
String? jsonNullableString(Object? value) {
  if (value == null) return null;
  final string = value.toString().trim();
  return string.isEmpty ? null : string;
}

/// Parses a list of strings. Handles:
/// - `List<dynamic>` where each item is converted via [toString]
/// - `List<Map<String, dynamic>>` where items with a `question` key yield
///   that value's string representation (for compatibility with task models)
/// - A single non-empty string (wrapped in a one-element list)
/// - Empty or non-list values return an empty list.
List<String> jsonStringList(Object? value) {
  if (value is List) {
    return value
        .map((item) {
          if (item is Map && item['question'] != null) {
            return item['question'].toString();
          }
          return item.toString();
        })
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

// ---------------------------------------------------------------------------
// Numeric helpers
// ---------------------------------------------------------------------------

/// Parses a boolean. Accepts `bool`, numeric (`0`/non-zero), and string
/// representations (`'true'/'false'`, `'yes'/'no'`, `'1'/'0'`).
bool jsonBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalised = value.trim().toLowerCase();
    if (normalised == 'true' || normalised == 'yes' || normalised == '1') {
      return true;
    }
    if (normalised == 'false' || normalised == 'no' || normalised == '0') {
      return false;
    }
  }
  return fallback;
}

/// Parses an integer. Accepts `int`, `num` (converted), or a parseable string.
int jsonInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

/// Parses a double. Accepts `double`, `num` (converted), or a parseable string.
double jsonDouble(Object? value, {double fallback = 0.0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

// ---------------------------------------------------------------------------
// DateTime helpers
// ---------------------------------------------------------------------------

/// Parses a non-nullable [DateTime]. Accepts [DateTime], epoch milliseconds,
/// or ISO-8601 strings. Returns [fallback] on failure.
DateTime jsonDate(Object? value, {required DateTime fallback}) {
  return jsonNullableDate(value) ?? fallback;
}

/// Parses a nullable [DateTime]. Returns `null` when the value is null.
DateTime? jsonNullableDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value.toString());
}

// ---------------------------------------------------------------------------
// Map helpers
// ---------------------------------------------------------------------------

/// Safely casts a value to `Map<String, dynamic>`. Returns an empty map when
/// the value is not a [Map].
Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

/// Parses a list of maps. Filters out non-Map items and casts each to
/// `Map<String, dynamic>`. Returns an empty list when the value is not a List.
List<Map<String, dynamic>> jsonMapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
