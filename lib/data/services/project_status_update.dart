import '../../domain/models/project_model.dart';

/// Persist once; offer the physical folder move only after finalization succeeds.
Future<bool> updateProjectStatus({
  required ProjectModel project,
  required String status,
  required Future<void> Function() persist,
  required Future<void> Function() registerLogs,
  required Future<bool> Function() offerArchive,
}) async {
  final previous = project.status;
  var saved = false;
  project.status = status;
  try {
    if (status == 'TRAB_FIM') await registerLogs();
    await persist();
    saved = true;
    return status == 'TRAB_FIM' ? await offerArchive() : false;
  } catch (_) {
    if (!saved) project.status = previous;
    rethrow;
  }
}
