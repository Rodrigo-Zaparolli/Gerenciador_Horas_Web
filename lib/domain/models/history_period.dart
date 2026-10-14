/// Inclusive calendar dates, with an exclusive next-day boundary for queries.
class HistoryPeriod {
  final DateTime start, endExclusive;
  HistoryPeriod(DateTime start, DateTime end)
      : start = DateTime(start.year, start.month, start.day),
        endExclusive = DateTime(end.year, end.month, end.day + 1);
  bool contains(DateTime date) =>
      !date.isBefore(start) && date.isBefore(endExclusive);
  String get signature =>
      '${start.toIso8601String()}/${endExclusive.toIso8601String()}';
}

class SubscriptionChanges {
  final Set<String> remove, add;
  SubscriptionChanges(Map<String, String> current, Map<String, String> desired)
      : remove =
            current.keys.where((key) => current[key] != desired[key]).toSet(),
        add = desired.keys.where((key) => current[key] != desired[key]).toSet();
}
