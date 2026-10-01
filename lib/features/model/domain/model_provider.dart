import 'package:hermes/features/model/application/model_completion_port.dart';

/// Model completion contract owned by the model feature.
///
/// Implementations and lifecycle adapters belong to this feature; generic
/// kernel services depend only on [ModelCompletionPort].
abstract interface class ModelProvider implements ModelCompletionPort {}
