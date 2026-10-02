/// Compatibility export for the persistence-owned project snapshot schema.
///
/// New persistence code should import the infrastructure DTO directly. This
/// path remains for existing application/domain callers during the migration.
library;

export '../../../persistence/infrastructure/dto/project_state_models.dart';
