/// Bounded retry policy for model requests that fail before output begins.
class ChatRetryPolicy {
  const ChatRetryPolicy({this.maxAttempts = 4});

  final int maxAttempts;

  bool shouldRetry(int attempt) => attempt < maxAttempts;

  Duration delayForAttempt(int attempt) =>
      Duration(milliseconds: 100 * (1 << (attempt - 1)));
}
