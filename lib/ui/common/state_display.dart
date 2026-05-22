import 'package:flutter/material.dart';

/// Represents the possible display states for a content panel or list.
enum DisplayState { loading, empty, error, content }

/// A unified widget for displaying consistent loading, empty, error, and content states.
///
/// Use this widget to replace scattered `CircularProgressIndicator`, empty text,
/// and error messages across the app with a consistent visual language.
///
/// Example:
/// ```dart
/// StateDisplay(
///   state: _loading ? DisplayState.loading : (_error != null ? DisplayState.error : DisplayState.content),
///   content: _buildContent(),
///   errorMessage: 'Failed to load data',
///   emptyMessage: 'Nothing here yet',
///   emptyHint: 'Try creating something new',
///   onRetry: _error != null ? () => _reload() : null,
/// )
/// ```
class StateDisplay extends StatelessWidget {
  final DisplayState state;
  final Widget? content;
  final String? errorMessage;
  final String? emptyMessage;
  final String? emptyHint;
  final VoidCallback? onRetry;
  final IconData? icon;

  const StateDisplay({
    super.key,
    required this.state,
    this.content,
    this.errorMessage,
    this.emptyMessage,
    this.emptyHint,
    this.onRetry,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case DisplayState.loading:
        return const Center(child: CircularProgressIndicator());
      case DisplayState.empty:
        return _EmptyState(
          message: emptyMessage ?? 'Nothing here yet',
          hint: emptyHint,
          icon: icon ?? Icons.info_outline,
        );
      case DisplayState.error:
        return _ErrorState(
          message: errorMessage ?? 'Something went wrong',
          onRetry: onRetry,
        );
      case DisplayState.content:
        return content ?? const SizedBox.shrink();
    }
  }
}

/// Displays a centered empty state with an icon and optional hint text.
class _EmptyState extends StatelessWidget {
  final String message;
  final String? hint;
  final IconData icon;

  const _EmptyState({
    required this.message,
    this.hint,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StateContentLayout(
      builder: (context, compact) {
        final iconSize = compact ? 32.0 : 48.0;
        final spacing = compact ? 8.0 : 16.0;
        final hintSpacing = compact ? 4.0 : 8.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            SizedBox(height: spacing),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
            ),
            if (hint != null) ...[
              SizedBox(height: hintSpacing),
              Text(
                hint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                textAlign: TextAlign.center,
                maxLines: compact ? 2 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Displays a centered error state with an optional retry button.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _StateContentLayout(
      builder: (context, compact) {
        final iconSize = compact ? 32.0 : 48.0;
        final spacing = compact ? 8.0 : 16.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: iconSize,
              color: theme.colorScheme.error,
            ),
            SizedBox(height: spacing),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
            ),
            if (onRetry != null) ...[
              SizedBox(height: spacing),
              compact
                  ? IconButton.filled(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Retry',
                      onPressed: onRetry,
                    )
                  : FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      onPressed: onRetry,
                    ),
            ],
          ],
        );
      },
    );
  }
}

class _StateContentLayout extends StatelessWidget {
  final Widget Function(BuildContext context, bool compact) builder;

  const _StateContentLayout({required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            (constraints.hasBoundedHeight && constraints.maxHeight < 160) ||
            (constraints.hasBoundedWidth && constraints.maxWidth < 220);
        final padding = compact ? 12.0 : 24.0;
        final content = Padding(
          padding: EdgeInsets.all(padding),
          child: builder(context, compact),
        );

        if (!constraints.hasBoundedHeight) {
          return Center(child: content);
        }

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

/// A skeleton loading widget for content placeholders.
///
/// Shows animated placeholder rectangles that mimic the structure of the
/// actual content being loaded. More performant and user-friendly than a
/// spinner because it conveys content layout.
class SkeletonLoader extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const SkeletonLoader({super.key, this.itemCount = 5, this.itemHeight = 48});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          height: itemHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
