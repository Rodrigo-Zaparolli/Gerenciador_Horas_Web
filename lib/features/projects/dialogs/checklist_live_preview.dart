import 'dart:async';
import 'package:flutter/foundation.dart';

/// Debounces edits and serializes Excel calculations. Older replies never
/// replace the preview for newer edits; saves can wait for Excel to finish.
class ChecklistLivePreview extends ChangeNotifier {
  ChecklistLivePreview({required this.calculate});
  final Future<Map<String, dynamic>> Function() calculate;
  Map<String, dynamic>? data;
  String? error;
  bool updating = false, stale = true;
  bool _active = false, _paused = false, _disposed = false, _dirty = false;
  int _generation = 0;
  Timer? _timer;
  Future<void>? _job;

  void activate() {
    if (_active || _disposed) return;
    _active = true;
    if (data == null || stale) invalidate();
  }

  void restore(Map<String, dynamic> saved) {
    if (_disposed) return;
    _generation++;
    _timer?.cancel();
    _dirty = false;
    _paused = false;
    data = Map<String, dynamic>.from(saved);
    stale = false;
    error = null;
    updating = false;
    notifyListeners();
  }

  void invalidate({bool clear = false}) {
    if (_disposed) return;
    _generation++;
    stale = true;
    error = null;
    if (clear) data = null;
    _dirty = true;
    _timer?.cancel();
    if (_active && !_paused) {
      _timer = Timer(const Duration(milliseconds: 700), refresh);
    }
    notifyListeners();
  }

  void refresh() {
    if (_disposed || !_active || _paused || _job != null) return;
    _timer?.cancel();
    _dirty = false;
    final generation = _generation;
    updating = true;
    error = null;
    notifyListeners();
    _job = Future<void>.microtask(() => _run(generation));
  }

  Future<void> _run(int generation) async {
    try {
      final result = await calculate();
      if (!_disposed && generation == _generation) {
        data = result;
        stale = false;
      }
    } catch (e) {
      if (!_disposed && generation == _generation) {
        error = e.toString();
        stale = true;
      }
    } finally {
      _job = null;
      updating = false;
      if (!_disposed) {
        notifyListeners();
        if (_dirty && _active && !_paused) refresh();
      }
    }
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
    _generation++;
    _dirty = false;
    stale = true;
  }

  Future<void> pauseAndWait() async {
    pause();
    await _job;
  }

  void resume({bool clear = false}) {
    _paused = false;
    invalidate(clear: clear);
  }

  void clear() {
    _timer?.cancel();
    _generation++;
    _paused = true;
    _dirty = false;
    data = null;
    error = null;
    stale = true;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
