import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/task_system/task_json.dart';

void main() {
  group('TaskJson', () {
    test('parses direct and fenced JSON objects', () {
      expect(TaskJson.tryParseObject('{"a":1}'), {'a': 1});
      expect(TaskJson.tryParseObject('```json\n{"a":1}\n```'), {'a': 1});
    });

    test('extracts the first complete JSON object from prose', () {
      final parsed = TaskJson.tryParseObject(
        'prefix {"message":"brace } in string","nested":{"ok":true}} suffix',
      );

      expect(parsed, {
        'message': 'brace } in string',
        'nested': {'ok': true},
      });
    });

    test('returns null or throws for non-object JSON', () {
      expect(TaskJson.tryParseObject('[1,2,3]'), isNull);
      expect(
        () => TaskJson.parseObject('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodes tool arguments when possible and keeps plain strings', () {
      expect(TaskJson.decodeJsonOrString('{"path":"output.md"}'), {
        'path': 'output.md',
      });
      expect(TaskJson.decodeJsonOrString('plain text'), 'plain text');
    });
  });
}
