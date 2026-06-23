import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/services/question_policy_service.dart';

void main() {
  group('QuestionPolicyService', () {
    const service = QuestionPolicyService();

    test(
      'downgrades prioritization questions in balanced and autonomous modes',
      () {
        final question = AgentQuestion.fromText(
          'Which UI component should I prioritise?',
        );

        expect(
          service
              .decide(question: question, autonomy: QuestionAutonomy.balanced)
              .shouldBlock,
          isFalse,
        );
        expect(
          service
              .decide(question: question, autonomy: QuestionAutonomy.autonomous)
              .shouldBlock,
          isFalse,
        );
      },
    );

    test(
      'blocks destructive, credential, and scope questions in all modes',
      () {
        for (final text in const [
          'Should I delete the production database?',
          'What API key should I use?',
          'Should I expand the scope beyond the requested feature?',
        ]) {
          for (final autonomy in QuestionAutonomy.values) {
            expect(
              service
                  .decide(
                    question: AgentQuestion.fromText(text),
                    autonomy: autonomy,
                  )
                  .shouldBlock,
              isTrue,
            );
          }
        }
      },
    );

    test('conservative blocks more ambiguous questions than balanced', () {
      final question = AgentQuestion.fromText(
        'Which architecture should I use?',
      );

      expect(
        service
            .decide(question: question, autonomy: QuestionAutonomy.conservative)
            .shouldBlock,
        isTrue,
      );
      expect(
        service
            .decide(question: question, autonomy: QuestionAutonomy.balanced)
            .shouldBlock,
        isFalse,
      );
    });
  });
}
