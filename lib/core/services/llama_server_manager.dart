import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/file.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:path/path.dart' as p;

class LlamaServerManager {
  static const Duration _healthRequestTimeout = Duration(seconds: 2);
  static const Duration _startupStallTimeout = Duration(minutes: 2);

  final ValueNotifier<LlamaServerHandle?> handle = ValueNotifier(null);
  final ModelSessionDiagnostics diagnostics = ModelSessionDiagnostics();
  ChatClient? chatClient;
  String? currentModelName;

  LlamaServerHandle? get current => handle.value;

  Future<void> startWithSnapshot(ModelConfigurationSnapshot snapshot) {
    return start(
      llamaCppDirectory: snapshot.llamaCppDirectory,
      modelPath: snapshot.modelPath,
      modelName: snapshot.modelName,
      nCtx: snapshot.nCtx,
      nThreads: snapshot.nThreads,
      nGpuLayers: snapshot.nGpuLayers,
      temperature: snapshot.temperature,
      topP: snapshot.topP,
      topK: snapshot.topK,
      nBatch: snapshot.nBatch,
      nUBatch: snapshot.nUBatch,
      mirostat: snapshot.mirostat,
      repeatPenalty: snapshot.repeatPenalty,
      repeatLastN: snapshot.repeatLastN,
      presencePenalty: snapshot.presencePenalty,
      frequencyPenalty: snapshot.frequencyPenalty,
      thinking: snapshot.thinking,
    );
  }

  LlamaServerHandle? _startingHandle;
  var _startGeneration = 0;
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
    double repeatPenalty = 1.1,
    int repeatLastN = 256,
    double presencePenalty = 1.2,
    double frequencyPenalty = 0.5,
    bool thinking = true,
  }) async {
    final generation = ++_startGeneration;
    final snapshot = ModelConfigurationSnapshot(
      modelName: modelName,
      modelPath: modelPath,
      llamaCppDirectory: llamaCppDirectory,
      nCtx: nCtx,
      nThreads: nThreads,
      nGpuLayers: nGpuLayers,
      temperature: temperature,
      topP: topP,
      topK: topK,
      nBatch: nBatch,
      nUBatch: nUBatch,
      mirostat: mirostat,
      repeatPenalty: repeatPenalty,
      repeatLastN: repeatLastN,
      presencePenalty: presencePenalty,
      frequencyPenalty: frequencyPenalty,
      thinking: thinking,
    );

    if (llamaCppDirectory.isEmpty) {
      final error = FlutterError('llama.cpp directory not specified');
      diagnostics.recordFailure(error);
      throw error;
    }

    final llamaServerExe = await _resolveLlamaServerExecutable(
      llamaCppDirectory,
    );

    if (llamaServerExe == null) {
      final error = FlutterError(
        'Could not find llama-server binary in $llamaCppDirectory. '
        'Make sure llama.cpp is built and the server binary exists.',
      );
      diagnostics.recordFailure(error);
      throw error;
    }

    final port = await _getFreePort();
    _throwIfCancelled(generation);

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
      '--repeat-penalty', '$repeatPenalty',
      '--repeat-last-n', '$repeatLastN',
      '--presence-penalty', '$presencePenalty',
      '--frequency-penalty', '$frequencyPenalty',
      '--no-mmap',
      if (!thinking) ...['--chat-template-kwargs', '{"enable_thinking": false}'],
      '--jinja',
    ];

    await _stopHandles();
    _throwIfCancelled(generation);

    final baseUrl = 'http://127.0.0.1:$port';
    diagnostics.recordStarting(
      snapshot: snapshot,
      port: port,
      baseUrl: baseUrl,
      executablePath: llamaServerExe,
    );

    final Process process;
    try {
      process = await Process.start(
        llamaServerExe,
        args,
        workingDirectory: llamaCppDirectory,
      );
    } catch (e, stackTrace) {
      diagnostics.recordFailure(e);
      Error.throwWithStackTrace(e, stackTrace);
    }

    final startupOutput = _StartupOutput();

    final stdoutSub = process.stdout.transform(utf8.decoder).listen((line) {
      startupOutput.add(line);
      diagnostics.addLog('stdout', line);
      if (kDebugMode) print(line);
    });

    final stderrSub = process.stderr.transform(utf8.decoder).listen((line) {
      startupOutput.add(line);
      diagnostics.addLog('stderr', line);
      if (kDebugMode) print(line);
    });

    final newHandle = LlamaServerHandle(
      process: process,
      stdoutSub: stdoutSub,
      stderrSub: stderrSub,
    );

    _startingHandle = newHandle;

    unawaited(
      process.exitCode.then((code) {
        if (handle.value == newHandle || _startingHandle == newHandle) {
          diagnostics.recordProcessExit(code);
        }

        if (handle.value == newHandle) {
          chatClient?.dispose();
          chatClient = null;
          currentModelName = null;
          handle.value = null;
        }
      }),
    );

    try {
      await _waitUntilReady(
        Uri.parse(baseUrl),
        process,
        startupOutput: startupOutput,
        isCancelled: () => generation != _startGeneration,
      );

      _throwIfCancelled(generation);

      final newClient = ChatClient(baseUrl: baseUrl, model: modelName);

      if (generation != _startGeneration) {
        newClient.dispose();
        throw const LlamaServerStartupCancelled();
      }

      chatClient = newClient;
      currentModelName = modelName;
      _startingHandle = null;
      handle.value = newHandle;
      diagnostics.recordReady();
    } catch (e, stackTrace) {
      chatClient = null;
      if (_startingHandle == newHandle) {
        _startingHandle = null;
      }

      if (e is LlamaServerStartupCancelled) {
        diagnostics.recordCancelled();
      } else {
        diagnostics.recordFailure(e, recentOutput: startupOutput.recentOutput);
      }

      try {
        await newHandle.stop();
      } catch (_) {}

      Error.throwWithStackTrace(e, stackTrace);
    }
  }

  Future<void> stop() async {
    _startGeneration++;
    await _stopHandles();
  }

  Future<void> _stopHandles() async {
    final startingHandle = _startingHandle;
    final currentHandle = handle.value;
    final currentClient = chatClient;

    _startingHandle = null;
    handle.value = null;
    chatClient = null;
    currentModelName = null;
    diagnostics.recordStopped();

    currentClient?.dispose();

    if (startingHandle != null && startingHandle != currentHandle) {
      await startingHandle.stop();
    }

    if (currentHandle != null) {
      await currentHandle.stop();
    }
  }

  void _throwIfCancelled(int generation) {
    if (generation != _startGeneration) {
      throw const LlamaServerStartupCancelled();
    }
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

  Future<void> _waitUntilReady(
    Uri base,
    Process process, {
    required _StartupOutput startupOutput,
    required bool Function() isCancelled,
  }) async {
    final client = HttpClient();
    Object? lastError;
    var processExited = false;
    int? processExitCode;
    final exitCode = process.exitCode;

    unawaited(
      exitCode.then((code) {
        processExited = true;
        processExitCode = code;
      }),
    );

    var delay = const Duration(milliseconds: 100);
    var lastProgressAt = DateTime.now();
    final maxDelay = const Duration(seconds: 1);

    try {
      while (true) {
        if (startupOutput.lastOutputAt.isAfter(lastProgressAt)) {
          lastProgressAt = startupOutput.lastOutputAt;
        }

        if (isCancelled()) {
          throw const LlamaServerStartupCancelled();
        }

        if (processExited) {
          throw StateError(
            _startupFailureMessage(
              'llama-server exited before it was ready (exit code $processExitCode)',
              startupOutput,
            ),
          );
        }

        try {
          final req = await client
              .getUrl(base.replace(path: '/health'))
              .timeout(_healthRequestTimeout);
          final res = await req.close().timeout(_healthRequestTimeout);

          if (res.statusCode == 200) {
            await res.drain();
            return;
          }

          if (res.statusCode == 503) {
            lastProgressAt = DateTime.now();
          }

          lastError = 'health check returned HTTP ${res.statusCode}';
          await res.drain();
        } catch (e) {
          lastError = e;
        }

        if (DateTime.now().difference(lastProgressAt) > _startupStallTimeout) {
          throw StateError(
            _startupFailureMessage(
              'llama-server startup appears stalled. Last readiness error: $lastError',
              startupOutput,
            ),
          );
        }

        await Future.any<void>([Future.delayed(delay), exitCode.then((_) {})]);

        final nextDelayMs = (delay.inMilliseconds * 1.5).round();
        delay = Duration(
          milliseconds: nextDelayMs > maxDelay.inMilliseconds
              ? maxDelay.inMilliseconds
              : nextDelayMs,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  String _startupFailureMessage(String message, _StartupOutput startupOutput) {
    final recentOutput = startupOutput.recentOutput;

    if (recentOutput.isEmpty) {
      return message;
    }

    return '$message\nRecent llama-server output:\n$recentOutput';
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await stop();
    diagnostics.dispose();
  }
}

class LlamaServerStartupCancelled implements Exception {
  const LlamaServerStartupCancelled();

  @override
  String toString() => 'llama-server startup cancelled';
}

class _StartupOutput {
  static const int _maxEntries = 20;

  final List<String> _entries = [];
  DateTime lastOutputAt = DateTime.now();

  void add(String output) {
    final trimmed = output.trim();

    if (trimmed.isEmpty) return;

    lastOutputAt = DateTime.now();
    _entries.add(trimmed);

    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
  }

  String get recentOutput => _entries.join('\n');
}
