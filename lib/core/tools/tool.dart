abstract class Tool {
  abstract final String id;
  abstract final String name;
  abstract final String description;
  abstract final Map<String, dynamic> schema;

  Future<String> process(String input);
}
