import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';

/// Generic JSON entry point for all typed application DTOs.
///
/// Mapper registration is supplied by the composition root. Keeping the
/// generated mapper registration explicit keeps this class independent of
/// feature adapters. Boundary adapters may additionally register codecs for
/// domain aggregates whose persistence representation is intentionally owned
/// outside the domain library.
abstract final class ModelJson {
  static final Map<Type, _ModelJsonCodec> _codecs = {};

  static void register<T>({
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
  }) {
    _codecs[T] = _ModelJsonCodec(
      encode: (value) => encode(value as T),
      decode: (value) => decode(value) as Object,
    );
  }

  static T decode<T>(Object? value) {
    _ensureInitialized();
    final normalized = value is Map && value is! Map<String, dynamic>
        ? Map<String, dynamic>.from(value)
        : value;
    final codec = _codecs[T];
    if (codec != null) {
      if (normalized is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      return codec.decode(normalized) as T;
    }
    return MapperContainer.globals.fromValue<T>(normalized);
  }

  static Map<String, dynamic> encode<T extends Object>(T value) {
    _ensureInitialized();
    final codec = _codecs[value.runtimeType] ?? _codecs[T];
    if (codec != null) return codec.encode(value);
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
    DateTimeMapper.encodingMode = DateTimeEncoding.iso8601String;
  }
}

class _ModelJsonCodec {
  const _ModelJsonCodec({required this.encode, required this.decode});

  final Map<String, dynamic> Function(Object value) encode;
  final Object Function(Map<String, dynamic> value) decode;
}
