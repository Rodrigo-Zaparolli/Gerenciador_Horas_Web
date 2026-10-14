class TimerSession {
  final String targetId;
  final DateTime startedAt;
  final DateTime? segmentStartedAt;
  final int accumulatedSeconds;

  const TimerSession({
    required this.targetId,
    required this.startedAt,
    required this.segmentStartedAt,
    required this.accumulatedSeconds,
  });

  bool get running => segmentStartedAt != null;

  int elapsedSeconds(DateTime now) {
    final segment = segmentStartedAt;
    final elapsed = segment == null ? 0 : now.difference(segment).inSeconds;
    return accumulatedSeconds + (elapsed < 0 ? 0 : elapsed);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'targetId': targetId,
        'startedAt': startedAt.toIso8601String(),
        'segmentStartedAt': segmentStartedAt?.toIso8601String(),
        'accumulatedSeconds': accumulatedSeconds,
      };

  static TimerSession? fromJson(Map<String, dynamic>? data) {
    if (data == null || data['version'] != 1) return null;
    final target = data['targetId'];
    final started = data['startedAt'];
    final segment = data['segmentStartedAt'];
    final accumulated = data['accumulatedSeconds'];
    if (target is! String ||
        target.isEmpty ||
        started is! String ||
        (segment != null && segment is! String) ||
        accumulated is! int ||
        accumulated < 0) {
      return null;
    }
    final start = DateTime.tryParse(started);
    final segmentStart = segment is String ? DateTime.tryParse(segment) : null;
    if (start == null ||
        (segment != null && segmentStart == null) ||
        (segmentStart != null && segmentStart.isBefore(start))) {
      return null;
    }
    return TimerSession(
      targetId: target,
      startedAt: start,
      segmentStartedAt: segmentStart,
      accumulatedSeconds: accumulated,
    );
  }
}
