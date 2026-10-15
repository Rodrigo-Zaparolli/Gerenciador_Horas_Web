typedef VoiceEventHandler = void Function(String type, String value);
typedef VoiceClientFactory = VoiceClient Function(VoiceEventHandler onEvent);

abstract class VoiceClient {
  bool get supported;
  void start();
  void stop();
  void dispose();
}
