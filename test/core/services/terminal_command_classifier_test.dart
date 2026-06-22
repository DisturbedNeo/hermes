import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';

void main() {
  group('TerminalCommandClassifier', () {
    test('classifies common read-only commands', () {
      expect(
        TerminalCommandClassifier.classify('rg "TaskService" lib'),
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

    test('blocks dangerous terminal commands by default', () {
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'rm',
          arguments: ['generated.txt'],
        ),
        contains('File deletion commands'),
      );
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'git',
          arguments: ['clean', '-fd'],
        ),
        contains('git clean'),
      );
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'find',
          arguments: ['.', '-delete'],
        ),
        contains('find -delete'),
      );
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'sudo',
          arguments: ['apt', 'install', 'package'],
        ),
        contains('Privilege escalation'),
      );
    });

    test('blocks dangerous commands hidden behind shell wrappers', () {
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'bash',
          arguments: ['-lc', 'echo ok && rm generated.txt'],
        ),
        contains('File deletion commands'),
      );
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'cmd',
          arguments: ['/c', 'del generated.txt'],
        ),
        contains('File deletion commands'),
      );
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'pwsh',
          arguments: ['-Command', 'Remove-Item generated.txt'],
        ),
        contains('File deletion commands'),
      );
    });

    test('does not block ordinary read-only commands', () {
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'rg',
          arguments: ['needle', 'lib'],
        ),
        isNull,
      );
      expect(
        TerminalCommandClassifier.blockedReason(
          executable: 'git',
          arguments: ['status', '--short'],
        ),
        isNull,
      );
    });
  });
}
