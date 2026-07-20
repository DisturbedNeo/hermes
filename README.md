# hermes

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Generated serialization

Typed JSON mapping is generated with `dart_mappable`. After changing an
annotated DTO, regenerate and commit the mapper outputs:

```sh
dart run build_runner build
```

Application code should use `ModelJson` rather than calling generated mapper
classes or per-model JSON methods directly.
