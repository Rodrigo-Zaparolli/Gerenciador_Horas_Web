import '../../core/platform/speech.dart';

/// Owns speech only for its screen/dialog. Text remains visible without audio.
class TheoReplies {
  TheoReplies({SpeechClientFactory? factory})
      : _client = (factory ?? createSpeechClient)();
  final SpeechClient _client;
  bool enabled = true;
  bool _disposed = false;
  Future<void> say(String text) async {
    if (_disposed || !enabled) return;
    try {
      await _client.speak(text);
    } catch (_) {/* Text is the fallback. */}
  }

  void cancel() => _client.cancel();
  void dispose() {
    _disposed = true;
    _client.dispose();
  }
}

String spokenHours(int minutes) {
  final hours = minutes ~/ 60, rest = minutes % 60;
  final parts = <String>[
    if (hours > 0) '$hours ${hours == 1 ? 'hora' : 'horas'}',
    if (rest > 0) '$rest ${rest == 1 ? 'minuto' : 'minutos'}',
  ];
  return parts.isEmpty ? 'zero horas' : parts.join(' e ');
}

bool isCancelHoursReview(String speech) {
  final text = speech
      .toLowerCase()
      .trim()
      .replaceAll('é', 'e')
      .replaceAll('ã', 'a')
      .replaceAll(RegExp(r'[.,!?:;]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'^(?:theo|teo) '), '');
  return const {'cancelar', 'cancelar envio', 'cancelar o envio', 'nao enviar'}
      .contains(text);
}
