// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'task_tool_contracts.dart';

/// @nodoc

class TaskToolErrorDispositionMapper
    extends EnumMapper<TaskToolErrorDisposition> {
  TaskToolErrorDispositionMapper._();

  static TaskToolErrorDispositionMapper? _instance;
  static TaskToolErrorDispositionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = TaskToolErrorDispositionMapper._(),
      );
    }
    return _instance!;
  }

  static TaskToolErrorDisposition fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TaskToolErrorDisposition decode(dynamic value) {
    switch (value) {
      case r'advisory':
        return TaskToolErrorDisposition.advisory;
      case r'retryable':
        return TaskToolErrorDisposition.retryable;
      case r'fatal':
        return TaskToolErrorDisposition.fatal;
      default:
        return TaskToolErrorDisposition.values[2];
    }
  }

  @override
  dynamic encode(TaskToolErrorDisposition self) {
    switch (self) {
      case TaskToolErrorDisposition.advisory:
        return r'advisory';
      case TaskToolErrorDisposition.retryable:
        return r'retryable';
      case TaskToolErrorDisposition.fatal:
        return r'fatal';
    }
  }
}

/// @nodoc

extension TaskToolErrorDispositionMapperExtension on TaskToolErrorDisposition {
  String toValue() {
    TaskToolErrorDispositionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TaskToolErrorDisposition>(this)
        as String;
  }
}

/// @nodoc
class TaskToolErrorMapper extends ClassMapperBase<TaskToolError> {
  TaskToolErrorMapper._();

  static TaskToolErrorMapper? _instance;
  static TaskToolErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskToolErrorMapper._());
      TaskToolErrorDispositionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskToolError';

  static String _$code(TaskToolError v) => v.code;
  static const Field<TaskToolError, String> _f$code = Field(
    'code',
    _$code,
    hook: JsonStringHook(fallback: 'unknown_tool_error'),
  );
  static String _$message(TaskToolError v) => v.message;
  static const Field<TaskToolError, String> _f$message = Field(
    'message',
    _$message,
    hook: JsonStringHook(),
  );
  static TaskToolErrorDisposition _$disposition(TaskToolError v) =>
      v.disposition;
  static const Field<TaskToolError, TaskToolErrorDisposition> _f$disposition =
      Field('disposition', _$disposition);

  @override
  final MappableFields<TaskToolError> fields = const {
    #code: _f$code,
    #message: _f$message,
    #disposition: _f$disposition,
  };
  @override
  final bool ignoreNull = true;

  static TaskToolError _instantiate(DecodingData data) {
    return TaskToolError(
      code: data.dec(_f$code),
      message: data.dec(_f$message),
      disposition: data.dec(_f$disposition),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskToolError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskToolError>(map);
  }

  static TaskToolError fromJson(String json) {
    return ensureInitialized().decodeJson<TaskToolError>(json);
  }
}

/// @nodoc
mixin TaskToolErrorMappable {
  String toJson() {
    return TaskToolErrorMapper.ensureInitialized().encodeJson<TaskToolError>(
      this as TaskToolError,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskToolErrorMapper.ensureInitialized().encodeMap<TaskToolError>(
      this as TaskToolError,
    );
  }
}
