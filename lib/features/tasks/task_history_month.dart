import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';

const taskHistoryMonths = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio',
  'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

DateTime historyWeekStart(DateTime day) => DateTime(day.year, day.month,
    day.day - day.weekday + DateTime.monday);

class TaskHistoryWeek {
  final DateTime start, end;
  final List<TimeLog> logs;
  TaskHistoryWeek(this.start, this.end, this.logs);
  DateTime get monday => historyWeekStart(start);
  String get label => '${start.day.toString().padLeft(2, '0')} a '
      '${end.day.toString().padLeft(2, '0')} de ${taskHistoryMonths[start.month - 1].toLowerCase()}';
  List<DateTime> get days => [for (var day = start.day; day <= end.day; day++)
    DateTime(start.year, start.month, day)];
  int get minutes => logs.fold(0, (sum, log) => sum + WorkDuration.minutes(log));
}

class TaskHistoryMonth {
  final int year, month;
  final List<TimeLog> logs;
  TaskHistoryMonth(this.year, this.month, Iterable<TimeLog> source)
      : logs = source.where((log) => log.date.year == year && log.date.month == month).toList();
  int get dayCount => DateTime(year, month + 1, 0).day;
  int get minutes => logs.fold(0, (sum, log) => sum + WorkDuration.minutes(log));
  int get chargedMinutes => logs.where((log) {
    final kind = (log.typeHs ?? '').toLowerCase().replaceAll('ã', 'a');
    return kind.contains('cobrada') && !kind.contains('nao');
  }).fold(0, (sum, log) => sum + WorkDuration.minutes(log));
  List<TaskHistoryWeek> get weeks {
    final result = <TaskHistoryWeek>[];
    var start = DateTime(year, month, 1);
    while (start.month == month && start.year == year) {
      final last = start.day + DateTime.sunday - start.weekday;
      final end = DateTime(year, month, last > dayCount ? dayCount : last);
      result.add(TaskHistoryWeek(start, end, logs.where((log) =>
          log.date.day >= start.day && log.date.day <= end.day).toList()));
      start = DateTime(year, month, end.day + 1);
    }
    return result;
  }
}

Map<int, Map<int, Map<DateTime, List<TimeLog>>>> taskHistoryTree(Iterable<TimeLog> logs) {
  final result = <int, Map<int, Map<DateTime, List<TimeLog>>>>{};
  for (final log in logs) {
    result.putIfAbsent(log.date.year, () => {})
        .putIfAbsent(log.date.month, () => {})
        .putIfAbsent(historyWeekStart(log.date), () => []).add(log);
  }
  return result;
}
