import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/ui/overlays/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService();
  });

  tearDown(() => preferences.dispose());

  testWidgets('renders question autonomy dropdown values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Settings(preferencesService: preferences)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Question autonomy'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);

    final dropdown = find.byType(DropdownButtonFormField<QuestionAutonomy>);
    final field = tester.widget<DropdownButtonFormField<QuestionAutonomy>>(
      dropdown,
    );
    expect(field.initialValue, QuestionAutonomy.balanced);
    expect(field.onChanged, isNotNull);

    expect(find.text('Plan revision approvals'), findsOneWidget);
    expect(find.text('High risk only'), findsOneWidget);
    final approvalDropdown = find.byType(
      DropdownButtonFormField<ProjectPlanApprovalPolicy>,
    );
    final approvalField = tester
        .widget<DropdownButtonFormField<ProjectPlanApprovalPolicy>>(
          approvalDropdown,
        );
    expect(approvalField.initialValue, ProjectPlanApprovalPolicy.highRiskOnly);
    expect(approvalField.onChanged, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
