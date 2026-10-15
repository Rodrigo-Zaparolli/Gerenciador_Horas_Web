import 'dart:async';
import 'dart:js_interop';
import 'speech_types.dart';

@JS('projectSpeechSupported')
external JSBoolean _supported();
@JS('projectSpeechSpeak')
external JSNumber _speak(JSString text, JSFunction callback);
@JS('projectSpeechCancel')
external void _cancel(JSNumber id);

SpeechClient createSpeechClient() => _WebSpeech();

class _WebSpeech implements SpeechClient {
  int? _id;
  Completer<bool>? _pending;
  bool _disposed = false;
  @override
  bool get supported {
    try {
      return _supported().toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> speak(String text) {
    cancel();
    if (_disposed || !supported || text.trim().isEmpty) {
      return Future.value(false);
    }
    final pending = Completer<bool>();
    _pending = pending;
    try {
      final id = _speak(
              text.toJS,
              ((JSBoolean completed) {
                if (!pending.isCompleted) pending.complete(completed.toDart);
                if (_pending == pending) {
                  _pending = null;
                  _id = null;
                }
              }).toJS)
          .toDartInt;
      if (_pending == pending) _id = id;
    } catch (_) {
      if (!pending.isCompleted) pending.complete(false);
      _pending = null;
    }
    return pending.future;
  }

  @override
  void cancel() {
    final id = _id;
    _id = null;
    try {
      if (id != null) _cancel(id.toJS);
    } catch (_) {}
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}
