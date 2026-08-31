import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/server_health_checker.dart';
import 'package:hermes/core/models/llama_server_handle.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/llama_server_manager.dart';

void main() {
  const snapshot = ModelConfigurationSnapshot(
    modelName: 'model',
    modelPath: '/models/model.gguf',
    llamaCppDirectory: '/llama.cpp',
    nCtx: 8192,
    nThreads: 8,
    temperature: 0.7,
    topP: 0.8,
    topK: 20,
    minP: 0.0,
    nBatch: 2048,
    nUBatch: 512,
    mirostat: 0,
    repeatPenalty: 1,
    repeatLastN: 64,
    presencePenalty: 1.5,
    frequencyPenalty: 0,
    thinking: false,
    flashAttention: true,
    cachePrompt: true,
    cacheReuse: 256,
    kvCacheQuantizationEnabled: true,
    kvCacheTypeK: 'q4_0',
    kvCacheTypeV: 'q8_0',
  );

  test('builds llama-server startup arguments from the snapshot', () {
    final args = buildLlamaServerArguments(snapshot: snapshot, port: 12345);

    expect(_valueAfter(args, '-t'), '8');
    expect(_valueAfter(args, '--threads-batch'), '8');
    expect(_valueAfter(args, '-ngl'), 'all');
    expect(_valueAfter(args, '--load-mode'), 'dio');
    expect(args, isNot(contains('--no-mmap')));
    expect(_valueAfter(args, '--min-p'), '0.0');
    expect(args, contains('--flash-attn'));
    expect(_valueAfter(args, '--flash-attn'), 'on');
    expect(args, contains('--cache-prompt'));
    expect(_valueAfter(args, '--cache-reuse'), '256');
    expect(_valueAfter(args, '--cache-type-k'), 'q4_0');
    expect(_valueAfter(args, '--cache-type-v'), 'q8_0');
    expect(
      _valueAfter(args, '--chat-template-kwargs'),
      '{"enable_thinking": false}',
    );
  });

  test('sets disabled boolean startup flags explicitly', () {
    final args = buildLlamaServerArguments(
      snapshot: ModelJson.decode<ModelConfigurationSnapshot>({
        ...ModelJson.encode(snapshot),
        'thinking': true,
        'flashAttention': false,
        'cachePrompt': false,
        'kvCacheQuantizationEnabled': false,
        'mtpModelPath': '/models/mtp.gguf',
      }),
      port: 12345,
    );

    expect(args, contains('--flash-attn'));
    expect(_valueAfter(args, '--flash-attn'), 'off');
    expect(args, contains('--no-cache-prompt'));
    expect(args, isNot(contains('--cache-prompt')));
    expect(args, isNot(contains('--cache-reuse')));
    expect(args, isNot(contains('--chat-template-kwargs')));
    expect(args, isNot(contains('--cache-type-k')));
    expect(args, isNot(contains('--cache-type-v')));
    expect(args, isNot(contains('--reasoning-effort')));
    expect(args, isNot(contains('--spec-type')));
    expect(args, isNot(contains('--spec-draft-model')));
    expect(args, isNot(contains('--spec-draft-n-max')));
  });

  test('sets explicit reasoning effort and MTP startup flags', () {
    final args = buildLlamaServerArguments(
      snapshot: ModelJson.decode<ModelConfigurationSnapshot>({
        ...ModelJson.encode(snapshot),
        'thinking': true,
        'reasoningEffort': 'xhigh',
        'mtpEnabled': true,
        'mtpModelPath': '/models/mtp.gguf',
        'mtpDraftTokens': 7,
      }),
      port: 12345,
    );

    expect(_valueAfter(args, '--reasoning'), 'on');
    expect(_valueAfter(args, '--reasoning-effort'), 'xhigh');
    expect(_valueAfter(args, '--spec-draft-model'), '/models/mtp.gguf');
    expect(_valueAfter(args, '--spec-type'), 'draft-mtp');
    expect(_valueAfter(args, '--spec-draft-n-max'), '7');
    expect(args, isNot(contains('--chat-template-kwargs')));
  });

  test('uses the model reasoning default without an effort override', () {
    final args = buildLlamaServerArguments(
      snapshot: ModelJson.decode<ModelConfigurationSnapshot>({
        ...ModelJson.encode(snapshot),
        'thinking': true,
        'reasoningEffort': 'default',
      }),
      port: 12345,
    );

    expect(_valueAfter(args, '--reasoning'), 'on');
    expect(args, isNot(contains('--reasoning-effort')));
  });

  group('LlamaServerHandle', () {
    test('stops escalating as soon as the process exits', () async {
      for (final expected in [
        ProcessSignal.sigint,
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]) {
        final process = _FakeProcess(exitOn: expected);
        final handle = _handle(process);
        final first = handle.stop();
        final second = handle.stop();

        expect(identical(first, second), isTrue);
        await Future.wait([first, second]);

        expect(process.signals.last, expected);
        expect(process.signals, [
          ProcessSignal.sigint,
          if (expected != ProcessSignal.sigint) ProcessSignal.sigterm,
          if (expected == ProcessSignal.sigkill) ProcessSignal.sigkill,
        ]);
      }
    });

    test('does not signal a process that has already exited', () async {
      final process = _FakeProcess()..completeExit();

      await _handle(process).stop();

      expect(process.signals, isEmpty);
    });
  });

  test('repeated startup responses eventually hit the stall timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final process = _FakeProcess();
    final checker = ServerHealthChecker(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      process: process,
      healthRequestTimeout: const Duration(milliseconds: 100),
      startupStallTimeout: const Duration(milliseconds: 40),
    );

    await expectLater(
      checker.waitForReady(isCancelled: () => false),
      throwsA(isA<StateError>()),
    );
  });

  test('retries startup with a new port only after a bind collision', () async {
    final directory = await Directory.systemTemp.createTemp('hermes_llama_');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/llama-server').writeAsString('');
    final ports = [12001, 12002];
    final processes = <_FakeProcess>[];
    var launches = 0;
    final manager = LlamaServerManager(
      portAllocator: () async => ports.removeAt(0),
      processLauncher: (_, _, {workingDirectory}) async {
        final process = _FakeProcess(
          exitOn: ProcessSignal.sigint,
          stderrText: launches++ == 0 ? 'address already in use' : null,
        );
        processes.add(process);
        return process;
      },
      healthWaiter:
          ({
            required baseUrl,
            required process,
            required recentOutput,
            required isCancelled,
          }) async {
            await Future<void>.delayed(Duration.zero);
            if (recentOutput().contains('address already in use')) {
              throw StateError('llama-server exited before it was ready');
            }
          },
    );
    addTearDown(manager.dispose);

    await manager.start(
      llamaCppDirectory: directory.path,
      modelPath: '${directory.path}/model.gguf',
      modelName: 'model',
    );

    expect(launches, 2);
    expect(manager.diagnostics.port, 12002);
    expect(processes.first.signals, contains(ProcessSignal.sigint));
  });

  test(
    'enriches ready diagnostics from props without delaying startup',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        expect(request.uri.path, '/props');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'build_info': 'build-99',
              'model_path': '/effective/model.gguf',
              'total_slots': 2,
              'default_generation_settings': {'n_ctx': 16384},
              'chat_template_caps': {'tools': true},
              'modalities': {'text': true},
            }),
          );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final directory = await Directory.systemTemp.createTemp('hermes_props_');
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/llama-server').writeAsString('');
      final manager = LlamaServerManager(
        portAllocator: () async => server.port,
        processLauncher: (_, _, {workingDirectory}) async =>
            _FakeProcess(exitOn: ProcessSignal.sigint),
        healthWaiter:
            ({
              required baseUrl,
              required process,
              required recentOutput,
              required isCancelled,
            }) async {},
      );
      addTearDown(manager.dispose);

      await manager.start(
        llamaCppDirectory: directory.path,
        modelPath: '${directory.path}/model.gguf',
        modelName: 'model',
      );
      for (
        var i = 0;
        i < 20 && manager.diagnostics.serverProperties == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(manager.diagnostics.state, ModelServerState.ready);
      expect(manager.diagnostics.serverProperties?.buildInfo, 'build-99');
      expect(manager.diagnostics.serverProperties?.effectiveContextSize, 16384);
      expect(manager.diagnostics.serverProperties?.totalSlots, 2);
      expect(manager.diagnostics.contextLimitTokens, 16384);
    },
  );
}

String _valueAfter(List<String> args, String flag) {
  final index = args.indexOf(flag);
  expect(index, isNot(-1));
  expect(index + 1, lessThan(args.length));
  return args[index + 1];
}

LlamaServerHandle _handle(_FakeProcess process) {
  return LlamaServerHandle(
    process: process,
    stdoutSub: const Stream<List<int>>.empty().listen((_) {}),
    stderrSub: const Stream<List<int>>.empty().listen((_) {}),
    interruptGrace: const Duration(milliseconds: 5),
    terminateGrace: const Duration(milliseconds: 5),
    killGrace: const Duration(milliseconds: 5),
  );
}

class _FakeProcess implements Process {
  _FakeProcess({this.exitOn, this.stderrText});

  final ProcessSignal? exitOn;
  final String? stderrText;
  final Completer<int> _exitCode = Completer<int>();
  final StreamController<List<int>> _stdin = StreamController<List<int>>();
  final List<ProcessSignal> signals = [];

  void completeExit() {
    if (!_exitCode.isCompleted) _exitCode.complete(0);
  }

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 42;

  @override
  IOSink get stdin => IOSink(_stdin.sink);

  @override
  Stream<List<int>> get stderr => stderrText == null
      ? const Stream.empty()
      : Stream.value(utf8.encode(stderrText!));

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == exitOn) completeExit();
    return true;
  }
}
