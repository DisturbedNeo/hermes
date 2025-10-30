class ToolDefinition {
  final String id;
  final String name;
  final String description;
  final Map<String, dynamic> schema;

  const ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.schema,
  });
}
