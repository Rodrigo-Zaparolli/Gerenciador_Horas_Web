import 'package:flutter/material.dart';
import 'dart:async';
import 'theo_voice_button.dart';
import 'theo_replies.dart';
import '../../core/platform/voice.dart';
import '../../core/platform/speech.dart';
import '../../core/theme/app_palette.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';
import '../../shared/widgets/voice_dictation_button.dart';

bool isSendTodayHoursCommand(String speech) {
  final normalized = speech
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[.,!?;:]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  return const {
    'enviar horas do dia',
    'enviar as horas do dia',
    'enviar horas de hoje',
    'enviar as horas de hoje',
    'enviar minhas horas do dia',
    'enviar minhas horas de hoje',
    'enviar horas do dia para o e-desk',
    'enviar horas de hoje para o e-desk',
  }.contains(normalized);
}

class DailyHoursVoiceCommand extends StatefulWidget {
  const DailyHoursVoiceCommand(
      {super.key,
      required this.accountKey,
      required this.loadDay,
      required this.onSend,
      this.enabled = true,
      this.onBusyChanged,
      this.accountIsCurrent,
      this.clientFactory,
      this.speechFactory,
      this.clock = DateTime.now});
  final String? accountKey;
  final bool enabled;
  final Future<List<TimeLog>> Function(DateTime) loadDay;
  final Future<void> Function(List<TimeLog>, bool spokenReplies) onSend;
  final ValueChanged<bool>? onBusyChanged;
  final bool Function(String)? accountIsCurrent;
  final VoiceClientFactory? clientFactory;
  final SpeechClientFactory? speechFactory;
  final DateTime Function() clock;
  @override
  State<DailyHoursVoiceCommand> createState() => _DailyHoursVoiceCommandState();
}

class _DailyHoursVoiceCommandState extends State<DailyHoursVoiceCommand> {
  int _revision = 0;
  int _scope = 0;
  bool _busy = false;
  String _message = '';
  String _reply = '';
  bool _spokenReplies = true;
  late final TheoReplies _speaker;

  @override
  void initState() {
    super.initState();
    _speaker = TheoReplies(factory: widget.speechFactory);
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

  void _answer(String text) {
    if (!mounted ||
        !widget.enabled ||
        widget.accountKey == null ||
        !(widget.accountIsCurrent?.call(widget.accountKey!) ?? true) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => _reply = text);
    unawaited(_speaker.say(text));
  }

  @override
  void didUpdateWidget(DailyHoursVoiceCommand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountKey != widget.accountKey ||
        oldWidget.enabled != widget.enabled) {
      _scope++;
      _speaker.cancel();
      _reply = '';
    }
  }

  Future<void> _recognized(String speech) async {
    if (_busy || !widget.enabled || widget.accountKey == null) return;
    final owner = widget.accountKey;
    final scope = _scope;
    bool sameScope() =>
        mounted &&
        _scope == scope &&
        widget.enabled &&
        widget.accountKey == owner &&
        (widget.accountIsCurrent?.call(owner!) ?? true);
    bool current() =>
        sameScope() && (ModalRoute.of(context)?.isCurrent ?? true);
    // Rebuild cancels recognition before any dialog or asynchronous operation.
    setState(() {
      _revision++;
      _message = '';
    });
    if (!isSendTodayHoursCommand(speech)) {
      setState(() =>
          _message = 'Comando não reconhecido. Diga: enviar horas do dia.');
      _answer(
          'Não entendi esse comando. Posso preparar as horas de hoje para conferência.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Buscando os apontamentos de hoje…';
    });
    widget.onBusyChanged?.call(true);
    _answer('Vou buscar os apontamentos de hoje.');
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!current()) return;
      final now = widget.clock();
      final day = DateTime(now.year, now.month, now.day);
      final loaded = await widget.loadDay(day);
      if (!current()) return;
      // Defense in depth: callers cannot add another date or running timers.
      final logs = loaded
          .where((log) =>
              log.isRegistered &&
              log.date.year == day.year &&
              log.date.month == day.month &&
              log.date.day == day.day)
          .toList();
      if (logs.isEmpty) {
        setState(
            () => _message = 'Nenhum apontamento registrado hoje para enviar.');
        _answer('Não encontrei apontamentos registrados hoje para enviar.');
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          // Each day's total uses the same start/end calculation as delivery.
          context: context,
          barrierDismissible: false,
          builder: (_) => _DailyHoursReview(
              day: day,
              logs: logs,
              spokenReplies: _spokenReplies,
              speechFactory: widget.speechFactory,
              clientFactory: widget.clientFactory,
              canInteract: sameScope));
      if (!current()) return;
      if (confirmed != true) {
        _answer('Certo, nenhum apontamento foi enviado.');
        return;
      }
      setState(() => _message = 'Encaminhando horas ao E-Desk…');
      await widget.onSend(logs, _spokenReplies);
    } catch (_) {
      if (current()) {
        setState(() => _message =
            'Não foi possível preparar todas as horas. Verifique a conexão e tente novamente.');
        _answer(
            'Não consegui carregar todas as horas. Verifique a conexão e tente novamente.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (widget.accountKey != owner ||
              _message == 'Buscando os apontamentos de hoje…' ||
              _message == 'Encaminhando horas ao E-Desk…') {
            _message = '';
          }
        });
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(spacing: 16, runSpacing: 6, children: [
              VoiceDictationButton(
                  idleLabel: 'Comando de voz',
                  activeLabel: 'Parar comando',
                  enabled:
                      widget.enabled && !_busy && widget.accountKey != null,
                  sessionKey: '${widget.accountKey}/$_revision',
                  clientFactory: widget.clientFactory,
                  onText: _recognized),
              TheoVoiceButton(
                  enabled:
                      widget.enabled && !_busy && widget.accountKey != null,
                  sessionKey: '${widget.accountKey}/$_revision',
                  clientFactory: widget.clientFactory,
                  accepts: isSendTodayHoursCommand,
                  onReply: _answer,
                  onStop: _speaker.cancel,
                  onCommand: _recognized),
              FilterChip(
                  label: const Text('Respostas faladas'),
                  avatar: Icon(
                      _spokenReplies
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                      size: 17),
                  selected: _spokenReplies,
                  onSelected: (selected) {
                    setState(() {
                      _spokenReplies = selected;
                      _speaker.enabled = selected;
                    });
                    if (!selected) _speaker.cancel();
                  }),
            ]),
            Text(
                _message.isEmpty
                    ? 'Com Théo ativo, diga “Théo, enviar horas do dia”. Confira antes de enviar. O áudio pode ser processado online.'
                    : _message,
                style: TextStyle(color: AppPalette.secondary, fontSize: 11)),
            if (_reply.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Théo: $_reply',
                      style: TextStyle(color: AppPalette.text, fontSize: 12))),
          ]);
}

int dayHoursMinutes(TimeLog log) {
  final start = WorkDuration.clock(log.startTime),
      end = WorkDuration.clock(log.endTime);
  return start != null && end != null && end > start ? end - start : 0;
}

class _DailyHoursReview extends StatefulWidget {
  const _DailyHoursReview(
      {required this.day,
      required this.logs,
      required this.spokenReplies,
      required this.canInteract,
      this.speechFactory,
      this.clientFactory});
  final DateTime day;
  final List<TimeLog> logs;
  final bool spokenReplies;
  final bool Function() canInteract;
  final SpeechClientFactory? speechFactory;
  final VoiceClientFactory? clientFactory;
  @override
  State<_DailyHoursReview> createState() => _DailyHoursReviewState();
}

class _DailyHoursReviewState extends State<_DailyHoursReview> {
  late final TheoReplies _speaker;
  late String _reply;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _speaker = TheoReplies(factory: widget.speechFactory)
      ..enabled = widget.spokenReplies;
    final total =
        widget.logs.fold<int>(0, (value, log) => value + dayHoursMinutes(log));
    _reply =
        'Encontrei ${widget.logs.length} ${widget.logs.length == 1 ? 'apontamento' : 'apontamentos'}, '
        'totalizando ${spokenHours(total)}. Abri a conferência para você revisar. '
        'Para cancelar, diga cancelar. Para enviar, confira e clique em Confirmar e enviar.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.canInteract() &&
          ModalRoute.of(context)?.isCurrent != false) {
        unawaited(_speaker.say(_reply));
      }
    });
  }

  @override
  void dispose() {
    _speaker.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) _speaker.cancel();
  }

  void _close(bool send) {
    if (_closing) return;
    if (send && !widget.canInteract()) return;
    _closing = true;
    _speaker.cancel();
    Navigator.pop(context, send);
  }

  void _heard(String text) {
    if (_closing ||
        !widget.canInteract() ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (isCancelHoursReview(text)) {
      _close(false);
      return;
    }
    setState(() => _reply =
        'Não entendi. Você pode dizer cancelar. Para enviar, revise os registros e clique em Confirmar e enviar.');
    unawaited(_speaker.say(_reply));
  }

  @override
  Widget build(BuildContext context) {
    final date =
        '${widget.day.day.toString().padLeft(2, '0')}/${widget.day.month.toString().padLeft(2, '0')}/${widget.day.year}';
    final total =
        widget.logs.fold<int>(0, (value, log) => value + dayHoursMinutes(log));
    return AlertDialog(
        title: const Text('Conferir horas do dia'),
        content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '$date · ${widget.logs.length} apontamento(s) · ${WorkDuration.format(total)}'),
                  const SizedBox(height: 8),
                  const Text(
                      'Confira os registros. Envios já existentes serão verificados pela integração.'),
                  const SizedBox(height: 8),
                  Text('Théo: $_reply',
                      style: TextStyle(color: AppPalette.text, fontSize: 12)),
                  const SizedBox(height: 6),
                  VoiceDictationButton(
                      autoStart: true,
                      cancelOnStop: true,
                      idleLabel: 'Ativar voz na conferência',
                      activeLabel: 'Parar voz na conferência',
                      listeningHint: 'Após a resposta, diga “cancelar”.',
                      onStop: _speaker.cancel,
                      onText: _heard,
                      clientFactory: widget.clientFactory),
                  const SizedBox(height: 8),
                  for (final log in widget.logs)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${log.projectName ?? log.targetId} · ${log.taskName ?? ''}'),
                        subtitle: Text(
                            '${log.startTime}–${log.endTime}\n${log.description ?? ''}')),
                ]))),
        actions: [
          TextButton(
              onPressed: () => _close(false), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => _close(true),
              child: const Text('Confirmar e enviar'))
        ]);
  }
}
