import 'dart:convert';
import 'dart:js_interop';
import 'voice_types.dart';

@JS('projectVoiceSupported')
external JSBoolean _supported();
@JS('projectVoiceStart')
external JSNumber _start(JSFunction callback);
@JS('projectVoiceStop')
external void _stop(JSNumber id);
@JS('projectVoiceCancel')
external void _cancel(JSNumber id);

VoiceClient createVoiceClient(VoiceEventHandler onEvent) => _WebVoice(onEvent);

class _WebVoice implements VoiceClient {
  _WebVoice(this.onEvent);
  final VoiceEventHandler onEvent;
  int? _id;
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
  void start() {
    if (_disposed) return;
    _id = _start(((JSString raw) {
      if (_disposed) return;
      final data = jsonDecode(raw.toDart) as Map<String, dynamic>;
      onEvent(data['type'] as String, data['value'] as String);
    }).toJS)
        .toDartInt;
  }

  @override
  void stop() {
    if (!_disposed && _id != null) _stop(_id!.toJS);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_id != null) _cancel(_id!.toJS);
    _id = null;
  }
}
