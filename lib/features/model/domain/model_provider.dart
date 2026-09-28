import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/models/model_call_diagnostics.dart';
import 'package:hermes/features/model/domain/model_completion.dart';
import 'package:hermes/features/model/domain/model_request.dart';

/// Typed application port for model completions.
///
/// Application code depends on this contract, never on HTTP or ChatClient.
abstract interface class ModelProvider {
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
