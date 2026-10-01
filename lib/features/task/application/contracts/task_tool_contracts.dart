import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'task_tool_contracts.mapper.dart';

@MappableEnum(defaultValue: TaskToolErrorDisposition.fatal)
enum TaskToolErrorDisposition { advisory, retryable, fatal }

extension TaskToolErrorDispositionWire on TaskToolErrorDisposition {
  String get wire => name;
}

@MappableClass(ignoreNull: true)
class TaskToolError with TaskToolErrorMappable {
  @MappableField(hook: JsonStringHook(fallback: 'unknown_tool_error'))
  final String code;
  @MappableField(hook: JsonStringHook())
  final String message;
  final TaskToolErrorDisposition disposition;

  const TaskToolError({
    required this.code,
    required this.message,
    required this.disposition,
  });
}
