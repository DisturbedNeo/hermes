import 'dart:io';

import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:path/path.dart' as p;

Future<Map<String, File>> getModels() async {
  final modelsDirectoryPath = await serviceProvider.get<PreferencesService>().getModelsDirectory();

  if (modelsDirectoryPath == null) {
    return {};
  }

  final modelsDirectory = Directory(modelsDirectoryPath);

  if (!await modelsDirectory.exists()) {
    return {};
  }

  final models = <String, File>{};
  final shardPattern = RegExp(r'^(.*)-(\d{5})-of-(\d{5})\.gguf$', caseSensitive: false);

  for (final entity in modelsDirectory.listSync().whereType<File>()) {
    final name = p.basename(entity.path);
    if (!name.toLowerCase().endsWith('.gguf')) {
      continue;
    }

    final match = shardPattern.firstMatch(name);

    if (match != null) {
      final base = match.group(1)!;
      final shardNum = int.parse(match.group(2)!);
      if (shardNum == 1) {
        models[base] = entity;
      }
    } else {
      final alias = name.substring(0, name.length - 5);
      models[alias] = entity;
    }
  }

  return models;
}