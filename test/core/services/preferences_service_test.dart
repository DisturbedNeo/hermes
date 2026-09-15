import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/preferences_keys.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_load_configuration.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesService task system settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns default task settings', () async {
      final settings = await PreferencesService().getTaskSystemSettings();

      expect(settings.enabled, isTrue);
      expect(settings.requireApprovalBeforeFileEdits, isTrue);
      expect(settings.showTaskMessagesInChat, isTrue);
      expect(settings.maxProjectTasksPerRun, 5);
      expect(settings.maxProjectIterations, 25);
      expect(settings.questionAutonomy, QuestionAutonomy.balanced);
      expect(
        settings.planApprovalPolicy,
        ProjectPlanApprovalPolicy.highRiskOnly,
      );
    });

    test('persists configurable task limits', () async {
      final service = PreferencesService();

      final saved = await service.setTaskSystemSettings(
        const TaskSystemSettings(
          enabled: false,
          requireApprovalBeforeFileEdits: false,
          showTaskMessagesInChat: false,
          maxProjectTasksPerRun: 99,
          maxProjectIterations: 0,
          questionAutonomy: QuestionAutonomy.autonomous,
          planApprovalPolicy: ProjectPlanApprovalPolicy.never,
        ),
      );

      final settings = await service.getTaskSystemSettings();
      expect(saved, isTrue);
      expect(settings.enabled, isFalse);
      expect(settings.requireApprovalBeforeFileEdits, isFalse);
      expect(settings.showTaskMessagesInChat, isFalse);
      expect(settings.maxProjectTasksPerRun, 99);
      expect(settings.maxProjectIterations, 0);
      expect(settings.questionAutonomy, QuestionAutonomy.autonomous);
      expect(settings.planApprovalPolicy, ProjectPlanApprovalPolicy.never);
    });
  });

  group('PreferencesService model load configurations', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('stores configurations independently by exact alias', () async {
      final service = PreferencesService();
      final alpha = _configuration(
        temperature: 0.4,
        reasoningEffort: 'high',
        mtpEnabled: true,
        mtpModelPath: '/models/mtp.gguf',
        mtpDraftTokens: 7,
      );
      final upperAlpha = _configuration(temperature: 1.2);

      expect(await service.setModelLoadConfiguration('alpha', alpha), isTrue);
      expect(
        await service.setModelLoadConfiguration('Alpha', upperAlpha),
        isTrue,
      );

      expect(
        (await service.getModelLoadConfiguration('alpha'))?.temperature,
        0.4,
      );
      final restoredAlpha = await service.getModelLoadConfiguration('alpha');
      expect(restoredAlpha?.reasoningEffort, 'high');
      expect(restoredAlpha?.mtpEnabled, isTrue);
      expect(restoredAlpha?.mtpModelPath, '/models/mtp.gguf');
      expect(restoredAlpha?.mtpDraftTokens, 7);
      expect(
        (await service.getModelLoadConfiguration('Alpha'))?.temperature,
        1.2,
      );
      expect(await service.getModelLoadConfiguration('missing'), isNull);
    });

    test(
      'overwrites and removes one alias without affecting another',
      () async {
        final service = PreferencesService();
        await service.setModelLoadConfiguration(
          'alpha',
          _configuration(temperature: 0.4),
        );
        await service.setModelLoadConfiguration(
          'beta',
          _configuration(temperature: 0.8),
        );
        await service.setModelLoadConfiguration(
          'alpha',
          _configuration(temperature: 1.1),
        );

        expect(
          (await service.getModelLoadConfiguration('alpha'))?.temperature,
          1.1,
        );
        expect(await service.removeModelLoadConfiguration('alpha'), isTrue);
        expect(await service.getModelLoadConfiguration('alpha'), isNull);
        expect(
          (await service.getModelLoadConfiguration('beta'))?.temperature,
          0.8,
        );
      },
    );

    test('returns null for malformed persisted JSON', () async {
      SharedPreferences.setMockInitialValues({
        '${PreferencesKeys.modelLoadConfigurationPrefix}broken': '{nope',
      });

      expect(
        await PreferencesService().getModelLoadConfiguration('broken'),
        isNull,
      );
    });
  });
}

ModelLoadConfiguration _configuration({
  required double temperature,
  String reasoningEffort = ModelLoadConfiguration.defaultReasoningEffort,
  bool mtpEnabled = ModelLoadConfiguration.defaultMtpEnabled,
  String? mtpModelPath,
  int mtpDraftTokens = ModelLoadConfiguration.defaultMtpDraftTokens,
}) => ModelLoadConfiguration(
  nCtx: ModelLoadConfiguration.defaultNCtx,
  nThreads: Platform.numberOfProcessors,
  temperature: temperature,
  topP: ModelLoadConfiguration.defaultTopP,
  topK: ModelLoadConfiguration.defaultTopK,
  minP: ModelLoadConfiguration.defaultMinP,
  nBatch: ModelLoadConfiguration.defaultNBatch,
  nUBatch: ModelLoadConfiguration.defaultNUBatch,
  mirostat: ModelLoadConfiguration.defaultMirostat,
  repeatPenalty: ModelLoadConfiguration.defaultRepeatPenalty,
  repeatLastN: ModelLoadConfiguration.defaultRepeatLastN,
  presencePenalty: ModelLoadConfiguration.defaultPresencePenalty,
  frequencyPenalty: ModelLoadConfiguration.defaultFrequencyPenalty,
  thinking: ModelLoadConfiguration.defaultThinking,
  reasoningEffort: reasoningEffort,
  mtpEnabled: mtpEnabled,
  mtpModelPath: mtpModelPath,
  mtpDraftTokens: mtpDraftTokens,
  flashAttention: ModelLoadConfiguration.defaultFlashAttention,
  cachePrompt: ModelLoadConfiguration.defaultCachePrompt,
  cacheReuse: ModelConfigurationSnapshot.defaultCacheReuse,
  kvCacheQuantizationEnabled:
      ModelLoadConfiguration.defaultKvCacheQuantizationEnabled,
  kvCacheTypeK: ModelLoadConfiguration.defaultKvCacheType,
  kvCacheTypeV: ModelLoadConfiguration.defaultKvCacheType,
);
