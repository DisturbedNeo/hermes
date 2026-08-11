import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DTO source files contain no handwritten JSON methods', () async {
    const dtoSources = [
      'lib/core/models/chat_message.dart',
      'lib/core/models/model_configuration_snapshot.dart',
      'lib/core/models/model_load_configuration.dart',
      'lib/core/models/project.dart',
      'lib/core/models/system_prompt.dart',
      'lib/core/models/task.dart',
      'lib/core/helpers/chat/context_summary_prompt.dart',
      'lib/core/services/question_policy_service.dart',
      'lib/core/services/task_system/task_service.dart',
      'lib/core/tools/calculator_tool.dart',
    ];

    for (final path in dtoSources) {
      final source = await File(path).readAsString();
      expect(
        source,
        isNot(matches(RegExp(r'\b(?:fromJson|toJson)\s*\('))),
        reason: '$path must use ModelJson and generated mappers.',
      );
    }
  });

  test('application code does not call per-model JSON methods', () async {
    final violations = <String>[];
    await for (final entity in Directory('lib').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.mapper.dart') ||
          entity.path.endsWith('.init.dart') ||
          entity.path.endsWith('model_json.dart')) {
        continue;
      }
      final source = await entity.readAsString();
      if (RegExp(r'\.(?:fromJson|toJson)\s*\(').hasMatch(source)) {
        violations.add(entity.path);
      }
    }

    expect(violations, isEmpty);
  });

  test('committed mapper outputs and package initializer exist', () {
    for (final path in [
      'lib/core/models/task.mapper.dart',
      'lib/core/models/project.mapper.dart',
      'lib/core/models/system_prompt.mapper.dart',
      'lib/core/models/model_configuration_snapshot.mapper.dart',
      'lib/core/models/model_load_configuration.mapper.dart',
      'lib/core/serialization/mappers.init.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing.');
    }
  });
}
