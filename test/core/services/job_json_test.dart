import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/job_system/job_json.dart';

void main() {
  group('JobJson', () {
    test('parses direct and fenced JSON objects', () {
      expect(JobJson.tryParseObject('{"a":1}'), {'a': 1});
      expect(JobJson.tryParseObject('```json\n{"a":1}\n```'), {'a': 1});
    });

    test('extracts the first complete JSON object from prose', () {
      final parsed = JobJson.tryParseObject(
        'prefix {"message":"brace } in string","nested":{"ok":true}} suffix',
      );

      expect(parsed, {
        'message': 'brace } in string',
        'nested': {'ok': true},
      });
    });

    test('returns null or throws for non-object JSON', () {
      expect(JobJson.tryParseObject('[1,2,3]'), isNull);
      expect(
        () => JobJson.parseObject('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodes tool arguments when possible and keeps plain strings', () {
      expect(JobJson.decodeJsonOrString('{"path":"output.md"}'), {
        'path': 'output.md',
      });
      expect(JobJson.decodeJsonOrString('plain text'), 'plain text');
    });
  });
}
