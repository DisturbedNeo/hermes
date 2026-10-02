import 'package:hermes/features/model/application/model_capabilities.dart';

export 'package:hermes/features/model/application/model_request.dart';
export 'package:hermes/features/model/application/model_capabilities.dart';

/// Shared model-completion capability used by feature application services.
///
/// The model feature's [ModelProvider] extends this contract. Keeping this
/// smaller capability lets planning and compaction services remain
/// independent from the concrete model infrastructure.
abstract interface class ModelCompletionPort
    implements
        ModelConversationPort,
        ModelContextPort,
        ModelMetadataPort,
        ModelLifecyclePort {}
