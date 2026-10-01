import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:hermes/features/model/infrastructure/llama_server_finder.dart';
import 'package:hermes/features/model/infrastructure/server_health_checker.dart';
import 'package:hermes/features/model/infrastructure/llama_server_handle.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/model/application/model_session_diagnostics.dart';
import 'package:hermes/features/model/application/model_session_diagnostics_port.dart';
import 'package:hermes/features/model/application/model_session_telemetry_port.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/features/model/domain/model_provider.dart';
import 'package:hermes/features/model/application/model_call_diagnostics.dart';
import 'package:hermes/features/model/infrastructure/model_diagnostic_bundle_writer.dart';

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
typedef LlamaModelProviderFactory =
    ModelProvider Function({
      required String baseUrl,
      required String model,
      void Function(ModelCallDiagnostics value)? onDiagnostics,
    });

@visibleForTesting
List<String> buildLlamaServerArguments({
  required ModelConfigurationSnapshot snapshot,
  required int port,
}) {
  final nThreads = snapshot.nThreads;
  final mtpModelPath = ModelConfigurationSnapshot.normaliseOptionalModelPath(
    snapshot.mtpModelPath,
  );

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
      if (mtpModelPath != null) ...['--spec-draft-model', mtpModelPath],
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

class LlamaServerManager implements ModelServerPort {
  final LlamaProcessLauncher _processLauncher;
  final LlamaPortAllocator _portAllocator;
  final LlamaHealthWaiter _healthWaiter;
  final LlamaModelProviderFactory _clientFactory;
  final ValueNotifier<LlamaServerHandle?> _handle = ValueNotifier(null);
  final ValueNotifier<ModelSessionState> _sessionNotifier = ValueNotifier(
    const ModelSessionState(),
  );
  late final ModelSessionPort _session = _ReadOnlyModelSession(
    _sessionNotifier,
  );
  final ModelSessionDiagnostics _diagnostics = ModelSessionDiagnostics();
  ModelProvider? _completionProvider;

  @override
  ModelSessionPort get session => _session;

  @override
  ModelSessionDiagnosticsPort get diagnostics => _diagnostics;

  @override
  ModelSessionTelemetryPort get telemetry => _diagnostics;

  @override
  ModelProvider? get completionProvider => _completionProvider;

  @override
  Future<ModelConfigurationAvailability> validateConfiguration(
    ModelConfigurationSnapshot snapshot,
  ) async {
    final modelExists = await File(snapshot.modelPath).exists();
    final mtpPath = snapshot.mtpModelPath;
    final mtpExists =
        !snapshot.mtpEnabled || mtpPath == null || await File(mtpPath).exists();
    return ModelConfigurationAvailability(
      modelPathMissing: !modelExists,
      mtpModelPathMissing: !mtpExists,
    );
  }

  /// Test-only injection for application tests that exercise chat behavior
  /// without launching a host process. Production code uses lifecycle start.
  @visibleForTesting
  void setCompletionProviderForTesting(ModelProvider? provider) {
    _completionProvider = provider;
    _sessionNotifier.value = ModelSessionState(isActive: provider != null);
  }

  @visibleForTesting
  void setSessionActiveForTesting(bool active) {
    _sessionNotifier.value = ModelSessionState(isActive: active);
  }

  LlamaServerManager({
    ModelDiagnosticBundleWriter? diagnosticBundleWriter,
    LlamaProcessLauncher? processLauncher,
    LlamaPortAllocator? portAllocator,
    LlamaHealthWaiter? healthWaiter,
    LlamaModelProviderFactory? clientFactory,
  }) : _processLauncher = processLauncher ?? _launchProcess,
       _portAllocator = portAllocator ?? _getFreePort,
       _healthWaiter = healthWaiter ?? _waitForHealth,
       _clientFactory = clientFactory ?? _defaultModelProviderFactory;

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
      mtpModelPath: snapshot.mtpModelPath,
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
    String? mtpModelPath,
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
      mtpModelPath: ModelConfigurationSnapshot.normaliseOptionalModelPath(
        mtpModelPath,
      ),
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
      _diagnostics.recordFailure(error);
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
      _diagnostics.recordFailure(error);
      throw error;
    }

    await _stopHandles();
    _throwIfCancelled(generation);

    for (var attempt = 1; attempt <= 3; attempt++) {
      final port = await _portAllocator();
      _throwIfCancelled(generation);
      final args = buildLlamaServerArguments(snapshot: snapshot, port: port);
      final baseUrl = 'http://127.0.0.1:$port';
      _diagnostics.recordStarting(
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
        _diagnostics.recordFailure(e);
        Error.throwWithStackTrace(e, stackTrace);
      }

      final startupOutput = _StartupOutput();
      final stdoutSub = process.stdout.transform(utf8.decoder).listen((line) {
        startupOutput.add(line);
        _diagnostics.addLog('stdout', line);
        if (kDebugMode) print(line);
      });
      final stderrSub = process.stderr.transform(utf8.decoder).listen((line) {
        startupOutput.add(line);
        _diagnostics.addLog('stderr', line);
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

        final newClient = _clientFactory(
          baseUrl: baseUrl,
          model: modelName,
          onDiagnostics: (value) {
            if (generation == _startGeneration) {
              _diagnostics.recordCallDiagnostics(value);
            }
          },
        );
        if (generation != _startGeneration) {
          newClient.dispose();
          throw const LlamaServerStartupCancelled();
        }

        _completionProvider = newClient;
        _startingHandle = null;
        _handle.value = newHandle;
        _sessionNotifier.value = ModelSessionState(
          snapshot: snapshot,
          isActive: true,
        );
        _diagnostics.recordReady();
        unawaited(_loadServerProperties(newClient, generation));
        return;
      } catch (e, stackTrace) {
        _completionProvider = null;
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
          _diagnostics.recordCancelled();
        } else {
          _diagnostics.recordFailure(
            e,
            recentOutput: startupOutput.recentOutput,
          );
        }
        Error.throwWithStackTrace(e, stackTrace);
      }
    }
  }

  Future<void> _loadServerProperties(
    ModelProvider client,
    int generation,
  ) async {
    final properties = await client.fetchServerProperties();
    if (properties == null ||
        generation != _startGeneration ||
        !identical(_completionProvider, client)) {
      return;
    }
    _diagnostics.recordServerProperties(properties);
  }

  Future<void> stop() async {
    _startGeneration++;
    await _stopHandles();
  }

  Future<void> _stopHandles() async {
    final startingHandle = _startingHandle;
    final currentHandle = _handle.value;
    final currentClient = _completionProvider;

    _startingHandle = null;
    _handle.value = null;
    _completionProvider = null;
    _sessionNotifier.value = const ModelSessionState();
    _diagnostics.recordStopped();

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
        if (_handle.value == serverHandle || _startingHandle == serverHandle) {
          _diagnostics.recordProcessExit(code);
        }
        if (_handle.value == serverHandle) {
          _completionProvider?.dispose();
          _completionProvider = null;
          _handle.value = null;
          _sessionNotifier.value = const ModelSessionState();
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

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await stop();
    _diagnostics.dispose();
  }
}

class _ReadOnlyModelSession implements ModelSessionPort {
  const _ReadOnlyModelSession(this._source);

  final ValueListenable<ModelSessionState> _source;

  @override
  ModelSessionState get value => _source.value;

  @override
  void addListener(VoidCallback listener) => _source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _source.removeListener(listener);
}

LlamaModelProviderFactory get _defaultModelProviderFactory =>
    ({required String baseUrl, required String model, onDiagnostics}) =>
        _PropertiesOnlyModelProvider(baseUrl);

/// Compatibility provider used when a manager is constructed outside the
/// composition root (for example in lifecycle tests). The real chat provider
/// is injected by the application composition root; this adapter only reads
/// `/props` so startup _diagnostics remain useful without importing the HTTP
/// chat implementation into the shared service.
class _PropertiesOnlyModelProvider implements ModelProvider {
  _PropertiesOnlyModelProvider(this._baseUrl);

  final String _baseUrl;
  bool _disposed = false;

  @override
  bool get supportsStreamingCancellation => false;

  @override
  void dispose() => _disposed = true;

  @override
  Future<LlamaServerProperties?> fetchServerProperties() async {
    if (_disposed) return null;
    try {
      final response = await http.get(Uri.parse('$_baseUrl/props'));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final raw = jsonDecode(response.body);
      if (raw is! Map) return null;
      final defaults = raw['default_generation_settings'];
      final model = raw['model'];
      final defaultMap = defaults is Map ? defaults : const {};
      final modelMap = model is Map ? model : const {};
      int? integer(Object? value) =>
          value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      return LlamaServerProperties(
        effectiveContextSize:
            integer(raw['n_ctx']) ??
            integer(defaultMap['n_ctx']) ??
            integer(modelMap['n_ctx_train']),
        totalSlots: integer(raw['total_slots']) ?? integer(raw['n_slots']),
        modelPath:
            raw['model_path']?.toString() ?? modelMap['path']?.toString(),
        buildInfo: raw['build_info']?.toString() ?? raw['build']?.toString(),
        chatTemplateCapabilities: raw['chat_template_caps'] is Map
            ? Map<String, dynamic>.from(raw['chat_template_caps'] as Map)
            : const {},
        modalities: raw['modalities'] is Map
            ? Map<String, dynamic>.from(raw['modalities'] as Map)
            : const {},
      );
    } catch (_) {
      return null;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('The compatibility model provider is read-only.');
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
