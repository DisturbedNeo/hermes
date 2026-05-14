import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';

void main() {
  group('TerminalCommandClassifier', () {
    test('classifies common read-only commands', () {
      expect(
        TerminalCommandClassifier.classify('rg "JobService" lib'),
        TerminalCommandClass.readOnly,
      );
      expect(
        TerminalCommandClassifier.classify('git status --short'),
        TerminalCommandClass.readOnly,
      );
      expect(
        TerminalCommandClassifier.classify('sed -n "1,20p" lib/main.dart'),
        TerminalCommandClass.readOnly,
      );
    });

    test('classifies mutating workspace commands', () {
      expect(
        TerminalCommandClassifier.classify('rm generated.txt'),
        TerminalCommandClass.mutatingWorkspace,
      );
      expect(
        TerminalCommandClassifier.classify('sed -i s/old/new/ file.txt'),
        TerminalCommandClass.mutatingWorkspace,
      );
      expect(
        TerminalCommandClassifier.classify(
          'bash -lc "printf changed > sneaky.txt"',
        ),
        TerminalCommandClass.mutatingWorkspace,
      );
    });

    test('classifies dependency, test, build, and git commands', () {
      expect(
        TerminalCommandClassifier.classify('npm install'),
        TerminalCommandClass.dependencyInstall,
      );
      expect(
        TerminalCommandClassifier.classify('flutter test'),
        TerminalCommandClass.testCommand,
      );
      expect(
        TerminalCommandClassifier.classify('npm run build'),
        TerminalCommandClass.buildCommand,
      );
      expect(
        TerminalCommandClassifier.classify('git checkout -b feature'),
        TerminalCommandClass.gitCommand,
      );
    });
  });
}
