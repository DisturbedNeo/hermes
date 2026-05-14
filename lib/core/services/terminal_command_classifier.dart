enum TerminalCommandClass {
  readOnly,
  mutatingWorkspace,
  dependencyInstall,
  testCommand,
  buildCommand,
  gitCommand,
  unknown,
}

extension TerminalCommandClassWire on TerminalCommandClass {
  String get wire => switch (this) {
    TerminalCommandClass.readOnly => 'read_only',
    TerminalCommandClass.mutatingWorkspace => 'mutating_workspace',
    TerminalCommandClass.dependencyInstall => 'dependency_install',
    TerminalCommandClass.testCommand => 'test_command',
    TerminalCommandClass.buildCommand => 'build_command',
    TerminalCommandClass.gitCommand => 'git_command',
    TerminalCommandClass.unknown => 'unknown',
  };
}

class TerminalCommandClassifier {
  const TerminalCommandClassifier._();

  static TerminalCommandClass classify(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return TerminalCommandClass.unknown;
    if (_hasWorkspaceWriteSyntax(trimmed)) {
      return TerminalCommandClass.mutatingWorkspace;
    }
    return _classifyTokens(_tokenize(trimmed));
  }

  static bool isClearlyMutating(TerminalCommandClass commandClass) {
    return commandClass == TerminalCommandClass.mutatingWorkspace ||
        commandClass == TerminalCommandClass.dependencyInstall;
  }

  static TerminalCommandClass _classifyTokens(List<String> rawTokens) {
    final tokens = _stripWrappers(rawTokens);
    if (tokens.isEmpty) return TerminalCommandClass.unknown;

    final executable = tokens.first;
    final args = tokens.skip(1).toList();

    if (const {'sh', 'bash', 'zsh'}.contains(executable)) {
      final commandIndex = args.indexWhere(
        (arg) => arg == '-c' || arg == '-lc' || arg == '-ec',
      );
      if (commandIndex >= 0 && commandIndex + 1 < args.length) {
        return classify(args.skip(commandIndex + 1).join(' '));
      }
      return TerminalCommandClass.unknown;
    }

    if (executable == 'git') return _classifyGit(args);
    if (_isDependencyCommand(executable, args)) {
      return TerminalCommandClass.dependencyInstall;
    }
    if (_isMutatingCommand(executable, args)) {
      return TerminalCommandClass.mutatingWorkspace;
    }
    if (_isTestCommand(executable, args)) {
      return TerminalCommandClass.testCommand;
    }
    if (_isBuildCommand(executable, args)) {
      return TerminalCommandClass.buildCommand;
    }
    if (_isReadOnlyCommand(executable, args)) {
      return TerminalCommandClass.readOnly;
    }
    return TerminalCommandClass.unknown;
  }

  static TerminalCommandClass _classifyGit(List<String> args) {
    if (args.isEmpty) return TerminalCommandClass.gitCommand;
    final subcommand = args.first;
    if (const {
      'status',
      'log',
      'show',
      'diff',
      'grep',
      'ls-files',
      'rev-parse',
      'remote',
    }.contains(subcommand)) {
      return TerminalCommandClass.readOnly;
    }
    if (subcommand == 'branch' &&
        !args.any(
          (arg) =>
              arg == '-d' ||
              arg == '-D' ||
              arg == '-m' ||
              arg == '-M' ||
              arg == '--delete' ||
              arg == '--move',
        )) {
      return TerminalCommandClass.readOnly;
    }
    return TerminalCommandClass.gitCommand;
  }

  static bool _isReadOnlyCommand(String executable, List<String> args) {
    if (const {
      'ls',
      'pwd',
      'cat',
      'grep',
      'egrep',
      'fgrep',
      'rg',
      'find',
      'head',
      'tail',
      'wc',
      'awk',
      'cut',
      'sort',
      'uniq',
      'file',
      'du',
      'stat',
      'which',
      'whereis',
      'tree',
      'printenv',
      'env',
    }.contains(executable)) {
      if (executable == 'find' && args.contains('-delete')) return false;
      return true;
    }
    if ((executable == 'sed' || executable == 'perl') &&
        !args.any((arg) => arg == '-i' || arg.startsWith('-i'))) {
      return true;
    }
    return false;
  }

  static bool _isMutatingCommand(String executable, List<String> args) {
    if (const {
      'rm',
      'mv',
      'cp',
      'mkdir',
      'rmdir',
      'touch',
      'chmod',
      'chown',
      'ln',
      'truncate',
      'dd',
      'tee',
      'patch',
      'rsync',
      'unzip',
    }.contains(executable)) {
      return true;
    }
    if (executable == 'tar' &&
        args.any((arg) => arg.contains('x') || arg == '--extract')) {
      return true;
    }
    if ((executable == 'sed' || executable == 'perl') &&
        args.any((arg) => arg == '-i' || arg.startsWith('-i'))) {
      return true;
    }
    if (const {'dart', 'dotnet', 'cargo', 'go', 'ruff'}.contains(executable) &&
        args.contains('format')) {
      return true;
    }
    if (executable == 'flutter' && args.contains('format')) return true;
    if (const {'prettier', 'black', 'isort'}.contains(executable)) return true;
    if (executable == 'eslint' && args.contains('--fix')) return true;
    if (executable == 'npm' || executable == 'pnpm' || executable == 'yarn') {
      return _scriptName(args).contains('format') ||
          _scriptName(args).contains('fix') ||
          _scriptName(args).contains('generate') ||
          _scriptName(args).contains('codegen');
    }
    if (executable == 'make') {
      final target = args.firstOrNull ?? '';
      return const {'clean', 'format', 'generate', 'codegen'}.contains(target);
    }
    return false;
  }

  static bool _isDependencyCommand(String executable, List<String> args) {
    final first = args.firstOrNull ?? '';
    final second = args.length > 1 ? args[1] : '';
    if (const {'npm', 'pnpm', 'yarn', 'bun'}.contains(executable)) {
      return const {
        'install',
        'i',
        'add',
        'update',
        'upgrade',
        'remove',
        'uninstall',
        'dedupe',
      }.contains(first);
    }
    if (executable == 'pip' || executable == 'pip3') {
      return const {'install', 'uninstall'}.contains(first);
    }
    if (executable == 'python' || executable == 'python3') {
      return first == '-m' &&
          second == 'pip' &&
          args.length > 2 &&
          const {'install', 'uninstall'}.contains(args[2]);
    }
    if (executable == 'poetry') {
      return const {'add', 'install', 'remove', 'update'}.contains(first);
    }
    if (executable == 'composer') {
      return const {'require', 'install', 'update', 'remove'}.contains(first);
    }
    if (executable == 'bundle') return first == 'install';
    if (executable == 'gem') return first == 'install';
    if (executable == 'cargo') {
      return const {'add', 'remove', 'update', 'install'}.contains(first);
    }
    if (executable == 'go') {
      return const {'get', 'install'}.contains(first) ||
          (first == 'mod' && const {'tidy', 'download'}.contains(second));
    }
    if (executable == 'dart' || executable == 'flutter') {
      return first == 'pub' &&
          const {
            'get',
            'add',
            'remove',
            'upgrade',
            'downgrade',
          }.contains(second);
    }
    if (executable == 'dotnet') {
      return first == 'restore' ||
          (first == 'add' && second == 'package') ||
          (first == 'remove' && second == 'package');
    }
    return false;
  }

  static bool _isTestCommand(String executable, List<String> args) {
    final first = args.firstOrNull ?? '';
    final script = _scriptName(args);
    if (const {'npm', 'pnpm', 'yarn', 'bun'}.contains(executable)) {
      return first == 'test' ||
          script.contains('test') ||
          script.contains('lint') ||
          script.contains('check') ||
          script.contains('analyze');
    }
    if (const {
      'flutter',
      'dart',
      'cargo',
      'go',
      'dotnet',
    }.contains(executable)) {
      return const {'test', 'analyze', 'check', 'clippy'}.contains(first);
    }
    if (const {'pytest', 'phpunit', 'rspec'}.contains(executable)) return true;
    if (executable == 'python' || executable == 'python3') {
      return (first == '-m' &&
              args.length > 1 &&
              const {'pytest', 'unittest'}.contains(args[1])) ||
          args.contains('test');
    }
    if (const {'mvn', 'gradle', './gradlew'}.contains(executable)) {
      return args.contains('test') || args.contains('check');
    }
    if (executable == 'make') {
      return const {'test', 'check', 'lint'}.contains(first);
    }
    return false;
  }

  static bool _isBuildCommand(String executable, List<String> args) {
    final first = args.firstOrNull ?? '';
    final script = _scriptName(args);
    if (const {'npm', 'pnpm', 'yarn', 'bun'}.contains(executable)) {
      return first == 'build' || script.contains('build');
    }
    if (const {'flutter', 'cargo', 'go', 'dotnet'}.contains(executable)) {
      return first == 'build';
    }
    if (executable == 'dart') return first == 'compile';
    if (const {'mvn', 'gradle', './gradlew'}.contains(executable)) {
      return args.any(
        (arg) => const {'build', 'package', 'assemble'}.contains(arg),
      );
    }
    if (executable == 'make') return first == 'build';
    return false;
  }

  static List<String> _stripWrappers(List<String> tokens) {
    var current = tokens;
    while (current.isNotEmpty) {
      final first = current.first;
      if (first == 'env') {
        current = current.skip(1).where((token) => !_isEnvFlag(token)).toList();
        while (current.isNotEmpty && _isAssignment(current.first)) {
          current = current.skip(1).toList();
        }
        continue;
      }
      if (first == 'time' || first == 'command') {
        current = current.skip(1).toList();
        continue;
      }
      break;
    }
    return current;
  }

  static String _scriptName(List<String> args) {
    if (args.isEmpty) return '';
    final first = args.first;
    if (first == 'run' || first == 'run-script') {
      return args.length > 1 ? args[1].toLowerCase() : '';
    }
    return first.toLowerCase();
  }

  static bool _isEnvFlag(String token) {
    return token.startsWith('-') && token != '--';
  }

  static bool _isAssignment(String token) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(token);
  }

  static bool _hasWorkspaceWriteSyntax(String command) {
    return RegExp(r'(^|\s)(\d?>|>>)\s*(?!/dev/null\b)').hasMatch(command) ||
        RegExp(r'(^|\s)tee(\s|$)').hasMatch(command);
  }

  static List<String> _tokenize(String command) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var escaped = false;

    for (final codePoint in command.runes) {
      final char = String.fromCharCode(codePoint);
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}
