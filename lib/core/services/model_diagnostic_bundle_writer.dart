import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef DiagnosticDirectoryProvider = Future<Directory> Function();

class ModelDiagnosticBundleWriter {
  static const int maxBundles = 10;

  final DiagnosticDirectoryProvider _directoryProvider;

  ModelDiagnosticBundleWriter({DiagnosticDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  Future<void> writeTransportFailure({
    required DateTime timestamp,
    required String modelName,
    required String baseUrl,
    required String serverState,
    required bool processRunning,
    required int? processId,
    required String failureKind,
    required int attempt,
    required bool outputStarted,
    required Object error,
    required StackTrace stackTrace,
    required Iterable<Map<String, String>> recentLogs,
    Map<String, dynamic>? latestTelemetry,
    Map<String, dynamic>? serverProperties,
  }) async {
    try {
      final supportDirectory = await _directoryProvider();
      final directory = Directory(
        p.join(supportDirectory.path, 'diagnostics', 'model-transport'),
      );
      await directory.create(recursive: true);
      final safeTimestamp = timestamp
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(
        p.join(directory.path, 'transport-failure-$safeTimestamp.json'),
      );
      final bundle = <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'model': modelName,
        'baseUrl': baseUrl,
        'serverState': serverState,
        'processRunning': processRunning,
        'processId': ?processId,
        'transport': {
          'kind': failureKind,
          'attempt': attempt,
          'outputStarted': outputStarted,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
        'latestTelemetry': ?latestTelemetry,
        'serverProperties': ?serverProperties,
        'recentServerLogs': recentLogs.toList(),
      };
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(bundle)}\n',
        flush: true,
      );
      await _prune(directory);
    } catch (_) {
      // Diagnostic persistence is best-effort and must not mask the failure.
    }
  }

  Future<void> _prune(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => p.basename(file.path).startsWith('transport-failure-'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    for (final file in files.skip(maxBundles)) {
      await file.delete();
    }
  }
}
