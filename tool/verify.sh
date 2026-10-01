#!/usr/bin/env bash
set -euo pipefail

dart run build_runner build
# dart_mappable emits one or more terminal blank lines; normalize only that
# generated whitespace so the final repository-wide diff check stays strict.
find lib -type f \( -name '*.mapper.dart' -o -name 'mappers.init.dart' \) \
  -exec perl -0pi -e 's/\n+\z/\n/' {} +
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test
git diff --check -- .
