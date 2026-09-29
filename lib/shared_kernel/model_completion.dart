import 'package:hermes/shared_kernel/model_call_diagnostics.dart';

/// Framework-independent result returned by a model provider.
class ModelCompletion {
  final String content;
  final String reasoning;
  final List<ModelToolCall> toolCalls;
  final ModelCallDiagnostics? diagnostics;

  const ModelCompletion({
    required this.content,
    this.reasoning = '',
    this.toolCalls = const [],
    this.diagnostics,
  });

  ModelCompletion copyWith({ModelCallDiagnostics? diagnostics}) =>
      ModelCompletion(
        content: content,
        reasoning: reasoning,
        toolCalls: toolCalls,
        diagnostics: diagnostics ?? this.diagnostics,
      );
}

class ModelToolCall {
  final String? id;
  final String name;
  final String arguments;

  const ModelToolCall({required this.name, this.id, this.arguments = '{}'});
}

typedef ChatCompletionResponse = ModelCompletion;
typedef ChatCompletionToolCall = ModelToolCall;
