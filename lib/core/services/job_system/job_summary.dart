import 'package:hermes/core/models/job.dart';

class JobSummary {
  final String id;
  final String title;
  final String? chatSessionId;
  final JobStatus status;
  final DateTime updatedAt;
  final String? currentPhaseId;

  const JobSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.currentPhaseId,
    this.chatSessionId,
  });
}
