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
  static final ModelJsonCodecRegistry registry = ModelJsonCodecRegistry();

  static void register<T>({
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
    bool replaceExisting = false,
  }) {
    registry.register<T>(
      encode: encode,
      decode: decode,
      replaceExisting: replaceExisting,
    );
  }

  /// Registers a composition-root codec without failing when application
  /// initialization is repeated by a test harness or hot restart.
  static void registerIfAbsent<T>({
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
  }) {
    registry.registerIfAbsent<T>(encode: encode, decode: decode);
  }

  static bool hasCodec<T>() => registry.hasCodec<T>();

  static T decode<T>(Object? value) {
    _ensureInitialized();
    final normalized = value is Map && value is! Map<String, dynamic>
        ? Map<String, dynamic>.from(value)
        : value;
    final codec = registry.codecFor<T>();
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
    final codec =
        registry.codecForType(value.runtimeType) ?? registry.codecFor<T>();
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

/// Explicit owner for codecs registered outside generated mapper discovery.
/// Duplicate registration is rejected so an unrelated adapter cannot silently
/// replace a persistence representation. Composition roots may use
/// [registerIfAbsent] for idempotent startup.
final class ModelJsonCodecRegistry {
  final Map<Type, ModelJsonCodec> _codecs = {};

  void register<T>({
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
    bool replaceExisting = false,
  }) {
    if (_codecs.containsKey(T) && !replaceExisting) {
      throw StateError('A JSON codec is already registered for $T.');
    }
    _codecs[T] = ModelJsonCodec(
      encode: (value) => encode(value as T),
      decode: (value) => decode(value) as Object,
    );
  }

  void registerIfAbsent<T>({
    required Map<String, dynamic> Function(T value) encode,
    required T Function(Map<String, dynamic> value) decode,
  }) {
    if (hasCodec<T>()) return;
    register<T>(encode: encode, decode: decode);
  }

  bool hasCodec<T>() => _codecs.containsKey(T);

  ModelJsonCodec? codecFor<T>() => _codecs[T];

  ModelJsonCodec? codecForType(Type type) => _codecs[type];
}

class ModelJsonCodec {
  const ModelJsonCodec({required this.encode, required this.decode});

  final Map<String, dynamic> Function(Object value) encode;
  final Object Function(Map<String, dynamic> value) decode;
}
