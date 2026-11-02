typedef BetaTransport = Future<String> Function(String request);

abstract class BetaAudio {
  void listen(String mode);
  void stop();
  Future<void> speak(String text);
  void dispose();
}
