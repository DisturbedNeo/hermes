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
import 'package:hermes/core/services/model_diagnostic_bundle_writer.dart';

export 'package:hermes/core/helpers/server_health_checker.dart'
    show LlamaServerStartupCancelled;

import 'disposable.dart';

typedef LlamaProcessLauncher =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });
typedef LlamaPortAllocator = Future<int> Function();
typedef LlamaHealthWaiter =
    Future<void> Function({
      required Uri baseUrl,
      required Process process,
      required String Function() recentOutput,
      required bool Function() isCancelled,
    });

@visibleForTesting
List<String> buildLlamaServerArguments({
  required ModelConfigurationSnapshot snapshot,
  required int port,
}) {
  final nThreads = snapshot.nThreads;

  return <String>[
    '-m',
    snapshot.modelPath,

    '--host',
    '127.0.0.1',

    '--port',
    '$port',

    '-c',
    '${snapshot.nCtx}',

    '-np',
    '1',

    '-t',
    '$nThreads',

    '--threads-batch',
    '$nThreads',

    '-ngl',
    'all',

    '--load-mode',
    'dio',

    '--temp',
    '${snapshot.temperature}',

    '--top-p',
    '${snapshot.topP}',

    '--top-k',
    '${snapshot.topK}',

    '--min-p',
    '${snapshot.minP}',

    '--mirostat',
    '${snapshot.mirostat}',

    '-b',
    '${snapshot.nBatch}',

    '-ub',
    '${snapshot.nUBatch}',

    '--repeat-penalty',
    '${snapshot.repeatPenalty}',

    '--repeat-last-n',
    '${snapshot.repeatLastN}',

    '--presence-penalty',
    '${snapshot.presencePenalty}',

    '--frequency-penalty',
    '${snapshot.frequencyPenalty}',

    '--flash-attn',
    snapshot.flashAttention ? 'on' : 'off',

    if (snapshot.cachePrompt) ...[
      '--cache-prompt',

      '--cache-reuse',
      '${snapshot.cacheReuse}',
    ] else
      '--no-cache-prompt',

    if (snapshot.thinking) ...[
      '--reasoning',
      'on',
      if (snapshot.reasoningEffort !=
          ModelConfigurationSnapshot.defaultReasoningEffort) ...[
        '--reasoning-effort',
        snapshot.reasoningEffort,
      ],
    ] else ...[
      '--reasoning',
      'off',

      '--chat-template-kwargs',
      '{"enable_thinking": false}',
    ],

    if (snapshot.mtpEnabled) ...[
      '--spec-type',
      'draft-mtp',
      '--spec-draft-n-max',
      '${snapshot.mtpDraftTokens}',
    ],

    if (snapshot.kvCacheQuantizationEnabled) ...[
      '--cache-type-k',

      snapshot.kvCacheTypeK,
      '--cache-type-v',
      snapshot.kvCacheTypeV,
    ],

    '--jinja',
  ];
}

class LlamaServerManager implements Disposable {
  final ModelDiagnosticBundleWriter _diagnosticBundleWriter;
  final LlamaProcessLauncher _processLauncher;
  final LlamaPortAllocator _portAllocator;
  final LlamaHealthWaiter _healthWaiter;
  final ValueNotifier<LlamaServerHandle?> handle = ValueNotifier(null);
  final ModelSessionDiagnostics diagnostics = ModelSessionDiagnostics();
  ChatClient? chatClient;
  String? currentModelName;

  LlamaServerHandle? get current => handle.value;

  LlamaServerManager({
    ModelDiagnosticBundleWriter? diagnosticBundleWriter,
    LlamaProcessLauncher? processLauncher,
    LlamaPortAllocator? portAllocator,
    LlamaHealthWaiter? healthWaiter,
  }) : _diagnosticBundleWriter =
           diagnosticBundleWriter ?? ModelDiagnosticBundleWriter(),
       _processLauncher = processLauncher ?? _launchProcess,
       _portAllocator = portAllocator ?? _getFreePort,
       _healthWaiter = healthWaiter ?? _waitForHealth;

  Future<void> startWithSnapshot(ModelConfigurationSnapshot snapshot) {
    return start(
      llamaCppDirectory: snapshot.llamaCppDirectory,
      modelPath: snapshot.modelPath,
      modelName: snapshot.modelName,
      nCtx: snapshot.nCtx,
      nThreads: snapshot.nThreads,
      temperature: snapshot.temperature,
      topP: snapshot.topP,
      topK: snapshot.topK,
      minP: snapshot.minP,
      nBatch: snapshot.nBatch,
      nUBatch: snapshot.nUBatch,
      mirostat: snapshot.mirostat,
      repeatPenalty: snapshot.repeatPenalty,
      repeatLastN: snapshot.repeatLastN,
      presencePenalty: snapshot.presencePenalty,
      frequencyPenalty: snapshot.frequencyPenalty,
      thinking: snapshot.thinking,
      reasoningEffort: snapshot.reasoningEffort,
      mtpEnabled: snapshot.mtpEnabled,
      mtpDraftTokens: snapshot.mtpDraftTokens,
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
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    double minP = 0.05,
    int nBatch = 2048,
    int nUBatch = 2048,
    int mirostat = 0,
    double repeatPenalty = 1.1,
    int repeatLastN = 256,
    double presencePenalty = 1.2,
    double frequencyPenalty = 0.5,
    bool thinking = true,
    String reasoningEffort = ModelConfigurationSnapshot.defaultReasoningEffort,
    bool mtpEnabled = false,
    int mtpDraftTokens = ModelConfigurationSnapshot.defaultMtpDraftTokens,
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
      temperature: temperature,
      topP: topP,
      topK: topK,
      minP: minP,
      nBatch: nBatch,
      nUBatch: nUBatch,
      mirostat: mirostat,
      repeatPenalty: repeatPenalty,
      repeatLastN: repeatLastN,
      presencePenalty: presencePenalty,
      frequencyPenalty: frequencyPenalty,
      thinking: thinking,
      reasoningEffort: thinking
          ? ModelConfigurationSnapshot.normaliseReasoningEffort(reasoningEffort)
          : ModelConfigurationSnapshot.defaultReasoningEffort,
      mtpEnabled: mtpEnabled,
      mtpDraftTokens: ModelConfigurationSnapshot.clampMtpDraftTokens(
        mtpDraftTokens,
      ),
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

    await _stopHandles();
    _throwIfCancelled(generation);

    for (var attempt = 1; attempt <= 3; attempt++) {
      final port = await _portAllocator();
      _throwIfCancelled(generation);
      final args = buildLlamaServerArguments(snapshot: snapshot, port: port);
      final baseUrl = 'http://127.0.0.1:$port';
      diagnostics.recordStarting(
        snapshot: snapshot,
        port: port,
        baseUrl: baseUrl,
        executablePath: llamaServerExe,
      );

      final Process process;
      try {
        process = await _processLauncher(
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
      _watchProcessExit(newHandle);

      try {
        await _healthWaiter(
          baseUrl: Uri.parse(baseUrl),
          process: process,
          recentOutput: () => startupOutput.recentOutput,
          isCancelled: () => generation != _startGeneration,
        );
        _throwIfCancelled(generation);

        final newClient = ChatClient(
          baseUrl: baseUrl,
          model: modelName,
          onTransportEvent: _recordTransportEvent,
        );
        if (generation != _startGeneration) {
          newClient.dispose();
          throw const LlamaServerStartupCancelled();
        }

        chatClient = newClient;
        currentModelName = modelName;
        _startingHandle = null;
        handle.value = newHandle;
        diagnostics.recordReady();
        return;
      } catch (e, stackTrace) {
        chatClient = null;
        if (_startingHandle == newHandle) _startingHandle = null;
        try {
          await newHandle.stop();
        } catch (_) {}

        final retryBindCollision =
            attempt < 3 &&
            e is! LlamaServerStartupCancelled &&
            _isAddressInUse(startupOutput.recentOutput);
        if (retryBindCollision) continue;

        if (e is LlamaServerStartupCancelled) {
          diagnostics.recordCancelled();
        } else {
          diagnostics.recordFailure(
            e,
            recentOutput: startupOutput.recentOutput,
          );
        }
        Error.throwWithStackTrace(e, stackTrace);
      }
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

  void _watchProcessExit(LlamaServerHandle serverHandle) {
    unawaited(
      serverHandle.process.exitCode.then((code) {
        if (handle.value == serverHandle || _startingHandle == serverHandle) {
          diagnostics.recordProcessExit(code);
        }
        if (handle.value == serverHandle) {
          chatClient?.dispose();
          chatClient = null;
          currentModelName = null;
          handle.value = null;
        }
      }),
    );
  }

  bool _isAddressInUse(String output) {
    final normalized = output.toLowerCase();
    return normalized.contains('address already in use') ||
        normalized.contains('failed to bind') ||
        normalized.contains('error binding');
  }

  static Future<Process> _launchProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
  }

  static Future<int> _getFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<void> _waitForHealth({
    required Uri baseUrl,
    required Process process,
    required String Function() recentOutput,
    required bool Function() isCancelled,
  }) async {
    final checker = ServerHealthChecker(
      baseUrl: baseUrl,
      process: process,
      recentOutputGetter: recentOutput,
    );
    await checker.waitForReady(isCancelled: isCancelled);
  }

  void _recordTransportEvent(ChatTransportEvent event) {
    diagnostics.recordTransportEvent(
      kind: event.kind.name,
      attempt: event.attempt,
      willRetry: event.willRetry,
      outputStarted: event.outputStarted,
      error: event.error,
    );
    if (event.willRetry) return;

    final currentHandle = handle.value;
    unawaited(
      _diagnosticBundleWriter.writeTransportFailure(
        timestamp: event.timestamp,
        modelName:
            currentModelName ?? diagnostics.modelSnapshot?.modelName ?? '',
        baseUrl: diagnostics.baseUrl ?? event.uri.origin,
        serverState: diagnostics.state.name,
        processRunning: currentHandle != null,
        processId: currentHandle?.process.pid,
        failureKind: event.kind.name,
        attempt: event.attempt,
        outputStarted: event.outputStarted,
        error: event.error,
        stackTrace: event.stackTrace,
        recentLogs: diagnostics.logs.map(
          (entry) => {
            'timestamp': entry.timestamp.toUtc().toIso8601String(),
            'source': entry.source,
            'message': entry.message,
          },
        ),
      ),
    );
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
