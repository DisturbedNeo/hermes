import 'dart:async';

import 'package:hermes/app/mappers.init.dart';
import 'package:hermes/shared_kernel/model_json.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ModelJson.configureMapperInitialization(initializeMappers);
  await testMain();
}
