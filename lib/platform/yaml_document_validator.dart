import 'package:yaml/yaml.dart';

import 'package:hermes/features/task/application/yaml_validation_port.dart';

class YamlDocumentValidator implements YamlValidationPort {
  const YamlDocumentValidator();

  @override
  void validate(String source) {
    loadYaml(source);
  }
}
