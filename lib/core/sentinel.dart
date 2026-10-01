/// A sentinel value used in [copyWith] methods to distinguish between
/// "not provided" and "explicitly null".
///
/// When a parameter is omitted, it remains `null`. When explicitly set to
/// `null`, the caller passes `_sentinel` as an `Object?` typed argument.
const Object kSentinel = Object();

/// Returns `true` if [value] is the sentinel object.
bool isSentinel(Object? value) => identical(value, kSentinel);

/// Resolves a copyWith parameter to its intended value.
///
/// If [value] is the sentinel, returns [fallback]. Otherwise casts and
/// returns [value]. This eliminates repetitive `identical` checks in every
/// [copyWith] method.
///
/// Example:
/// ```dart
/// String? get name => resolve<String?>(nameParam, this.name);
/// DateTime? get createdAt => resolve<DateTime?>(createdAtParam, this.createdAt);
/// ```
T? resolve<T>(Object? value, T? fallback) =>
    identical(value, kSentinel) ? fallback : value as T?;
