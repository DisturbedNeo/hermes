/// Converts a JSON-compatible value to the model-facing wire convention.
///
/// Dart model properties use camelCase internally, while planning tools,
/// views, and structured model payloads use snake_case. Keeping this
/// conversion at the protocol boundary avoids changing persistence formats.
Object? snakeCaseWire(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        _snakeCaseKey(entry.key.toString()): snakeCaseWire(entry.value),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) snakeCaseWire(item)];
  }
  return value;
}

Map<String, dynamic> snakeCaseMap(Map<Object?, Object?> value) =>
    Map<String, dynamic>.from(snakeCaseWire(value) as Map);

String _snakeCaseKey(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .replaceAll('-', '_')
      .toLowerCase();
}
