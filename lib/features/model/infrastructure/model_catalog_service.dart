import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:hermes/features/model/application/model_catalog.dart';
import 'package:hermes/features/settings/application/preferences_port.dart';

/// Infrastructure adapter for local GGUF discovery.
class ModelCatalogService implements ModelCatalogPort {
  const ModelCatalogService({required ModelDirectorySettingsPort preferences})
    : _preferences = preferences;

  final ModelDirectorySettingsPort _preferences;

  @override
  int get defaultThreadCount => Platform.numberOfProcessors;

  @override
  Future<List<ModelDescriptor>> listModels() async {
    final directoryPath = await _preferences.getModelsDirectory();
    if (directoryPath == null) return const [];
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return const [];

    final models = <String, ModelDescriptor>{};
    final shardPattern = RegExp(
      r'^(.*)-(\d{5})-of-(\d{5})\.gguf$',
      caseSensitive: false,
    );
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (!name.toLowerCase().endsWith('.gguf')) continue;
      final match = shardPattern.firstMatch(name);
      if (match != null) {
        if (int.parse(match.group(2)!) != 1) continue;
        models[match.group(1)!] = ModelDescriptor(
          alias: match.group(1)!,
          path: entity.path,
        );
      } else {
        final alias = name.substring(0, name.length - 5);
        models[alias] = ModelDescriptor(alias: alias, path: entity.path);
      }
    }
    return models.values.toList()..sort((a, b) => a.alias.compareTo(b.alias));
  }
}
