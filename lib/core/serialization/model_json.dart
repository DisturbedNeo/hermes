import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/serialization/mappers.init.dart';

/// Generic JSON entry point for all typed application DTOs.
abstract final class ModelJson {
  static bool _initialized = false;

  static T decode<T>(Object? value) {
    _ensureInitialized();
    final normalized = value is Map && value is! Map<String, dynamic>
        ? Map<String, dynamic>.from(value)
        : value;
    return MapperContainer.globals.fromValue<T>(normalized);
  }

  static Map<String, dynamic> encode<T extends Object>(T value) {
    _ensureInitialized();
    return MapperContainer.globals.toMap<T>(value);
  }

  static T decodeString<T>(String source) {
    _ensureInitialized();
    return MapperContainer.globals.fromJson<T>(source);
  }

  static String encodeString<T extends Object>(T value, {String? indent}) {
    final encoded = encode(value);
    return indent == null
        ? jsonEncode(encoded)
        : JsonEncoder.withIndent(indent).convert(encoded);
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    DateTimeMapper.encodingMode = DateTimeEncoding.iso8601String;
    initializeMappers();
    _initialized = true;
  }
}
