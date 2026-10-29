import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/services/edesk_service.dart';
import '../../data/services/firebase_service.dart';
import '../../domain/models/project_model.dart';
import 'phase_date_sync.dart';
import 'work_audit.dart';

class PhaseDateSyncDialog extends StatefulWidget {
  const PhaseDateSyncDialog(
      {super.key,
      required this.project,
      required this.task,
      required this.request,
      required this.phase,
      required this.edeskStart,
      required this.edeskEnd});
  final ProjectModel project;
  final TaskModel task;
  final String request, phase, edeskStart, edeskEnd;
  @override
  State<PhaseDateSyncDialog> createState() => _PhaseDateSyncDialogState();
}

class _PhaseDateSyncDialogState extends State<PhaseDateSyncDialog> {
  late final String? _owner;
  late final String _expectedStart, _expectedEnd, _expectedStage;
  bool _toEdesk = false, _busy = false;
  DateTime? _start, _end;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _owner = FirebaseAuth.instance.currentUser?.uid;
    _expectedStart = auditDate(widget.task.planStart);
    _expectedEnd = auditDate(widget.task.planEnd);
    _expectedStage = widget.task.stage;
    _resetDates();
  }

  void _resetDates() {
    _start = _toEdesk
        ? parsePhaseDate(_expectedStart)
        : parsePhaseDate(widget.edeskStart);
    _end = _toEdesk
        ? parsePhaseDate(_expectedEnd)
        : parsePhaseDate(widget.edeskEnd);
  }

  Future<void> _pick(bool start) async {
    final date = await showDatePicker(
        context: context,
        initialDate: (start ? _start : _end) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (date != null && mounted) {
      setState(() {
        if (start) {
          _start = date;
        } else {
          _end = date;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_busy ||
        _owner == null ||
        FirebaseAuth.instance.currentUser?.uid != _owner) {
      return;
    }
    if (_start == null || _end == null) {
      setState(() => _message = 'Informe as duas datas.');
      return;
    }
    try {
      validatePhaseDates(_start!, _end!);
    } on FormatException catch (e) {
      setState(() => _message = e.message);
      return;
    }
    final start = _start!, end = _end!, toEdesk = _toEdesk;
    final oldStart = toEdesk ? widget.edeskStart : _expectedStart;
    final oldEnd = toEdesk ? widget.edeskEnd : _expectedEnd;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(toEdesk
                    ? 'Confirmar envio ao E-Desk'
                    : 'Confirmar ajuste no sistema'),
                content: Text(
                    'Solicita\u00e7\u00e3o ${widget.request} / Trabalho ${widget.task.edeskWorkNumber}\n'
                    'Fase: ${widget.phase}\n\n'
                    'In\u00edcio: ${oldStart.isEmpty ? "N\u00e3o informado" : oldStart} \u2192 ${auditDate(start)}\n'
                    'Fim: ${oldEnd.isEmpty ? "N\u00e3o informado" : oldEnd} \u2192 ${auditDate(end)}\n\n'
                    '${toEdesk ? "Somente as datas ajustadas desta fase no E-Desk ser\u00e3o alteradas." : "Somente as datas planejadas deste trabalho no sistema ser\u00e3o alteradas."}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirmar altera\u00e7\u00e3o'))
                ]));
    if (confirmed != true ||
        !mounted ||
        FirebaseAuth.instance.currentUser?.uid != _owner) {
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    var success = false;
    try {
      if (toEdesk) {
        final result = await EdeskService().atualizarFasesViaPython(
            id: widget.request,
            cliente: widget.project.client,
            fases: [
              {
                'nome': widget.phase,
                'dataInicial': auditDate(start),
                'dataFinal': auditDate(end)
              }
            ]);
        if (!result.confirmed) {
          throw StateError(result.message.isEmpty
              ? 'Envio sem confirma\u00e7\u00e3o. Confira o E-Desk antes de repetir.'
              : result.message);
        }
      } else {
        await FirebaseService().applyAuditedPhaseDates(
            ownerUid: _owner,
            projectId: widget.project.id,
            request: widget.request,
            work: widget.task.edeskWorkNumber,
            phase: _expectedStage,
            expectedStart: _expectedStart,
            expectedEnd: _expectedEnd,
            start: start,
            end: end);
      }
      success = true;
    } catch (e) {
      if (mounted && FirebaseAuth.instance.currentUser?.uid == _owner) {
        setState(() => _message = e is StateError
            ? e.message
            : 'N\u00e3o foi poss\u00edvel confirmar a altera\u00e7\u00e3o. Confira o destino antes de repetir.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (success && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: Text('Ajustar fase: ${widget.phase}'),
          content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(
                        'Solicita\u00e7\u00e3o ${widget.request} / Trabalho ${widget.task.edeskWorkNumber}'),
                    const SizedBox(height: 16),
                    Text(
                        'Sistema: ${auditDate(widget.task.planStart)} \u2014 ${auditDate(widget.task.planEnd)}'),
                    Text(
                        'E-Desk (ajustadas): ${widget.edeskStart} \u2014 ${widget.edeskEnd}'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<bool>(
                        initialValue: _toEdesk,
                        decoration: const InputDecoration(
                            labelText: 'Sentido da altera\u00e7\u00e3o'),
                        items: const [
                          DropdownMenuItem(
                              value: false,
                              child: Text('E-Desk \u2192 Sistema')),
                          DropdownMenuItem(
                              value: true, child: Text('Sistema \u2192 E-Desk'))
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _toEdesk = v!;
                                  _resetDates();
                                  _message = '';
                                })),
                    const SizedBox(height: 16),
                    const Text(
                        'Confira ou ajuste as datas que ser\u00e3o gravadas no destino:'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pick(true),
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                              'In\u00edcio: ${_start == null ? "Selecionar" : auditDate(_start)}')),
                      OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pick(false),
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                              'Fim: ${_end == null ? "Selecionar" : auditDate(_end)}'))
                    ]),
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const Text(
                          'Salvando e aguardando confirma\u00e7\u00e3o...')
                    ],
                    if (_message.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_message)),
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child:
                    Text(_toEdesk ? 'Salvar no E-Desk' : 'Salvar no sistema'))
          ]));
}
