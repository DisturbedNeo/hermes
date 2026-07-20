import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The interaction state of a [ChatScrollController].
enum ChatScrollMode {
  /// Keep the latest chat content pinned to the bottom of the viewport.
  following,

  /// Leave the viewport entirely under user control.
  paused,

  /// A requested return to the latest content is in progress.
  returning,
}

/// Session-only state used to restore a chat tab's reading position.
class ChatScrollSnapshot {
  final double offset;
  final ChatScrollMode mode;
  final int historyRevision;

  const ChatScrollSnapshot({
    required this.offset,
    required this.mode,
    required this.historyRevision,
  });
}

/// Coordinates scrolling for a vertical, chronological chat list.
///
/// The controller deliberately supports one attached scroll position. While
/// [mode] is [ChatScrollMode.following], its custom position corrects to the
/// latest extent during layout. This keeps streaming content pinned without
/// timers or a sequence of animations. User input switches to
/// [ChatScrollMode.paused], where normal chronological list coordinates keep
/// older content stable as new content is appended below it.
class ChatScrollController extends ScrollController {
  final double bottomThreshold;
  final double longScrollViewportMultiplier;
  final Duration returnDuration;

  ChatScrollMode _mode = ChatScrollMode.following;
  bool _userScrollActive = false;
  bool _scrollBeganWhileFollowing = false;
  int _returnOperation = 0;
  double? _restoredOffset;
  VoidCallback? _scrollActivityListener;

  ChatScrollController({
    this.bottomThreshold = 50,
    this.longScrollViewportMultiplier = 3,
    this.returnDuration = const Duration(milliseconds: 200),
  }) : super(keepScrollOffset: false);

  ChatScrollMode get mode => _mode;

  bool get isAtLatest {
    final current = positions.firstOrNull;
    if (current == null || !current.hasContentDimensions) return true;
    return current.extentAfter <= bottomThreshold;
  }

  bool get needsReturnToLatest => hasClients && !isAtLatest;

  /// Restore state before the controller is attached to its list.
  void restoreSnapshot(ChatScrollSnapshot snapshot) {
    if (hasClients) {
      throw StateError(
        'A chat scroll snapshot must be restored before attach.',
      );
    }

    _restoredOffset = snapshot.offset;
    _mode = snapshot.mode == ChatScrollMode.returning
        ? ChatScrollMode.paused
        : snapshot.mode;
  }

  ChatScrollSnapshot snapshot({required int historyRevision}) {
    final current = positions.firstOrNull;
    final offset = current?.pixels ?? _restoredOffset ?? initialScrollOffset;
    final snapshotMode = switch (_mode) {
      ChatScrollMode.returning =>
        isAtLatest ? ChatScrollMode.following : ChatScrollMode.paused,
      final mode => mode,
    };

    return ChatScrollSnapshot(
      offset: offset,
      mode: snapshotMode,
      historyRevision: historyRevision,
    );
  }

  /// Update the state machine from notifications emitted by the chat list.
  void handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _beginUserScroll();
      return;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _beginUserScroll();
      return;
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _beginUserScroll();
      return;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        if (_userScrollActive) _finishUserScroll();
      } else {
        _beginUserScroll();
      }
      return;
    }

    if (notification is ScrollEndNotification && _userScrollActive) {
      _finishUserScroll();
    }
  }

  /// Return to the newest message and resume following.
  Future<void> returnToLatest({bool animate = true, Duration? duration}) async {
    final current = positions.firstOrNull;
    if (current == null || !current.hasContentDimensions) {
      _setMode(ChatScrollMode.following);
      return;
    }

    _userScrollActive = false;
    _scrollBeganWhileFollowing = false;
    final operation = ++_returnOperation;
    _setMode(ChatScrollMode.returning);

    final target = current.maxScrollExtent;
    final distance = (current.pixels - target).abs();
    final jumpThreshold =
        current.viewportDimension * longScrollViewportMultiplier;

    if (!animate || distance > jumpThreshold) {
      current.jumpTo(target);
    } else if (distance > precisionErrorTolerance) {
      await current.animateTo(
        target,
        duration: duration ?? returnDuration,
        curve: Curves.easeOutCubic,
      );
    }

    if (operation != _returnOperation || _mode != ChatScrollMode.returning) {
      return;
    }

    final latestPosition = positions.firstOrNull;
    if (latestPosition != null && latestPosition.hasContentDimensions) {
      final latestTarget = latestPosition.maxScrollExtent;
      if ((latestPosition.pixels - latestTarget).abs() >
          precisionErrorTolerance) {
        latestPosition.jumpTo(latestTarget);
      }
    }
    _setMode(ChatScrollMode.following);
  }

  /// Forget restored/user state and open the current history at its latest item.
  void resetToLatest() {
    _restoredOffset = null;
    _userScrollActive = false;
    _scrollBeganWhileFollowing = false;
    _returnOperation++;
    _setMode(ChatScrollMode.following, pinLatest: true);
  }

  @override
  void attach(ScrollPosition position) {
    if (hasClients) {
      throw FlutterError(
        'ChatScrollController supports exactly one attached ScrollPosition.',
      );
    }
    super.attach(position);
    void handleScrollActivity() {
      if (position.isScrollingNotifier.value) {
        if (_mode == ChatScrollMode.following) _beginUserScroll();
      } else if (_userScrollActive) {
        _finishUserScroll();
      }
    }

    _scrollActivityListener = handleScrollActivity;
    position.isScrollingNotifier.addListener(handleScrollActivity);
  }

  @override
  void detach(ScrollPosition position) {
    final listener = _scrollActivityListener;
    if (listener != null) {
      position.isScrollingNotifier.removeListener(listener);
      _scrollActivityListener = null;
    }
    _restoredOffset = position.pixels;
    super.detach(position);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ChatScrollPosition(
      owner: this,
      physics: physics,
      context: context,
      initialPixels: _restoredOffset ?? initialScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }

  bool get _pinsLatest => _mode == ChatScrollMode.following;

  void _beginUserScroll() {
    if (!_userScrollActive) {
      _userScrollActive = true;
      _scrollBeganWhileFollowing = _mode == ChatScrollMode.following;
      _returnOperation++;
    }
    _setMode(ChatScrollMode.paused);
  }

  void _finishUserScroll() {
    _userScrollActive = false;
    final beganWhileFollowing = _scrollBeganWhileFollowing;
    _scrollBeganWhileFollowing = false;
    final current = positions.firstOrNull;
    final exactlyAtLatest =
        current == null ||
        !current.hasContentDimensions ||
        current.extentAfter <= precisionErrorTolerance;
    if (isAtLatest && (!beganWhileFollowing || exactlyAtLatest)) {
      _setMode(ChatScrollMode.following, pinLatest: true);
    } else {
      _setMode(ChatScrollMode.paused);
    }
  }

  void _setMode(ChatScrollMode next, {bool pinLatest = false}) {
    final changed = _mode != next;
    _mode = next;

    if (pinLatest) {
      final current = positions.firstOrNull;
      if (current != null && current.hasContentDimensions) {
        final target = current.maxScrollExtent;
        if ((current.pixels - target).abs() > precisionErrorTolerance) {
          current.jumpTo(target);
        }
      }
    }

    if (changed) notifyListeners();
  }
}

class _ChatScrollPosition extends ScrollPositionWithSingleContext {
  final ChatScrollController owner;

  _ChatScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    required super.initialPixels,
    super.oldPosition,
    super.debugLabel,
  }) : super(keepScrollOffset: false);

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!hasContentDimensions &&
        owner._pinsLatest &&
        maxScrollExtent != pixels) {
      correctPixels(maxScrollExtent);
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    if (owner._pinsLatest) {
      final target = newPosition.maxScrollExtent;
      if (target != pixels) {
        correctPixels(target);
        return false;
      }
      return true;
    }
    return super.correctForNewDimensions(oldPosition, newPosition);
  }
}
