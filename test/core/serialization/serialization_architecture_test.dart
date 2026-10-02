import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DTO source files contain no handwritten JSON methods', () async {
    const dtoSources = [
      'lib/features/chat/application/contracts/chat_message.dart',
      'lib/features/model/application/model_configuration.dart',
      'lib/features/model/application/model_load_configuration.dart',
      'lib/features/project/application/contracts/project_snapshot_models.dart',
      'lib/features/chat/application/contracts/system_prompt.dart',
      'lib/features/task/application/contracts/task_snapshot_models.dart',
      'lib/features/chat/application/protocol/context_summary_prompt.dart',
      'lib/features/task/application/contracts/question_policy_service.dart',
      'lib/features/task/application/contracts/task_planning_models.dart',
      'lib/platform/tools/calculator_tool.dart',
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
    // Persistence-facing state contracts own generated wire mappers. The
    // aggregate DTOs themselves are explicit infrastructure codecs.
    for (final path in [
      'lib/features/task/application/contracts/task_state_models.mapper.dart',
      'lib/features/project/application/contracts/project_state_models.mapper.dart',
      'lib/features/chat/application/contracts/system_prompt.mapper.dart',
      'lib/features/model/application/model_configuration.mapper.dart',
      'lib/features/model/application/model_load_configuration.mapper.dart',
      'lib/app/mappers.init.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing.');
    }
    for (final path in [
      'lib/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart',
      'lib/features/persistence/infrastructure/dto/project_snapshot_dto.dart',
      'lib/features/persistence/infrastructure/dto/task_snapshot_dto.dart',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path is missing.');
    }
  });
}
