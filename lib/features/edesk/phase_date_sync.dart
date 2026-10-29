import '../../domain/models/project_model.dart';
import 'work_audit.dart';

DateTime? parsePhaseDate(String value) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value.trim());
  if (match == null) return null;
  final day = int.parse(match[1]!),
      month = int.parse(match[2]!),
      year = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

void validatePhaseDates(DateTime start, DateTime end) {
  if (DateTime(end.year, end.month, end.day)
      .isBefore(DateTime(start.year, start.month, start.day))) {
    throw const FormatException(
        'O fim deve ser igual ou posterior ao in\u00edcio.');
  }
}

/// Only date fields of an exact, unique work may change. Preserve all other data.
List<Map<String, dynamic>> phaseDatePatch(List<dynamic> rawTasks,
    {required String request,
    required String work,
    required String phase,
    required String expectedStart,
    required String expectedEnd,
    required DateTime start,
    required DateTime end}) {
  validatePhaseDates(start, end);
  final tasks =
      rawTasks.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  final matches = tasks.where((t) {
    final task = TaskModel.fromJson(t);
    return task.edeskWorkNumber == work &&
        (task.edeskSolicitacao?.trim().isNotEmpty == true
                ? task.edeskSolicitacao!.trim()
                : request) ==
            request;
  }).toList();
  if (matches.length != 1) {
    throw StateError(
        'Trabalho ausente ou repetido. Confira o cadastro novamente.');
  }
  final target = matches.single;
  final task = TaskModel.fromJson(target);
  if (task.stage != phase ||
      auditDate(task.planStart) != expectedStart ||
      auditDate(task.planEnd) != expectedEnd) {
    throw StateError('O cadastro mudou. Refaca a conferencia antes de salvar.');
  }
  target['planStart'] = start.toIso8601String();
  target['planEnd'] = end.toIso8601String();
  return tasks;
}
