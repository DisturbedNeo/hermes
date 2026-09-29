import 'package:hermes/shared_kernel/model_provider.dart' as shared;

/// Model completion contract owned by the model feature.
///
/// The shared contract remains available to generic planning values while all
/// model implementations and lifecycle adapters implement this feature port.
abstract interface class ModelProvider implements shared.ModelProvider {}
