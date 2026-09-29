import 'package:flutter/foundation.dart';
import 'package:hermes/features/model/application/llama_server_handle.dart';
import 'package:hermes/features/model/application/model_session_diagnostics.dart';
import 'package:hermes/shared_kernel/disposable.dart';
import 'package:hermes/shared_kernel/model_configuration.dart';
import 'package:hermes/features/model/domain/model_provider.dart';

/// Application-facing lifecycle port for the local model server.
///
/// Chat depends on this capability rather than on process or HTTP adapters.
abstract interface class ModelServerPort implements Disposable {
  ValueNotifier<LlamaServerHandle?> get handle;
  ModelSessionDiagnostics get diagnostics;
  ModelProvider? get chatClient;
  set chatClient(ModelProvider? value);
  String? get currentModelName;
  set currentModelName(String? value);
  LlamaServerHandle? get current;

  Future<void> startWithSnapshot(ModelConfigurationSnapshot snapshot);

  Future<void> stop();
}
