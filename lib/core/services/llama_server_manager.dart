import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/file.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:path/path.dart' as p;

class LlamaServerHandle {
  final Process process;
  final Uri baseUrl;
  final String model;
  final StreamSubscription stdoutSub;
  final StreamSubscription stderrSub;

  LlamaServerHandle({
    required this.process,
    required this.baseUrl,
    required this.model,
    required this.stdoutSub,
    required this.stderrSub,
  });

  Future<void> stop() async {
    _sendSignalSafe(process, ProcessSignal.sigint);

    await Future.delayed(const Duration(milliseconds: 400));

    _sendSignalSafe(process, ProcessSignal.sigterm);

    await Future.delayed(const Duration(milliseconds: 300));
    _sendSignalSafe(process, ProcessSignal.sigkill);

    await stdoutSub.cancel();
    await stderrSub.cancel();
  }

  void _sendSignalSafe(Process p, ProcessSignal sig) {
    try {
      p.kill(sig);
    } catch (_) {}
  }
}

class LlamaServerManager {
  final ValueNotifier<LlamaServerHandle?> handle = ValueNotifier(null);

  LlamaServerHandle? get current => handle.value;

  final PreferencesService _preferencesService = serviceProvider.get<PreferencesService>();

  var isDisposed = false;

  Future<void> start({
    required String modelPath,
    required String modelName,
    int nCtx = 8192,
    int nThreads = 1,
    int nGpuLayers = 999,
  }) async {
    await stop();

    final port = await getFreePort();
    final llamaCppDirectory = await _preferencesService.getLlamaCppDirectory();

    if (llamaCppDirectory == null){
      throw FlutterError('llama.cpp directory not specified');
    }

    final llamaServerExe = await resolveLlamaServerExecutable(llamaCppDirectory);

    if (llamaServerExe == null) {
      throw FlutterError(
        'Could not find llama-server binary in $llamaCppDirectory. '
        'Make sure llama.cpp is built and the server binary exists.',
      );
    }

    final args = <String>[
      '-m', modelPath,
      '--host', '127.0.0.1',
      '--port', '$port',
      '-c', '$nCtx',
      '-t', '$nThreads',
      '-ngl', '$nGpuLayers',
      '--no-mmap'
    ];

    final process = await Process.start(
      llamaServerExe,
      args,
      mode: ProcessStartMode.detachedWithStdio,
      workingDirectory: llamaCppDirectory,
    );

    final stdoutSub = process.stdout.transform(utf8.decoder).listen((line) { if (kDebugMode) print(line); });
    final stderrSub = process.stderr.transform(utf8.decoder).listen((line) { if (kDebugMode) print(line); });

    final newHandle = LlamaServerHandle(process: process, baseUrl: Uri.parse('http://127.0.0.1:$port'), model: modelName, stdoutSub: stdoutSub, stderrSub: stderrSub);

    await waitUntilReady(newHandle.baseUrl);

    handle.value = newHandle;
  }

  Future<void> stop() async {
    if (handle.value != null) {
      await handle.value!.stop();
    }

    handle.value = null;
  }

  Future<String?> resolveLlamaServerExecutable(String llamaCppDir) async {
    final candidates = <String>[
      // make / default in repo root
      p.join(llamaCppDir, 'llama-server'),
      p.join(llamaCppDir, 'llama-server.exe'),
      // common CMake layouts
      p.join(llamaCppDir, 'build', 'bin', 'llama-server'),
      p.join(llamaCppDir, 'build', 'bin', 'llama-server.exe'),
      p.join(llamaCppDir, 'build', 'bin', 'Release', 'llama-server.exe'),
      p.join(llamaCppDir, 'bin', 'llama-server'),
      p.join(llamaCppDir, 'bin', 'llama-server.exe'),
    ];

    for (final path in candidates) {
      final f = File(path);

      if (await f.exists()) {
        if (!Platform.isWindows && !await isExecutable(f)) {
          try {
            await Process.run('chmod', ['+x', f.path]);
          } catch (_) {}
        }

        return f.path;
      }
    }

    return null;
  }

  Future<int> getFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> waitUntilReady(Uri base) async {
    await Future.delayed(const Duration(seconds: 10));

    final client = HttpClient();
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    Object? lastError;

    while(DateTime.now().isBefore(deadline)) {
      try {
        final req = await client.getUrl(base.replace(path: '/health'));
        final res = await req.close();

        if (res.statusCode == 200) {
          await res.drain();
          client.close(force: true);
          return;
        }

        await res.drain();
      } catch (e) {
        lastError = e;
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    client.close(force: true);

    throw StateError('llama-cpp-python server not ready: $lastError');
  }

  void dispose() {
    if (isDisposed) return;

    stop();

    isDisposed = true;
  }
}
