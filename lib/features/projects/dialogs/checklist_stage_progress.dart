/// Uses Excel coefficients only when they reproduce its confirmed stage total.
/// No equal-weight average or inferred duration replaces the workbook formula.
double? immediateStageProgress(String stage, List<Map<String, dynamic>> tasks,
    Map<String, double> values, Map<String, dynamic>? preview) {
  final rows = (preview?['rows'] as List? ?? [])
      .whereType<Map>()
      .where((row) =>
          row['label']?.toString().trim().toLowerCase() ==
          stage.trim().toLowerCase())
      .toList();
  final progress = preview?['taskProgress'];
  if (tasks.isEmpty || rows.length != 1 || progress is! Map) return null;
  final confirmed = rows.single['percentage'];
  if (confirmed is! num || !confirmed.isFinite) return null;
  double weightSum = 0, before = 0, after = 0;
  for (final task in tasks) {
    final key = "${task['sheet']}!${task['cell']}";
    final item = progress[key];
    if (item is! Map) return null;
    final weight = item['weight'],
        original = item['value'],
        current = values[key];
    if (weight is! num ||
        original is! num ||
        current == null ||
        !weight.isFinite ||
        !original.isFinite ||
        !current.isFinite ||
        weight < 0 ||
        weight > 1 ||
        original < 0 ||
        original > 1 ||
        current < 0 ||
        current > 1) {
      return null;
    }
    weightSum += weight;
    before += weight * original;
    after += weight * current;
  }
  if ((weightSum - 1).abs() > 0.000001 ||
      (before - confirmed).abs() > 0.000001) {
    return null;
  }
  return after.clamp(0, 1);
}

/// Whole-block progress includes collapsed and filtered children. Excel weights
/// apply within the block when available; weightless blocks use a simple mean.
/// This display never changes the stage's authoritative Excel calculation.
double checklistBlockProgress(List<Map<String, dynamic>> tasks,
    Map<String, double> values, Map<String, dynamic>? preview) {
  if (tasks.isEmpty) return 0;
  final progress = preview?['taskProgress'];
  double sum = 0, weighted = 0, weights = 0;
  var completeWeights = progress is Map;
  for (final task in tasks) {
    final key = "${task['sheet']}!${task['cell']}";
    final value = values[key] ?? 0;
    sum += value;
    final item = progress is Map ? progress[key] : null;
    final weight = item is Map ? item['weight'] : null;
    if (weight is num && weight.isFinite && weight >= 0 && weight <= 1) {
      weighted += weight * value;
      weights += weight;
    } else {
      completeWeights = false;
    }
  }
  return (completeWeights && weights > 0
          ? weighted / weights
          : sum / tasks.length)
      .clamp(0, 1);
}
