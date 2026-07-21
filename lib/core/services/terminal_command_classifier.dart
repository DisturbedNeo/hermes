/// Terminal command classification — public-facing API.
///
/// This file provides the single-responsibility entry point for routing parsed
/// commands to execution strategies and formatting results. All parsing,
/// tokenization, and rule-matching logic lives in [terminal_command_parser.dart].

library;

export 'terminal_command_parser.dart'
    show TerminalCommandClass, TerminalCommandClassWire;

import 'package:hermes/core/services/terminal_command_parser.dart';

/// Thin public API that delegates to [TerminalCommandParser].
///
/// The parser handles syntax-level logic (tokenization, rule matching); this
/// class exists solely as the stable boundary for consumers.
class TerminalCommandClassifier {
  const TerminalCommandClassifier._();

  /// Returns a human-readable reason why *executable* with *arguments* is
  /// blocked by terminal policy, or `null` if the command is allowed.
  static String? blockedReason({
    required String executable,
    required List<String> arguments,
  }) {
    return TerminalCommandParser.blockedReasonForTokens(
      [executable, ...arguments],
    );
  }

  /// Returns a reason why *command* is blocked (checks for shell substitution
  /// and delegates to the parser).
  static String? blockedReasonForCommand(String command) {
    if (TerminalCommandParser.hasShellCommandSubstitution(command)) {
      return 'Shell command substitution is blocked by terminal policy because it can hide nested commands.';
    }
    return TerminalCommandParser.blockedReasonForCommandLine(command);
  }

  /// Classifies *command* into a [TerminalCommandClass].
  static TerminalCommandClass classify(String command) {
    return TerminalCommandParser.classify(command);
  }

  /// Returns `true` for classes that unambiguously mutate the workspace.
  static bool isClearlyMutating(TerminalCommandClass commandClass) {
    return TerminalCommandParser.isClearlyMutating(commandClass);
  }
}
