/// Compatibility export for the persistence-owned task snapshot schema.
///
/// New persistence code should import the infrastructure DTO directly. This
/// path remains for existing application/domain callers during the migration.
library;

export '../../../persistence/infrastructure/dto/task_state_models.dart';
