import 'package:hermes/core/tools/json_tool.dart';

class CalculatorOperation {
  final num paramA;
  final num paramB;
  final String operator;

  const CalculatorOperation({
    required this.paramA,
    required this.paramB,
    required this.operator,
  });
}

class CalculatorTool extends JsonTool<CalculatorOperation> {
  @override
  final String id = 'calculator';

  @override
  final String name = 'Calculator';

  @override
  final String description = 'Performs arithmetic operations';

  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'paramA': {
        'type': 'number',
        'description': 'The first number in the operation.',
      },
      'paramB': {
        'type': 'number',
        'description': 'The second number in the operation.',
      },
      'operator': {
        'type': 'string',
        'enum': ['+', '-', '*', '/', 'add', 'subtract', 'multiply', 'divide'],
        'description': 'The operation to perform.',
      },
    },
    'required': ['paramA', 'paramB', 'operator'],
  };

  @override
  CalculatorOperation fromJson(Map<String, dynamic> json) {
    final paramA = json['paramA'];
    final paramB = json['paramB'];
    final operator = json['operator'];

    if (paramA is! num || paramB is! num || operator is! String) {
      throw const FormatException('Invalid calculator input');
    }

    return CalculatorOperation(
      paramA: paramA,
      paramB: paramB,
      operator: operator,
    );
  }

  @override
  Future<Map<String, dynamic>> run(CalculatorOperation input) {
    final op = input.operator.trim().toLowerCase();

    num result;
    switch (op) {
      case '+':
      case 'add':
        result = input.paramA + input.paramB;
        break;
      case '-':
      case 'subtract':
        result = input.paramA - input.paramB;
        break;
      case '*':
      case 'x':
      case 'multiply':
        result = input.paramA * input.paramB;
        break;
      case '/':
      case 'divide':
        if (input.paramB == 0) {
          throw ArgumentError('Division by zero');
        }
        result = input.paramA / input.paramB;
        break;
      default:
        throw ArgumentError('Unsupported operator: ${input.operator}');
    }

    return Future.value({'result': result});
  }
}
