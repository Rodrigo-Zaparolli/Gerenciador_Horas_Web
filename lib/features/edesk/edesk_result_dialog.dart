import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/platform/speech.dart';

String hoursCompletionReply(bool confirmed) => confirmed
    ? 'As horas estão confirmadas no E-Desk. O processamento foi concluído.'
    : 'O E-Desk não confirmou o cadastro das horas. Confira os registros antes de reenviar.';

/// Reads the authoritative result when it becomes visible, before "Entendi".
class EdeskResultDialog extends StatefulWidget {
  const EdeskResultDialog(
      {super.key,
      required this.confirmed,
      required this.message,
      this.completeProgress = false,
      this.spokenHoursResult = false,
      this.canSpeak,
      this.speechFactory});
  final bool confirmed, completeProgress, spokenHoursResult;
  final String message;
  final bool Function()? canSpeak;
  final SpeechClientFactory? speechFactory;
  @override
  State<EdeskResultDialog> createState() => _EdeskResultDialogState();
}

class _EdeskResultDialogState extends State<EdeskResultDialog> {
  late final SpeechClient _speaker;
  @override
  void initState() {
    super.initState();
    _speaker = (widget.speechFactory ?? createSpeechClient)();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.spokenHoursResult &&
          (widget.canSpeak?.call() ?? true) &&
          ModalRoute.of(context)?.isCurrent != false) {
        unawaited(_say());
      }
    });
  }

  Future<void> _say() async {
    try {
      await _speaker.speak(hoursCompletionReply(widget.confirmed));
    } catch (_) {/* The result remains readable without audio. */}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) _speaker.cancel();
  }

  @override
  void dispose() {
    _speaker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(
              widget.confirmed ? 'Envio concluído' : 'Envio não confirmado'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (widget.confirmed && widget.completeProgress) ...[
                      const LinearProgressIndicator(value: 1),
                      const SizedBox(height: 8),
                      const Text('100% — envio confirmado'),
                      const SizedBox(height: 16),
                    ],
                    Text(widget.message),
                    if (widget.spokenHoursResult) ...[
                      const SizedBox(height: 12),
                      Text('Théo: ${hoursCompletionReply(widget.confirmed)}'),
                      TextButton.icon(
                          onPressed: _speaker.cancel,
                          icon: const Icon(Icons.volume_off_outlined, size: 17),
                          label: const Text('Silenciar Théo')),
                    ],
                  ]))),
          actions: [
            TextButton(
                onPressed: () {
                  _speaker.cancel();
                  Navigator.pop(context);
                },
                child: const Text('Entendi'))
          ]);
}
