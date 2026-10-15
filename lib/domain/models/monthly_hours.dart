import 'work_duration.dart';
import 'dart:math' as math;
import 'dashboard_models.dart';

class MonthlyHours {
  static const defaultGoals = [
    110,
    120,
    137,
    125,
    128,
    128,
    147,
    134,
    134,
    134,
    122,
    90
  ];
  final DateTime month;
  final double planned, goal, charged;
  const MonthlyHours(this.month, this.planned, this.goal, this.charged);
  double get remaining => math.max(0, goal - charged);
  double get remainingPercentage =>
      goal > 0 ? (remaining / goal * 100).clamp(0, 100) : 0;
  double get progress => goal > 0 ? (charged / goal).clamp(0, 1) : 0;
  static double parse(String value) {
    final parts = value.trim().split(':');
    if (parts.length == 2) {
      final hours = int.tryParse(parts[0]), minutes = int.tryParse(parts[1]);
      if (hours != null &&
          hours >= 0 &&
          minutes != null &&
          minutes >= 0 &&
          minutes < 60) return hours + minutes / 60;
      return 0;
    }
    final number = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return number.isFinite && number > 0 ? number : 0;
  }

  static double workedInMonth(DateTime month, Iterable<TimeLog> logs) => logs
      .where(
          (log) => log.date.year == month.year && log.date.month == month.month)
      .fold(0.0, (sum, log) => sum + WorkDuration.minutes(log) / 60);

  static MonthlyHours calculate(DateTime now, Iterable<TimeLog> logs,
      Map<String, dynamic> goals, Map<String, dynamic> preferences) {
    var weekdays = 0;
    for (var day = 1; day <= DateTime(now.year, now.month + 1, 0).day; day++) {
      if (DateTime(now.year, now.month, day).weekday <= 5) weekdays++;
    }
    final charged = logs
        .where((log) =>
            log.date.year == now.year &&
            log.date.month == now.month &&
            log.typeHs?.trim().toLowerCase() == 'hs cobradas')
        .fold(0.0, (sum, log) => sum + WorkDuration.minutes(log) / 60);
    return MonthlyHours(
        DateTime(now.year, now.month),
        weekdays * parse(preferences['horasDia']?.toString() ?? '08:20'),
        parse(goals['${now.month}']?.toString() ??
            '${now.year == 2026 ? defaultGoals[now.month - 1] : 0}:00'),
        charged);
  }
}
