import 'package:flutter/material.dart';
import '../../core/platform/voice.dart';
import '../../shared/widgets/voice_dictation_button.dart';

/// Only a name at the beginning addresses the assistant. A standalone name
/// arms one following phrase for eight seconds, using a monotonic clock.
class TheoWakeMatcher {
  TheoWakeMatcher({Duration Function()? elapsed}) : _clock = elapsed;
  final Duration Function()? _clock;
  final _watch = Stopwatch()..start();
  Duration _elapsed() => _clock?.call() ?? _watch.elapsed;
  Duration? _until;
  bool wasAddressed = false;
  bool get waitingForCommand => _until != null && _elapsed() < _until!;
  void reset() {
    _until = null;
    wasAddressed = false;
  }

  String? command(String speech, bool Function(String) accepts) {
    final text =
        speech.toLowerCase().trim().replaceAll('é', 'e').replaceAll('ê', 'e');
    final name = RegExp(r'^(?:theo|teo)(?:[\s,.:;!?]+|$)').firstMatch(text);
    final armed = _until != null && _elapsed() < _until!;
    reset();
    wasAddressed = name != null || armed;
    if (name == null && !armed) return null;
    final phrase = name == null ? text : text.substring(name.end).trim();
    if (name != null && phrase.isEmpty) {
      _until = _elapsed() + const Duration(seconds: 8);
      return null;
    }
    return accepts(phrase) ? phrase : null;
  }
}

class TheoVoiceButton extends StatefulWidget {
  const TheoVoiceButton(
      {super.key,
      required this.onCommand,
      required this.accepts,
      required this.sessionKey,
      this.enabled = true,
      this.onReply,
      this.onStop,
      this.clientFactory});
  final ValueChanged<String> onCommand;
  final bool Function(String) accepts;
  final Object sessionKey;
  final bool enabled;
  final ValueChanged<String>? onReply;
  final VoidCallback? onStop;
  final VoiceClientFactory? clientFactory;
  @override
  State<TheoVoiceButton> createState() => _TheoVoiceButtonState();
}

class _TheoVoiceButtonState extends State<TheoVoiceButton> {
  final _matcher = TheoWakeMatcher();
  @override
  void didUpdateWidget(TheoVoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.sessionKey != widget.sessionKey) {
      _matcher.reset();
    }
  }

  @override
  Widget build(BuildContext context) => VoiceDictationButton(
      enabled: widget.enabled,
      sessionKey: widget.sessionKey,
      clientFactory: widget.clientFactory,
      idleLabel: 'Ativar Théo',
      activeLabel: 'Desativar Théo',
      listeningHint: 'Théo está ouvindo…',
      idleHint: 'Théo desativado. Ative para chamar pelo nome.',
      cancelOnStop: true,
      onStop: widget.onStop,
      onStart: () {
        _matcher.reset();
        widget.onReply?.call(
            'Estou ouvindo. Pode me chamar pelo nome e pedir para enviar as horas do dia.');
      },
      onText: (speech) {
        final command = _matcher.command(speech, widget.accepts);
        if (command != null) {
          widget.onCommand(command);
        } else if (_matcher.waitingForCommand) {
          widget.onReply?.call('Estou ouvindo. O que deseja fazer?');
        } else if (_matcher.wasAddressed) {
          widget.onReply?.call(
              'Não entendi esse comando. Posso preparar as horas de hoje para conferência.');
        }
      });
}
