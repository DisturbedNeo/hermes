/// Application-facing model runtime boundary.
///
/// Concrete HTTP clients and process managers implement this contract in the
/// composition root. Feature application code never names those adapters.
abstract interface class ModelRuntimePort {
  Future<String> complete({required String prompt, String? diagnosticsLabel});
}
