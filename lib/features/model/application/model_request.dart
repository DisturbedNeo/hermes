import 'package:hermes/features/tools/application/tool_contracts.dart';

/// Typed options for one model completion capability.
///
/// The HTTP/llama request document is assembled by the model infrastructure
/// adapter. Application code can select supported capabilities without
/// constructing transport option maps.
class ModelRequestOptions {
  const ModelRequestOptions({
    this.addGenerationPrompt,
    this.tools = const [],
    this.toolChoice,
    this.maxTokens,
    this.temperature,
    this.streamOptions,
    this.chatTemplate,
  });

  const ModelRequestOptions.empty()
    : addGenerationPrompt = null,
      tools = const [],
      toolChoice = null,
      maxTokens = null,
      temperature = null,
      streamOptions = null,
      chatTemplate = null;

  final bool? addGenerationPrompt;
  final List<ToolDefinition> tools;
  final String? toolChoice;
  final int? maxTokens;
  final double? temperature;
  final ModelStreamOptions? streamOptions;
  final ModelChatTemplateOptions? chatTemplate;

  bool get isEmpty =>
      addGenerationPrompt == null &&
      tools.isEmpty &&
      toolChoice == null &&
      maxTokens == null &&
      temperature == null &&
      streamOptions == null &&
      chatTemplate == null;

  bool get isNotEmpty => !isEmpty;
}

/// Typed stream diagnostics options understood by the local model server.
class ModelStreamOptions {
  const ModelStreamOptions({this.custom = const []});

  final List<ModelStreamOption> custom;
}

class ModelStreamOption {
  const ModelStreamOption({required this.name, required this.value});

  final String name;
  final Object? value;
}

/// Typed chat-template controls understood by llama-server.
class ModelChatTemplateOptions {
  const ModelChatTemplateOptions({this.enableThinking, this.reasoningBudget});

  final bool? enableThinking;
  final int? reasoningBudget;
}
