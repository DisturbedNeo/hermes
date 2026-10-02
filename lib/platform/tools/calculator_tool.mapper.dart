// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'calculator_tool.dart';

/// @nodoc
class CalculatorOperationMapper extends ClassMapperBase<CalculatorOperation> {
  CalculatorOperationMapper._();

  static CalculatorOperationMapper? _instance;
  static CalculatorOperationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CalculatorOperationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'CalculatorOperation';

  static num _$paramA(CalculatorOperation v) => v.paramA;
  static const Field<CalculatorOperation, num> _f$paramA = Field(
    'paramA',
    _$paramA,
  );
  static num _$paramB(CalculatorOperation v) => v.paramB;
  static const Field<CalculatorOperation, num> _f$paramB = Field(
    'paramB',
    _$paramB,
  );
  static String _$operator(CalculatorOperation v) => v.operator;
  static const Field<CalculatorOperation, String> _f$operator = Field(
    'operator',
    _$operator,
  );

  @override
  final MappableFields<CalculatorOperation> fields = const {
    #paramA: _f$paramA,
    #paramB: _f$paramB,
    #operator: _f$operator,
  };

  @override
  final MappingHook hook = const CalculatorOperationJsonHook();
  static CalculatorOperation _instantiate(DecodingData data) {
    return CalculatorOperation(
      paramA: data.dec(_f$paramA),
      paramB: data.dec(_f$paramB),
      operator: data.dec(_f$operator),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static CalculatorOperation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<CalculatorOperation>(map);
  }

  static CalculatorOperation fromJson(String json) {
    return ensureInitialized().decodeJson<CalculatorOperation>(json);
  }
}

/// @nodoc
mixin CalculatorOperationMappable {}

