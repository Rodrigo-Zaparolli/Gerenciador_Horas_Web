typedef SpeechClientFactory = SpeechClient Function();

abstract class SpeechClient {
  bool get supported;
  Future<bool> speak(String text);
  void cancel();
  void dispose();
}
