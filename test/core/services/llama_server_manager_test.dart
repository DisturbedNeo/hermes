import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/llama_server_manager.dart';

void main() {
  const snapshot = ModelConfigurationSnapshot(
    modelName: 'model',
    modelPath: '/models/model.gguf',
    llamaCppDirectory: '/llama.cpp',
    nCtx: 8192,
    nThreads: 8,
    nGpuLayers: 999,
    temperature: 0.7,
    topP: 0.8,
    topK: 20,
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
  });
}

String _valueAfter(List<String> args, String flag) {
  final index = args.indexOf(flag);
  expect(index, isNot(-1));
  expect(index + 1, lessThan(args.length));
  return args[index + 1];
}
