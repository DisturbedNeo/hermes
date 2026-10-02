import 'package:hermes/core/cancellation.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/model/application/model_call_diagnostics.dart';
import 'package:hermes/features/model/application/model_completion.dart';
import 'package:hermes/features/model/application/model_request.dart';

export 'package:hermes/features/model/application/model_request.dart';

/// Text and non-streaming completion capability.
abstract interface class ModelTextCompletionPort {
  Future<String> completeMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  });

  Future<ModelCompletion> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  });
}

/// Streaming completion capability, including provider cancellation support.
abstract interface class ModelStreamingPort {
  bool get supportsStreamingCancellation;

  Future<ModelCompletion> completeChatStreamed({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    void Function(ChatToken token)? onToken,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  });

  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  });
}

/// Exact or provider-backed context token counting.
abstract interface class ModelTokenCountingPort {
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  });
}

/// Read-only server capability metadata.
abstract interface class ModelMetadataPort {
  Future<LlamaServerProperties?> fetchServerProperties();
}

/// Provider lifecycle capability. Feature services should not own transport
/// handles; composition code owns and disposes the combined provider.
abstract interface class ModelLifecyclePort {
  void dispose();
}

/// Focused bundle for services that generate text and stream model output.
abstract interface class ModelGenerationPort
    implements ModelTextCompletionPort, ModelStreamingPort {}

/// Focused bundle for context compaction and token accounting.
abstract interface class ModelContextPort
    implements ModelTextCompletionPort, ModelTokenCountingPort {}

/// Focused bundle for chat generation, streaming, and token accounting.
abstract interface class ModelConversationPort
    implements ModelGenerationPort, ModelContextPort {}
