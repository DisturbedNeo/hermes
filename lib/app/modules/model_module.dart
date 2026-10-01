import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/features/model/infrastructure/llama_server_manager.dart';

/// Model lifecycle and completion capabilities owned by the composition root.
class ModelModule {
  ModelModule._({required this.manager});

  factory ModelModule.create() => ModelModule._(
    manager: LlamaServerManager(
      clientFactory: ({required baseUrl, required model, onDiagnostics}) =>
          ChatClient(
            baseUrl: baseUrl,
            model: model,
            onDiagnostics: onDiagnostics,
          ),
    ),
  );

  final LlamaServerManager manager;
}
