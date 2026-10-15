import 'voice_types.dart';

VoiceClient createVoiceClient(VoiceEventHandler onEvent) => _UnavailableVoice();

class _UnavailableVoice implements VoiceClient {
  @override
  bool get supported => false;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() {}
}
