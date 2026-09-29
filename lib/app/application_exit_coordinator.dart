import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

/// Owns the platform exit handshake while the application performs its
/// asynchronous save and disposal work.
class ApplicationExitCoordinator extends WidgetsBindingObserver {
  ApplicationExitCoordinator({required this.onExitRequested});

  final Future<void> Function() onExitRequested;
  bool _cleanupStarted = false;
  bool _exitAllowed = false;

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (_exitAllowed) return AppExitResponse.exit;
    if (_cleanupStarted) return AppExitResponse.cancel;
    _cleanupStarted = true;
    Timer.run(() => unawaited(_runCleanup()));
    return AppExitResponse.cancel;
  }

  void reset() {
    _cleanupStarted = false;
  }

  void allowExit() {
    _exitAllowed = true;
  }

  Future<void> _runCleanup() async {
    try {
      await onExitRequested();
    } catch (_) {
      _cleanupStarted = false;
    }
  }
}
