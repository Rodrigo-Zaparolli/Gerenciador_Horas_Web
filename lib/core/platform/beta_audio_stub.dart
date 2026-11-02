import 'beta_audio_types.dart';

BetaAudio createBetaAudio(
        void Function(String, String) event, BetaTransport transport) =>
    _Unavailable(event);

class _Unavailable implements BetaAudio {
  _Unavailable(this.event);
  final void Function(String, String) event;
  @override
  void listen(String mode) => event(
      'error', 'A BETA por voz está disponível no navegador deste computador.');
  @override
  void stop() {}
  @override
  Future<void> speak(String text) async {}
  @override
  void dispose() {}
}
