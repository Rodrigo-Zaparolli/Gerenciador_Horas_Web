import 'speech_types.dart';

SpeechClient createSpeechClient() => _SilentSpeech();

class _SilentSpeech implements SpeechClient {
  @override
  bool get supported => false;
  @override
  Future<bool> speak(String text) async => false;
  @override
  void cancel() {}
  @override
  void dispose() {}
}
