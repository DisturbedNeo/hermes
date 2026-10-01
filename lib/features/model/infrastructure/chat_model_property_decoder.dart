import 'package:hermes/features/model/application/model_call_diagnostics.dart';

/// Decodes the local model server's property document into a typed value.
/// Transport JSON remains confined to this infrastructure adapter.
class ChatModelPropertyDecoder {
  const ChatModelPropertyDecoder();

  LlamaServerProperties decode(Map decoded) {
    final defaults = decoded['default_generation_settings'];
    final defaultMap = defaults is Map ? defaults : const <dynamic, dynamic>{};
    final model = decoded['model'];
    final modelMap = model is Map ? model : const <dynamic, dynamic>{};
    final capabilities = decoded['chat_template_caps'];
    final modalities = decoded['modalities'];

    return LlamaServerProperties(
      effectiveContextSize:
          _int(decoded['n_ctx']) ??
          _int(defaultMap['n_ctx']) ??
          _int(modelMap['n_ctx_train']),
      totalSlots: _int(decoded['total_slots']) ?? _int(decoded['n_slots']),
      modelPath:
          decoded['model_path']?.toString() ?? modelMap['path']?.toString(),
      buildInfo:
          decoded['build_info']?.toString() ??
          decoded['build']?.toString() ??
          decoded['version']?.toString(),
      chatTemplateCapabilities: capabilities is Map
          ? capabilities.map((key, value) => MapEntry(key.toString(), value))
          : const {},
      modalities: modalities is Map
          ? modalities.map((key, value) => MapEntry(key.toString(), value))
          : modalities is List
          ? {'supported': List<Object?>.from(modalities)}
          : const {},
    );
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
