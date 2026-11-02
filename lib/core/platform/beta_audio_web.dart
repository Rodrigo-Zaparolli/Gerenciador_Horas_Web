import 'dart:js_interop';
import 'beta_audio_types.dart';

@JS('betaAudioCreate')
external JSNumber _create(JSFunction event, JSFunction transport);
@JS('betaAudioListen')
external void _listen(JSNumber id, JSString mode);
@JS('betaAudioStop')
external void _stop(JSNumber id);
@JS('betaAudioSpeak')
external JSPromise<JSAny?> _speak(JSNumber id, JSString text);
@JS('betaAudioDispose')
external void _dispose(JSNumber id);
BetaAudio createBetaAudio(
        void Function(String, String) event, BetaTransport transport) =>
    _WebBeta(event, transport);

class _WebBeta implements BetaAudio {
  _WebBeta(void Function(String, String) event, BetaTransport transport) {
    id = _create(
        ((JSString type, JSString value) => event(type.toDart, value.toDart))
            .toJS,
        ((JSString request) =>
            transport(request.toDart).then((value) => value.toJS).toJS).toJS);
  }
  late final JSNumber id;
  bool disposed = false;
  @override
  void listen(String mode) {
    if (!disposed) _listen(id, mode.toJS);
  }

  @override
  void stop() {
    if (!disposed) _stop(id);
  }

  @override
  Future<void> speak(String text) async {
    if (!disposed) await _speak(id, text.toJS).toDart;
  }

  @override
  void dispose() {
    if (!disposed) {
      _dispose(id);
      disposed = true;
    }
  }
}
