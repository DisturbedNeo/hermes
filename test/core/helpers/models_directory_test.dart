import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/models_directory.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('discovers models from the injected preferences service', () async {
    final root = await Directory.systemTemp.createTemp('hermes_models_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    await File('${root.path}/single.gguf').writeAsString('model');
    await File(
      '${root.path}/sharded-00001-of-00002.gguf',
    ).writeAsString('model');
    await File(
      '${root.path}/sharded-00002-of-00002.gguf',
    ).writeAsString('model');
    await File('${root.path}/ignored.txt').writeAsString('not a model');

    final models = await getModels(_FakePreferencesService(root.path));

    expect(models.keys, containsAll(<String>['single', 'sharded']));
    expect(models, hasLength(2));
    expect(models['sharded']?.path, endsWith('sharded-00001-of-00002.gguf'));
  });
}

class _FakePreferencesService extends PreferencesService {
  _FakePreferencesService(this.modelsDirectory);

  final String modelsDirectory;

  @override
  Future<String?> getModelsDirectory() async => modelsDirectory;
}
