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
  final Duration scrollBackThresholdMs;

  SmartScrollController({this.scrollBackThresholdMs = const Duration(milliseconds: 50)});

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (position is ScrollActivity) return;
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

    // When scrolling stops, check if user is near the bottom
    if (!position.isScrollingNotifier.value && _autoScrollEnabled) {
      final atBottom = position.pixels >= position.maxScrollExtent - scrollBackThresholdMs.inMilliseconds.toDouble();
      if (atBottom) {
        _userScrolledAway = false;
      } else {
        _userScrolledAway = true;
        _autoScrollEnabled = false;
      }
    }
  }

  /// Enable auto-scrolling to the bottom.
  void enableAutoScroll() {
    _autoScrollEnabled = true;
    _userScrolledAway = false;
  }

  /// Whether the scroll position is near the bottom of the list.
  bool get isNearBottom {
    final position = positions.firstOrNull;
    if (position == null) return true;
    return position.pixels >= position.maxScrollExtent - scrollBackThresholdMs.inMilliseconds.toDouble();
  }

  /// Whether the user has scrolled away from the bottom.
  bool get wasScrolledAway => _userScrolledAway;

  /// Smoothly animate to the bottom of the list.
  Future<void> scrollToBottom({Duration? duration}) async {
    final position = positions.firstOrNull;
    if (position == null) return;
    final dur = duration ?? const Duration(milliseconds: 200);
    await position.animateTo(
      position.maxScrollExtent,
      duration: dur,
      curve: Curves.easeOutCubic,
    );
  }
}
