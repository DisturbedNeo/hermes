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
      expect(
        TerminalCommandClassifier.classify('dart --version'),
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
      expect(
        TerminalCommandClassifier.classify('dart analyze && rm output.txt'),
        TerminalCommandClass.unknown,
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

    test('blocks generated and inline interpreter commands', () {
      expect(
        TerminalCommandClassifier.blockedReasonForCommand(
          "find . -name '*.tmp' | xargs rm",
        ),
        contains('xargs'),
      );

      for (final command in const [
        'python -c "print(1)"',
        'python3 -c "print(1)"',
        'node -e "console.log(1)"',
        'node --eval "console.log(1)"',
        'node -p "1 + 1"',
        'node --print "1 + 1"',
        'perl -e "print 1"',
        'ruby -e "puts 1"',
        'lua -e "print(1)"',
        'php -r "echo 1;"',
      ]) {
        expect(
          TerminalCommandClassifier.blockedReasonForCommand(command),
          contains('Inline interpreter code'),
          reason: command,
        );
      }

      expect(
        TerminalCommandClassifier.blockedReasonForCommand(
          'python3 scripts/check.py',
        ),
        isNull,
      );
    });

    test('unwraps common process wrappers recursively', () {
      for (final command in const [
        'nohup rm generated.txt',
        'nice -n 10 rm generated.txt',
        'ionice -c 3 rm generated.txt',
        'stdbuf -oL rm generated.txt',
        'timeout 5 rm generated.txt',
        'env FOO=bar timeout 5 nice -n 2 rm generated.txt',
      ]) {
        expect(
          TerminalCommandClassifier.blockedReasonForCommand(command),
          contains('File deletion commands'),
          reason: command,
        );
      }

      for (final command in const [
        'nohup dart --version',
        'nice -n 10 dart --version',
        'ionice -c 3 dart --version',
        'stdbuf -oL dart --version',
        'timeout 5 dart --version',
      ]) {
        expect(
          TerminalCommandClassifier.blockedReasonForCommand(command),
          isNull,
          reason: command,
        );
      }

      for (final command in const [
        'nohup --bad dart --version',
        'nice -n',
        'ionice -c',
        'stdbuf dart --version',
        'timeout --signal',
        'timeout not-a-duration dart --version',
      ]) {
        expect(
          TerminalCommandClassifier.blockedReasonForCommand(command),
          contains('could not be classified safely'),
          reason: command,
        );
      }
    });

    test('blocks shell command substitution', () {
      expect(
        TerminalCommandClassifier.blockedReasonForCommand(
          'echo \$(rm generated.txt)',
        ),
        contains('command substitution'),
      );
      expect(
        TerminalCommandClassifier.blockedReasonForCommand(
          'echo `rm generated.txt`',
        ),
        contains('command substitution'),
      );
      expect(
        TerminalCommandClassifier.blockedReasonForCommand(
          'cat <(rm generated.txt)',
        ),
        contains('command substitution'),
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
