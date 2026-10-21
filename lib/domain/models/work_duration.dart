import 'dashboard_models.dart';

/// Minutes are the common unit for displayed totals; explicit durations win.
class WorkDuration {
  static int? parse(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    if (text.contains(':')) {
      final parts = text.split(':');
      if (parts.length != 2) return null;
      final hours = int.tryParse(parts[0]), minutes = int.tryParse(parts[1]);
      if (hours == null ||
          hours < 0 ||
          minutes == null ||
          minutes < 0 ||
          minutes >= 60) {
        return null;
      }
      return hours * 60 + minutes;
    }
    final hours = double.tryParse(text.replaceAll(',', '.'));
    return hours != null && hours.isFinite && hours >= 0
        ? (hours * 60).round()
        : null;
  }

  static int minutes(TimeLog log) {
    if (log.durationMinutes > 0) return log.durationMinutes;
    final duration = parse(log.durationFormatted);
    if (duration != null) return duration;
    final hours = parse(log.hours);
    if (hours != null) return hours;
    final start = clock(log.startTime), end = clock(log.endTime);
    return start != null && end != null && end >= start ? end - start : 0;
  }

  static int? clock(String value) {
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value.trim())) return null;
    final minutes = parse(value);
    return minutes != null && minutes < 24 * 60 ? minutes : null;
  }

  static String format(int minutes) {
    final sign = minutes < 0 ? '-' : '';
    final value = minutes.abs();
    return '$sign${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  }
}
