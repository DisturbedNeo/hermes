import 'dart:async';

import 'package:hermes/app/mappers.init.dart';
import 'package:hermes/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  initializeMappers();
  registerAggregateSnapshotCodecs();
  await testMain();
}
