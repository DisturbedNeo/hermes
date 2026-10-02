/// Typed model item exposed to presentation. File enumeration remains behind
/// the application capability and is never performed by widgets.
class ModelDescriptor {
  const ModelDescriptor({required this.alias, required this.path});

  final String alias;
  final String path;
}

abstract interface class ModelCatalogPort {
  Future<List<ModelDescriptor>> listModels();

  int get defaultThreadCount;
}
