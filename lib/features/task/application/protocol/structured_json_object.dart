/// Validated JSON object returned by a protocol adapter.
///
/// Runtime/application collaborators read named values through this value;
/// only the protocol adapter requests the wire representation.
final class StructuredJsonObject {
  StructuredJsonObject(Map<String, Object?> values)
    : _values = Map.unmodifiable(values);

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];

  Map<String, Object?> toWire() => _values;
}
