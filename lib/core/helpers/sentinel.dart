/// A sentinel value used in [copyWith] methods to distinguish between
/// "not provided" and "explicitly null".
///
/// When a parameter is omitted, it remains `null`. When explicitly set to
/// `null`, the caller passes `_sentinel` as an `Object?` typed argument.
const Object kSentinel = Object();

/// Returns `true` if [value] is the sentinel object.
bool isSentinel(Object? value) => identical(value, kSentinel);
