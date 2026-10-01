#!/usr/bin/env bash
set -euo pipefail

test -f docs/architecture.md || {
  echo "Missing docs/architecture.md; restore the tracked architecture guide before verifying." >&2
  exit 1
}

dart run build_runner build
# dart_mappable emits one or more terminal blank lines; normalize only that
# generated whitespace so the final repository-wide diff check stays strict.
find lib -type f \( -name '*.mapper.dart' -o -name 'mappers.init.dart' \) \
  -exec perl -0pi -e 's/\n+\z/\n/' {} +
git diff --exit-code -- '*.mapper.dart' 'lib/app/mappers.init.dart'
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test test/architecture/architecture_test.dart
flutter test
git diff --check -- .
