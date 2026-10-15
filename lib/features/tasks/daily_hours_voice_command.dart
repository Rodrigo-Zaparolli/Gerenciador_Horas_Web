import 'package:flutter/material.dart';
import '../../core/platform/voice.dart';
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
      this.clock = DateTime.now});
  final String? accountKey;
  final bool enabled;
  final Future<List<TimeLog>> Function(DateTime) loadDay;
  final Future<void> Function(List<TimeLog>) onSend;
  final ValueChanged<bool>? onBusyChanged;
  final bool Function(String)? accountIsCurrent;
  final VoiceClientFactory? clientFactory;
  final DateTime Function() clock;
  @override
  State<DailyHoursVoiceCommand> createState() => _DailyHoursVoiceCommandState();
}

class _DailyHoursVoiceCommandState extends State<DailyHoursVoiceCommand> {
  int _revision = 0;
  int _scope = 0;
  bool _busy = false;
  String _message = '';

  @override
  void didUpdateWidget(DailyHoursVoiceCommand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountKey != widget.accountKey ||
        oldWidget.enabled != widget.enabled) {
      _scope++;
    }
  }

  Future<void> _recognized(String speech) async {
    if (_busy || !widget.enabled || widget.accountKey == null) return;
    final owner = widget.accountKey;
    final scope = _scope;
    bool current() =>
        mounted &&
        _scope == scope &&
        widget.enabled &&
        widget.accountKey == owner &&
        (widget.accountIsCurrent?.call(owner!) ?? true) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    // Rebuild cancels recognition before any dialog or asynchronous operation.
    setState(() {
      _revision++;
      _message = '';
    });
    if (!isSendTodayHoursCommand(speech)) {
      setState(() =>
          _message = 'Comando não reconhecido. Diga: enviar horas do dia.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Buscando os apontamentos de hoje…';
    });
    widget.onBusyChanged?.call(true);
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
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          // Each day's total uses the same start/end calculation as delivery.
          context: context,
          barrierDismissible: false,
          builder: (_) => _DailyHoursReview(day: day, logs: logs));
      if (!current() || confirmed != true) return;
      setState(() => _message = 'Encaminhando horas ao E-Desk…');
      await widget.onSend(logs);
    } catch (_) {
      if (current()) {
        setState(() => _message =
            'Não foi possível preparar todas as horas. Verifique a conexão e tente novamente.');
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
            VoiceDictationButton(
                idleLabel: 'Comando de voz',
                activeLabel: 'Parar comando',
                enabled: widget.enabled && !_busy && widget.accountKey != null,
                sessionKey: '${widget.accountKey}/$_revision',
                clientFactory: widget.clientFactory,
                onText: _recognized),
            Text(
                _message.isEmpty
                    ? 'Diga “enviar horas do dia” e confira antes de enviar.'
                    : _message,
                style: TextStyle(color: AppPalette.secondary, fontSize: 11)),
          ]);
}

int dayHoursMinutes(TimeLog log) {
  final start = WorkDuration.clock(log.startTime),
      end = WorkDuration.clock(log.endTime);
  return start != null && end != null && end > start ? end - start : 0;
}

class _DailyHoursReview extends StatelessWidget {
  const _DailyHoursReview({required this.day, required this.logs});
  final DateTime day;
  final List<TimeLog> logs;
  @override
  Widget build(BuildContext context) {
    final date =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
    final total =
        logs.fold<int>(0, (value, log) => value + dayHoursMinutes(log));
    return AlertDialog(
        title: const Text('Conferir horas do dia'),
        content: SizedBox(
            width: 620,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '$date · ${logs.length} apontamento(s) · ${WorkDuration.format(total)}'),
                  const SizedBox(height: 8),
                  const Text(
                      'Confira os registros. Envios já existentes serão verificados pela integração.'),
                  const SizedBox(height: 8),
                  Flexible(
                      child: SingleChildScrollView(
                          child: Column(children: [
                    for (final log in logs)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              '${log.projectName ?? log.targetId} · ${log.taskName ?? ''}'),
                          subtitle: Text(
                              '${log.startTime}–${log.endTime}\n${log.description ?? ''}')),
                  ]))),
                ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar e enviar'))
        ]);
  }
}
