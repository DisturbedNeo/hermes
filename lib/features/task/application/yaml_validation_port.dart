/// Validates YAML text without exposing the parser or its document model to
/// task runtime code.
abstract interface class YamlValidationPort {
  void validate(String source);
}
