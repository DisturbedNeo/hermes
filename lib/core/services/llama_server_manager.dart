import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/file.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/services/chat_client.dart';
import 'package:path/path.dart' as p;

class LlamaServerManager {
  final ValueNotifier<LlamaServerHandle?> handle = ValueNotifier(null);
  ChatClient? chatClient;

  LlamaServerHandle? get current => handle.value;

  var _isDisposed = false;

  Future<void> start({
    required String llamaCppDirectory,
    required String modelPath,
    required String modelName,
    int nCtx = 4096,
    int nThreads = 1,
    int nGpuLayers = 0,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    int nBatch = 512,
    int nUBatch = 512,
    int mirostat = 0,
  }) async {
    await stop();

    final port = await _getFreePort();

    if (llamaCppDirectory.isEmpty){
      throw FlutterError('llama.cpp directory not specified');
    }

    final llamaServerExe = await _resolveLlamaServerExecutable(llamaCppDirectory);

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
      '--temp', '$temperature',
      '--top-p', '$topP',
      '--top-k', '$topK',
      '--mirostat', '$mirostat',
      '-b', '$nBatch',
      '-ub', '$nUBatch',
      '--flash-attn', '0',
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

    final newHandle = LlamaServerHandle(process: process, stdoutSub: stdoutSub, stderrSub: stderrSub);
    final baseUrl = 'http://127.0.0.1:$port';

    await _waitUntilReady(Uri.parse(baseUrl));

    chatClient = ChatClient(baseUrl: baseUrl, model: modelName);

    handle.value = newHandle;
  }

  Future<void> stop() async {
    if (handle.value != null) {
      await handle.value!.stop();
    }

    handle.value = null;
    chatClient = null;
  }

  Future<String?> _resolveLlamaServerExecutable(String llamaCppDir) async {
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

  Future<int> _getFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _waitUntilReady(Uri base) async {
    await Future.delayed(const Duration(seconds: 5));

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
    if (_isDisposed) return;

    stop();
    chatClient?.dispose();

    _isDisposed = true;
  }
}
