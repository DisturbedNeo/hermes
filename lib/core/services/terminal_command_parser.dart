/// Terminal command parsing, tokenization, and rule matching.
///
/// This library encapsulates all syntax-level logic for the terminal command
/// classifier: splitting raw shell strings into tokens, stripping wrapper
/// prefixes (env, time, bash -c, etc.), classifying commands into categories,
/// and evaluating safety-block rules against parsed command trees.
///
/// See [TerminalCommandClassifier] for the thin public-facing API that routes
/// parsed results to execution strategies.

library;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Blocked-command sets (policy definitions)
// ---------------------------------------------------------------------------

const Set<String> kFileDeletionCommands = {
  'rm',
  'rmdir',
  'unlink',
  'shred',
  'srm',
  'wipe',
  'del',
  'erase',
  'rd',
  'remove-item',
};

const Set<String> kDiskCommands = {
  'dd',
  'mkfs',
  'mke2fs',
  'fsck',
  'fdisk',
  'cfdisk',
  'sfdisk',
  'gdisk',
  'parted',
  'mount',
  'umount',
  'cryptsetup',
  'lvremove',
  'vgremove',
  'pvremove',
};

const Set<String> kPrivilegeEscalationCommands = {
  'sudo',
  'su',
  'doas',
  'pkexec',
};

const Set<String> kProcessControlCommands = {'kill', 'killall', 'pkill'};

const Set<String> kSystemControlCommands = {
  'shutdown',
  'reboot',
  'halt',
  'poweroff',
  'systemctl',
  'service',
  'launchctl',
};

const Set<String> kAccountManagementCommands = {
  'userdel',
  'usermod',
  'groupdel',
  'groupmod',
  'passwd',
};

const Set<String> kNetworkAdministrationCommands = {
  'iptables',
  'ip6tables',
  'nft',
  'ufw',
  'firewall-cmd',
};

// ---------------------------------------------------------------------------
// TerminalCommandParser — parsing, tokenization & rule matching
// ---------------------------------------------------------------------------

/// Encapsulates all command-syntax parsing, tokenization, and rule-matching
/// logic. The [TerminalCommandClassifier] delegates to this class so that it
/// retains a single responsibility: routing parsed commands to execution
/// strategies and formatting results.
class TerminalCommandParser {
  const TerminalCommandParser._();

  // ---- Tokenization -------------------------------------------------------

  /// Splits *command* into positional tokens, respecting quotes and escapes.
  static List<String> tokenize(String command) {
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
      if (char == r'\\') {
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

  /// Splits a compound shell command on `;`, `|`, and `&` separators,
  /// respecting quotes and escapes within each segment.
  static List<String> splitCommandSegments(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var escaped = false;

    void flush() {
      final segment = buffer.toString().trim();
      if (segment.isNotEmpty) segments.add(segment);
      buffer.clear();
    }

    for (final codePoint in command.runes) {
      final char = String.fromCharCode(codePoint);
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == r'\\') {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        }
        buffer.write(char);
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        buffer.write(char);
        continue;
      }
      if (char == ';' || char == '|' || char == '&') {
        flush();
        continue;
      }
      buffer.write(char);
    }
    flush();
    return segments;
  }

  // ---- Normalisation ------------------------------------------------------

  /// Extracts the basename of *executable* in lower case, stripping `.exe`.
  static String normaliseExecutable(String executable) {
    final parts = executable.toLowerCase().split(RegExp(r'[\\/]'));
    final basename = parts.isEmpty ? executable.toLowerCase() : parts.last;
    return basename.endsWith('.exe')
        ? basename.substring(0, basename.length - 4)
        : basename;
  }

  /// Strips known wrapper prefixes (`env …`, `time`, `command`) from *tokens*.
  static List<String> stripWrappers(List<String> tokens) {
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

  // ---- Shell-command extraction -------------------------------------------

  /// If *executable* is a shell interpreter, returns the inner command string
  /// from its `-c` / `/c` / `-command` argument. Returns `null` otherwise.
  static String? shellCommandArgument(String executable, List<String> args) {
    if (const {
      'sh',
      'bash',
      'zsh',
      'dash',
      'ksh',
      'fish',
    }.contains(executable)) {
      for (var i = 0; i < args.length; i++) {
        final arg = args[i];
        final isCommandFlag =
            arg == '-c' ||
            (arg.startsWith('-') &&
                !arg.startsWith('--') &&
                arg.substring(1).contains('c'));
        if (isCommandFlag && i + 1 < args.length) return args[i + 1];
      }
      return null;
    }

    if (executable == 'cmd') {
      for (var i = 0; i < args.length; i++) {
        final arg = args[i].toLowerCase();
        if ((arg == '/c' || arg == '/k') && i + 1 < args.length) {
          return args.skip(i + 1).join(' ');
        }
      }
      return null;
    }

    if (executable == 'powershell' || executable == 'pwsh') {
      for (var i = 0; i < args.length; i++) {
        final arg = args[i].toLowerCase();
        if ((arg == '-command' || arg == '-c') && i + 1 < args.length) {
          return args.skip(i + 1).join(' ');
        }
      }
    }
    return null;
  }

  // ---- Safety / blocking rules --------------------------------------------

  /// Returns a human-readable reason why the command is blocked, or `null`.
  static String? blockedReasonForTokens(List<String> rawTokens) {
    final tokens = stripWrappers(rawTokens);
    if (tokens.isEmpty) return null;

    final executable = normaliseExecutable(tokens.first);
    final args = tokens.skip(1).toList();

    final directReason = _blockedDirectInvocation(executable, args);
    if (directReason != null) return directReason;

    final shellCommand = shellCommandArgument(executable, args);
    if (shellCommand == null) return null;
    return blockedReasonForCommandLine(shellCommand);
  }

  /// Evaluates blocking rules against a single command string.
  static String? blockedReasonForCommandLine(String command) {
    for (final segment in splitCommandSegments(command)) {
      final reason = blockedReasonForTokens(tokenize(segment));
      if (reason != null) return reason;
    }
    return null;
  }

  static String? _blockedDirectInvocation(
    String executable,
    List<String> args,
  ) {
    if (kFileDeletionCommands.contains(executable)) {
      return 'File deletion commands are blocked by terminal policy. Use workspace delete tools for scoped file removal.';
    }
    if (kDiskCommands.contains(executable) || executable.startsWith('mkfs.')) {
      return 'Disk formatting, partitioning, and raw disk commands are blocked by terminal policy.';
    }
    if (kPrivilegeEscalationCommands.contains(executable)) {
      return 'Privilege escalation commands are blocked by terminal policy.';
    }
    if (kProcessControlCommands.contains(executable)) {
      return 'Process control commands are blocked by terminal policy.';
    }
    if (kSystemControlCommands.contains(executable)) {
      return 'System control commands are blocked by terminal policy.';
    }
    if (kAccountManagementCommands.contains(executable)) {
      return 'Account management commands are blocked by terminal policy.';
    }
    if (kNetworkAdministrationCommands.contains(executable)) {
      return 'Network administration commands are blocked by terminal policy.';
    }
    if (executable == 'git') {
      return _blockedGitReason(args);
    }
    if (executable == 'find' && args.contains('-delete')) {
      return 'find -delete is blocked by terminal policy because it can delete many files.';
    }
    return null;
  }

  static String? _blockedGitReason(List<String> args) {
    if (args.isEmpty) return null;
    final subcommand = args.first;
    if (subcommand == 'clean') {
      return 'git clean is blocked by terminal policy because it can delete untracked work.';
    }
    if (subcommand == 'reset' && args.contains('--hard')) {
      return 'git reset --hard is blocked by terminal policy because it can discard work.';
    }
    return null;
  }

  /// Returns `true` when *command* contains shell command substitution
  /// (`$(…)`, `` `…` ``, or process substitution `<(...)` / `>(...)`).
  static bool hasShellCommandSubstitution(String command) {
    String? quote;
    var escaped = false;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\\') {
        escaped = true;
        continue;
      }
      if (quote == "'") {
        if (char == "'") quote = null;
        continue;
      }
      if (char == '"') {
        quote = quote == '"' ? null : '"';
        continue;
      }
      if (char == "'") {
        quote = "'";
        continue;
      }
      if (char == '`') return true;
      if (i + 1 < command.length && char == r'$' && command[i + 1] == '(') {
        return true;
      }
      if ((char == '<' || char == '>') &&
          i + 1 < command.length &&
          command[i + 1] == '(') {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` when *command* contains workspace-write redirection
  /// (`> file`, `>> file`, or `tee`).
  static bool hasWorkspaceWriteSyntax(String command) {
    return RegExp(r'(^|\s)(\d?>|>>)\s*(?!/dev/null\b)').hasMatch(command) ||
        RegExp(r'(^|\s)tee(\s|$)').hasMatch(command);
  }

  // ---- Classification rules -----------------------------------------------

  /// Classifies a fully-tokenised command (post-wrapper-stripping) into a
  /// [TerminalCommandClass].
  static TerminalCommandClass classifyTokens(List<String> rawTokens) {
    final tokens = stripWrappers(rawTokens);
    if (tokens.isEmpty) return TerminalCommandClass.unknown;

    final executable = tokens.first;
    final args = tokens.skip(1).toList();

    // Recurse into shell wrappers.
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

  // ---- Internal helpers ---------------------------------------------------

  static bool _isEnvFlag(String token) =>
      token.startsWith('-') && token != '--';

  static bool _isAssignment(String token) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(token);

  static String _scriptName(List<String> args) {
    if (args.isEmpty) return '';
    final first = args.first;
    if (first == 'run' || first == 'run-script') {
      return args.length > 1 ? args[1].toLowerCase() : '';
    }
    return first.toLowerCase();
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
    if (const {'dart', 'flutter'}.contains(executable) &&
        args.length == 1 &&
        const {'--version', '-h', '--help'}.contains(args.first)) {
      return true;
    }
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

  // ---- Public classification entry point ----------------------------------

  /// Classifies *command* into a [TerminalCommandClass].
  static TerminalCommandClass classify(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return TerminalCommandClass.unknown;
    if (hasWorkspaceWriteSyntax(trimmed)) {
      return TerminalCommandClass.mutatingWorkspace;
    }
    if (hasShellCommandSubstitution(trimmed)) {
      return TerminalCommandClass.unknown;
    }
    final segments = splitCommandSegments(trimmed);
    if (segments.length != 1) return TerminalCommandClass.unknown;
    return classifyTokens(tokenize(segments.single));
  }

  /// Returns `true` for classes that unambiguously mutate the workspace.
  static bool isClearlyMutating(TerminalCommandClass commandClass) {
    return commandClass == TerminalCommandClass.mutatingWorkspace ||
        commandClass == TerminalCommandClass.dependencyInstall;
  }
}
