import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job_system_settings.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesService job system settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns default job settings', () async {
      final settings = await PreferencesService().getJobSystemSettings();

      expect(settings.enabled, isTrue);
      expect(settings.requireApprovalBeforeFileEdits, isTrue);
      expect(settings.showJobMessagesInChat, isTrue);
    });

    test('persists normalised job settings', () async {
      final service = PreferencesService();

      final saved = await service.setJobSystemSettings(
        const JobSystemSettings(
          enabled: false,
          requireApprovalBeforeFileEdits: false,
          showJobMessagesInChat: false,
        ),
      );

      final settings = await service.getJobSystemSettings();
      expect(saved, isTrue);
      expect(settings.enabled, isFalse);
      expect(settings.requireApprovalBeforeFileEdits, isFalse);
      expect(settings.showJobMessagesInChat, isFalse);
    });
  });
}
