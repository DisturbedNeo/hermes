import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';

/// Generic JSON entry point for all typed application DTOs.
///
/// Mapper registration is supplied by the composition root. Keeping the
/// callback here as a small generic seam prevents the shared kernel from
/// depending on application wiring or generated feature mappers.
abstract final class ModelJson {
  static bool _initialized = false;
  static void Function()? _mapperInitializer;

  static void configureMapperInitialization(void Function() initializer) {
    if (_initialized) return;
    _mapperInitializer = initializer;
  }

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
    final initializer = _mapperInitializer;
    if (initializer == null) {
      throw StateError(
        'ModelJson is not configured. Register generated mappers at the '
        'composition root before serializing a model.',
      );
    }
    initializer();
    _initialized = true;
  }
}
