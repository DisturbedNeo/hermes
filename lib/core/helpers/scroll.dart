import 'package:flutter/material.dart';

/// A [ScrollController] that supports smart auto-scroll behavior for chat-like
/// conversations.
///
/// Auto-scroll is enabled by default and will smoothly scroll to the bottom
/// when new content arrives. It automatically disables when the user scrolls
/// away from the bottom, and re-enables when they return to the bottom position.
class SmartScrollController extends ScrollController {
  bool _autoScrollEnabled = true;
  bool _userScrolledAway = false;
  final double bottomThreshold;

  SmartScrollController({this.bottomThreshold = 50});

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    position.isScrollingNotifier.addListener(_onScrollingChanged);
  }

  @override
  void detach(ScrollPosition position) {
    position.isScrollingNotifier.removeListener(_onScrollingChanged);
    super.detach(position);
  }

  void _onScrollingChanged() {
    final position = positions.firstOrNull;
    if (position == null) return;

    if (!position.isScrollingNotifier.value) {
      updateAutoScrollState();
    }
  }

  /// Enable auto-scrolling to the bottom.
  void enableAutoScroll() {
    _setAutoScrollState(enabled: true, userScrolledAway: false);
  }

  /// Update auto-scroll state from the current position.
  void updateAutoScrollState() {
    final nearBottom = isNearBottom;
    _setAutoScrollState(enabled: nearBottom, userScrolledAway: !nearBottom);
  }

  /// Whether automatic scrolling is currently enabled.
  bool get autoScrollEnabled => _autoScrollEnabled;

  /// Whether the scroll position is near the bottom of the list.
  bool get isNearBottom {
    final position = positions.firstOrNull;
    if (position == null) return true;
    final distanceFromBottom = (position.pixels - _bottomExtent(position))
        .abs();
    return distanceFromBottom <= bottomThreshold;
  }

  /// Whether the user has scrolled away from the bottom.
  bool get wasScrolledAway => _userScrolledAway;

  /// Smoothly animate to the bottom of the list.
  Future<void> scrollToBottom({Duration? duration}) async {
    final position = positions.firstOrNull;
    if (position == null) return;
    final dur = duration ?? const Duration(milliseconds: 200);
    await position.animateTo(
      _bottomExtent(position),
      duration: dur,
      curve: Curves.easeOutCubic,
    );
  }

  double _bottomExtent(ScrollPosition position) {
    return switch (position.axisDirection) {
      AxisDirection.down || AxisDirection.right => position.maxScrollExtent,
      AxisDirection.up || AxisDirection.left => position.minScrollExtent,
    };
  }

  void _setAutoScrollState({
    required bool enabled,
    required bool userScrolledAway,
  }) {
    if (_autoScrollEnabled == enabled &&
        _userScrolledAway == userScrolledAway) {
      return;
    }

    _autoScrollEnabled = enabled;
    _userScrolledAway = userScrolledAway;
    notifyListeners();
  }
}
