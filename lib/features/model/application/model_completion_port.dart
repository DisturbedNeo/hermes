import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_call_diagnostics.dart';
import 'package:hermes/features/model/application/model_completion.dart';
import 'package:hermes/features/model/application/model_request.dart';

export 'package:hermes/features/model/application/model_request.dart';

/// Shared model-completion capability used by feature application services.
///
/// The model feature's [ModelProvider] extends this contract. Keeping this
/// smaller capability lets planning and compaction services remain
/// independent from the concrete model infrastructure.
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
