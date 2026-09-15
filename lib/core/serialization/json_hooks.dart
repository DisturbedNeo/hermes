import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/json_parsing.dart';

/// Normalises boundary payload keys before mapping a model and removes
/// explicitly configured optional values after encoding it.
class JsonModelHook extends MappingHook {
  const JsonModelHook({
    this.omitEmpty = const {},
    this.omitEmptyStrings = const {},
    this.removeKeys = const {},
    this.outputOverrides = const {},
  });

  final Set<String> omitEmpty;
  final Set<String> omitEmptyStrings;
  final Set<String> removeKeys;
  final Map<String, Object?> outputOverrides;

  @override
  Object? beforeDecode(Object? value) {
    if (value is! Map) return value;
    final source = Map<String, dynamic>.from(value);
    final normalized = Map<String, dynamic>.from(source);

    for (final entry in source.entries) {
      if (!entry.key.contains('_')) continue;
      normalized.putIfAbsent(_snakeToCamel(entry.key), () => entry.value);
    }
    return normalized;
  }

  @override
  Object? afterEncode(Object? value) {
    if (value is! Map) return value;
    final encoded = Map<String, dynamic>.from(value);
    encoded.removeWhere((key, value) {
      if (removeKeys.contains(key)) return true;
      if (omitEmpty.contains(key) &&
          ((value is Iterable && value.isEmpty) ||
              (value is Map && value.isEmpty))) {
        return true;
      }
      return omitEmptyStrings.contains(key) && value is String && value.isEmpty;
    });
    encoded.addAll(outputOverrides);
    return encoded;
  }

  static String _snakeToCamel(String value) {
    final parts = value.split('_');
    if (parts.length == 1) return value;
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return '';
          return '${part[0].toUpperCase()}${part.substring(1)}';
        }).join();
  }
}

class JsonStringHook extends MappingHook {
  const JsonStringHook({this.fallback = ''});

  final String fallback;

  @override
  Object? beforeDecode(Object? value) => jsonString(value, fallback: fallback);
}

class JsonNullableStringHook extends MappingHook {
  const JsonNullableStringHook();

  @override
  Object? beforeDecode(Object? value) => jsonNullableString(value);
}

class JsonStringListHook extends MappingHook {
  const JsonStringListHook();

  @override
  Object? beforeDecode(Object? value) => jsonStringList(value);
}

class JsonObjectListHook extends MappingHook {
  const JsonObjectListHook();

  @override
  Object? beforeDecode(Object? value) => jsonMapList(value);
}

class JsonBoolHook extends MappingHook {
  const JsonBoolHook({this.fallback = false});

  final bool fallback;

  @override
  Object? beforeDecode(Object? value) => jsonBool(value, fallback: fallback);
}

class JsonIntHook extends MappingHook {
  const JsonIntHook({this.fallback = 0, this.min, this.max});

  final int fallback;
  final int? min;
  final int? max;

  @override
  Object? beforeDecode(Object? value) {
    var parsed = jsonInt(value, fallback: fallback);
    if (min != null && parsed < min!) parsed = min!;
    if (max != null && parsed > max!) parsed = max!;
    return parsed;
  }
}

class JsonDoubleHook extends MappingHook {
  const JsonDoubleHook({this.fallback = 0});

  final double fallback;

  @override
  Object? beforeDecode(Object? value) => jsonDouble(value, fallback: fallback);
}

class JsonMapValueHook extends MappingHook {
  const JsonMapValueHook();

  @override
  Object? beforeDecode(Object? value) => jsonMap(value);
}

class JsonDateHook extends MappingHook {
  const JsonDateHook();

  @override
  Object? beforeDecode(Object? value) =>
      jsonNullableDate(value) ?? DateTime.now();
}

class JsonNullableDateHook extends MappingHook {
  const JsonNullableDateHook();

  @override
  Object? beforeDecode(Object? value) => jsonNullableDate(value);
}

class EpochDateHook extends MappingHook {
  const EpochDateHook({this.fallbackNow = false});

  final bool fallbackNow;

  @override
  Object? beforeDecode(Object? value) =>
      jsonNullableDate(value) ?? (fallbackNow ? DateTime.now() : null);

  @override
  Object? beforeEncode(Object? value) =>
      value is DateTime ? value.millisecondsSinceEpoch : value;
}
