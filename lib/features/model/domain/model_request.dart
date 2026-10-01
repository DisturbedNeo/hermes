import 'package:hermes/features/tools/application/tool_contracts.dart';

/// Typed options for one model completion capability.
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

class ModelStreamOptions {
  const ModelStreamOptions({this.custom = const []});

  final List<ModelStreamOption> custom;
}

class ModelStreamOption {
  const ModelStreamOption({required this.name, required this.value});

  final String name;
  final Object? value;
}

class ModelChatTemplateOptions {
  const ModelChatTemplateOptions({this.enableThinking, this.reasoningBudget});

  final bool? enableThinking;
  final int? reasoningBudget;
}
