/// Wire-level generation options owned by the model boundary.
///
/// The alias keeps transport-shaped values out of application port
/// declarations; only the HTTP adapter is responsible for serialising them.
typedef ModelRequestOptions = Map<String, dynamic>;
