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
  double? _lastMinScrollExtent;
  double? _lastMaxScrollExtent;
  AxisDirection? _lastAxisDirection;
  final double bottomThreshold;
  final double longScrollViewportMultiplier;

  SmartScrollController({
    this.bottomThreshold = 50,
    this.longScrollViewportMultiplier = 3,
  });

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

  /// Preserve the visible viewport when content grows below it.
  ///
  /// Reversed chat lists place the newest content at the visual bottom. When
  /// that newest bubble grows while the user is reading older content, the
  /// scroll extent increases and the current content would otherwise drift.
  /// This keeps the same content anchored unless the view is near the bottom.
  void updateContentMetrics() {
    final position = positions.firstOrNull;
    if (position == null || !position.hasContentDimensions) return;

    final previousMin = _lastMinScrollExtent;
    final previousMax = _lastMaxScrollExtent;
    final previousAxisDirection = _lastAxisDirection;
    final currentMin = position.minScrollExtent;
    final currentMax = position.maxScrollExtent;
    final currentAxisDirection = position.axisDirection;

    _lastMinScrollExtent = currentMin;
    _lastMaxScrollExtent = currentMax;
    _lastAxisDirection = currentAxisDirection;

    if (previousMin == null ||
        previousMax == null ||
        previousAxisDirection == null ||
        previousAxisDirection != currentAxisDirection ||
        isNearBottom) {
      return;
    }

    final delta = switch (currentAxisDirection) {
      AxisDirection.up || AxisDirection.left => currentMax - previousMax,
      AxisDirection.down || AxisDirection.right => currentMin - previousMin,
    };

    if (delta.abs() < 0.5) return;

    final target = (position.pixels + delta)
        .clamp(currentMin, currentMax)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;

    position.jumpTo(target);
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
    final target = _bottomExtent(position);
    final distance = (position.pixels - target).abs();
    final longScrollThreshold =
        position.viewportDimension * longScrollViewportMultiplier;

    if (distance > longScrollThreshold) {
      position.jumpTo(target);
      return;
    }

    final dur = duration ?? const Duration(milliseconds: 200);
    await position.animateTo(target, duration: dur, curve: Curves.easeOutCubic);
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
