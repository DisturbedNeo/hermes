import 'package:flutter_test/flutter_test.dart';
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
    });

    test('persists normalised task settings', () async {
      final service = PreferencesService();

      final saved = await service.setTaskSystemSettings(
        const TaskSystemSettings(
          enabled: false,
          requireApprovalBeforeFileEdits: false,
          showTaskMessagesInChat: false,
          maxProjectTasksPerRun: 99,
        ),
      );

      final settings = await service.getTaskSystemSettings();
      expect(saved, isTrue);
      expect(settings.enabled, isFalse);
      expect(settings.requireApprovalBeforeFileEdits, isFalse);
      expect(settings.showTaskMessagesInChat, isFalse);
      expect(settings.maxProjectTasksPerRun, 25);
    });
  });
}
