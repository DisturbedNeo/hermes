import 'package:hermes/core/models/task.dart';

Map<String, dynamic> toolErrorPayload({
  required String code,
  required String message,
  required TaskToolErrorDisposition disposition,
  Map<String, dynamic> details = const {},
}) {
  return {
    'error': message,
    'error_code': code,
    'error_disposition': disposition.wire,
    ...details,
  };
}

TaskToolError? taskToolErrorFromResult(Map<String, dynamic> result) {
  final message = result['error']?.toString().trim();
  if (message == null || message.isEmpty) return null;
  final rawDisposition = result['error_disposition']
      ?.toString()
      .trim()
      .toLowerCase();
  final disposition = switch (rawDisposition) {
    'advisory' => TaskToolErrorDisposition.advisory,
    'retryable' => TaskToolErrorDisposition.retryable,
    _ => TaskToolErrorDisposition.fatal,
  };
  final code = result['error_code']?.toString().trim();
  return TaskToolError(
    code: code == null || code.isEmpty ? 'unknown_tool_error' : code,
    message: message,
    disposition: disposition,
  );
}
