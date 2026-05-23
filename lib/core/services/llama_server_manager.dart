import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/llama_server_finder.dart';
import 'package:hermes/core/helpers/server_health_checker.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/services/chat/chat_client.dart';

export 'package:hermes/core/helpers/server_health_checker.dart'
    show LlamaServerStartupCancelled;

import 'disposable.dart';

@visibleForTesting
List<String> buildLlamaServerArguments({
  required ModelConfigurationSnapshot snapshot,
  required int port,
}) {
  final nThreads = snapshot.nThreads;

  return <String>[
    '-m', snapshot.modelPath,
    '--host', '127.0.0.1',
    '--port', '$port',
    '-c', '${snapshot.nCtx}',
    '-t', '$nThreads',
    '--threads-batch', '$nThreads',
    '-ngl', '${snapshot.nGpuLayers}',
    '--temp', '${snapshot.temperature}',
    '--top-p', '${snapshot.topP}',
    '--top-k', '${snapshot.topK}',
    '--mirostat', '${snapshot.mirostat}',
    '-b', '${snapshot.nBatch}',
    '-ub', '${snapshot.nUBatch}',
    '--repeat-penalty', '${snapshot.repeatPenalty}',
    '--repeat-last-n', '${snapshot.repeatLastN}',
    '--presence-penalty', '${snapshot.presencePenalty}',
    '--frequency-penalty', '${snapshot.frequencyPenalty}',
    '--flash-attn', snapshot.flashAttention ? 'on' : 'off',
    '--no-mmap',
    if (snapshot.cachePrompt) ...[
      '--cache-prompt',
      '--cache-reuse', '${snapshot.cacheReuse}',
    ] else
      '--no-cache-prompt',
    if (!snapshot.thinking) ...[
      '--chat-template-kwargs', '{"enable_thinking": false}',
    ],
    if (snapshot.kvCacheQuantizationEnabled) ...[
      '--cache-type-k', snapshot.kvCacheTypeK,
      '--cache-type-v', snapshot.kvCacheTypeV,
    ],
    '--jinja',
  ];
}

class LlamaServerManager implements Disposable {
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
      flashAttention: snapshot.flashAttention,
      cachePrompt: snapshot.cachePrompt,
      cacheReuse: snapshot.cacheReuse,
      kvCacheQuantizationEnabled: snapshot.kvCacheQuantizationEnabled,
      kvCacheTypeK: snapshot.kvCacheTypeK,
      kvCacheTypeV: snapshot.kvCacheTypeV,
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
    int? nThreads,
    int nGpuLayers = 0,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    int nBatch = 2048,
    int nUBatch = 512,
    int mirostat = 0,
    double repeatPenalty = 1.1,
    int repeatLastN = 256,
    double presencePenalty = 1.2,
    double frequencyPenalty = 0.5,
    bool thinking = true,
    bool flashAttention = true,
    bool cachePrompt = true,
    int cacheReuse = ModelConfigurationSnapshot.defaultCacheReuse,
    bool kvCacheQuantizationEnabled = true,
    String kvCacheTypeK = ModelConfigurationSnapshot.defaultKvCacheType,
    String kvCacheTypeV = ModelConfigurationSnapshot.defaultKvCacheType,
  }) async {
    final generation = ++_startGeneration;
    final effectiveNThreads =
        nThreads ?? ModelConfigurationSnapshot.defaultNThreads;
    final snapshot = ModelConfigurationSnapshot(
      modelName: modelName,
      modelPath: modelPath,
      llamaCppDirectory: llamaCppDirectory,
      nCtx: nCtx,
      nThreads: effectiveNThreads,
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
      flashAttention: flashAttention,
      cachePrompt: cachePrompt,
      cacheReuse: ModelConfigurationSnapshot.clampCacheReuse(cacheReuse),
      kvCacheQuantizationEnabled: kvCacheQuantizationEnabled,
      kvCacheTypeK: kvCacheTypeK,
      kvCacheTypeV: kvCacheTypeV,
    );

    if (llamaCppDirectory.isEmpty) {
      final error = FlutterError('llama.cpp directory not specified');
      diagnostics.recordFailure(error);
      throw error;
    }

    final llamaServerExe = await resolveLlamaServerExecutable(
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

    final args = buildLlamaServerArguments(snapshot: snapshot, port: port);

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
      final healthChecker = ServerHealthChecker(
        baseUrl: Uri.parse(baseUrl),
        process: process,
        recentOutputGetter: () => startupOutput.recentOutput,
      );
      await healthChecker.waitForReady(
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

  Future<int> _getFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await stop();
    diagnostics.dispose();
  }
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
