import 'dart:async';

import 'package:hermes/app/mappers.init.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  initializeMappers();
  await testMain();
}
