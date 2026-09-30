import 'package:hermes/shared_kernel/chat_message.dart';
import 'package:hermes/shared_kernel/chat_token.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_call_diagnostics.dart';
import 'package:hermes/shared_kernel/model_completion.dart';
import 'package:hermes/shared_kernel/model_request.dart';

/// Shared model-completion capability used by generic kernel services.
///
/// The model feature's [ModelProvider] extends this contract. Keeping this
/// smaller capability in the shared kernel lets generic planning and
/// compaction services remain independent from feature ownership.
abstract interface class ModelCompletionPort {
  bool get supportsStreamingCancellation;

  void dispose();

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

  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  });

  Future<LlamaServerProperties?> fetchServerProperties();
}
