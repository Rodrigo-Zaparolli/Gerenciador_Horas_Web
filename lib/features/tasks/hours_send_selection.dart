import 'package:flutter/material.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';
import 'task_log_edit_dialog.dart';
import '../../shared/widgets/recovery_error.dart';

int selectedHoursMinutes(TimeLog log) {
  final start = WorkDuration.clock(log.startTime);
  final end = WorkDuration.clock(log.endTime);
  return start != null && end != null && end > start ? end - start : 0;
}

class HoursSendSelection extends StatelessWidget {
  const HoursSendSelection(
      {super.key,
      required this.logs,
      required this.selected,
      required this.onChanged,
      this.onEdit,
      this.onDelete});
  final List<TimeLog> logs;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final ValueChanged<int>? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final total =
        selected.fold<int>(0, (sum, i) => sum + selectedHoursMinutes(logs[i]));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        tristate: true,
        value: selected.isEmpty
            ? false
            : selected.length == logs.length
                ? true
                : null,
        onChanged: (_) => onChanged(selected.length == logs.length
            ? <int>{}
            : Set<int>.from(List.generate(logs.length, (i) => i))),
        title: const Text('Selecionar todas'),
        subtitle: Text(
            '${selected.length} de ${logs.length} selecionado(s) · ${WorkDuration.format(total)}'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
      for (var i = 0; i < logs.length; i++)
        CheckboxListTile(
          key: ValueKey('hours-selection-$i'),
          secondary: onEdit == null && onDelete == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (onEdit != null)
                    IconButton(
                        tooltip: 'Editar apontamento',
                        onPressed: () => onEdit!(i),
                        icon: const Icon(Icons.edit_outlined)),
                  if (onDelete != null)
                    IconButton(
                        tooltip: 'Excluir apontamento',
                        onPressed: () => onDelete!(i),
                        icon: const Icon(Icons.delete_outline)),
                ]),
          contentPadding: EdgeInsets.zero,
          value: selected.contains(i),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (checked) {
            final next = Set<int>.from(selected);
            if (checked == true) {
              next.add(i);
            } else {
              next.remove(i);
            }
            onChanged(next);
          },
          title: Text(
              '${logs[i].projectName ?? logs[i].targetId} · ${logs[i].taskName ?? ''}'),
          subtitle: Text(
              '${logs[i].date.day.toString().padLeft(2, '0')}/${logs[i].date.month.toString().padLeft(2, '0')}/${logs[i].date.year} · ${logs[i].startTime}–${logs[i].endTime}\n${logs[i].description ?? ''}'),
        ),
    ]);
  }
}

Future<List<TimeLog>?> selectHoursForSend(
        BuildContext context, List<TimeLog> logs,
        {required bool Function() canSend,
        Future<void> Function(TimeLog)? save,
        Future<void> Function(TimeLog)? delete}) =>
    showDialog<List<TimeLog>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HoursReview(
            logs: logs, canSend: canSend, save: save, delete: delete));

class _HoursReview extends StatefulWidget {
  const _HoursReview(
      {required this.logs, required this.canSend, this.save, this.delete});
  final List<TimeLog> logs;
  final bool Function() canSend;
  final Future<void> Function(TimeLog)? save, delete;
  @override
  State<_HoursReview> createState() => _HoursReviewState();
}

class _HoursReviewState extends State<_HoursReview> {
  late final logs = List<TimeLog>.from(widget.logs);
  late Set<int> selected = Set<int>.from(List.generate(logs.length, (i) => i));
  bool busy = false;
  String? error;

  Future<void> edit(int index) async {
    if (busy || !widget.canSend()) return;
    setState(() {
      busy = true;
      error = null;
    });
    TimeLog? updated;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TaskLogEditDialog(
            log: logs[index],
            save: (value) async {
              if (!widget.canSend())
                throw StateError(
                    'A conta mudou. Abra a conferência novamente.');
              await widget.save!(value);
              updated = value;
            }));
    if (!mounted) return;
    setState(() {
      busy = false;
      if (updated != null) logs[index] = updated!;
    });
  }

  Future<void> remove(int index) async {
    if (busy || !widget.canSend()) return;
    setState(() {
      busy = true;
      error = null;
    });
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Excluir apontamento?'),
                content: const Text(
                    'O apontamento será excluído do app. Isso não remove horas já cadastradas no E-Desk. Para apenas não enviar, desmarque o registro.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Excluir')),
                ]));
    try {
      if (confirmed != true || !widget.canSend()) return;
      await widget.delete!(logs[index]);
      if (!mounted) return;
      setState(() {
        logs.removeAt(index);
        selected = {
          for (final i in selected)
            if (i != index) i > index ? i - 1 : i
        };
      });
    } catch (failure) {
      if (mounted)
        setState(() =>
            error = recoveryError(failure, operation: 'excluir o apontamento'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Conferir horas para enviar'),
        content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text(
                      'Selecione os apontamentos que deseja enviar. Edições e exclusões são salvas no app, mesmo se você cancelar o envio.'),
                  if (busy) const Text('Conclua a edição ou exclusão para continuar.'),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  AbsorbPointer(
                      absorbing: busy,
                      child: HoursSendSelection(
                          logs: logs,
                          selected: selected,
                          onChanged: (value) =>
                              setState(() => selected = value),
                          onEdit: widget.save == null ? null : edit,
                          onDelete: widget.delete == null ? null : remove)),
                ]))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: busy || selected.isEmpty
                  ? null
                  : () {
                      if (!widget.canSend()) return;
                      Navigator.pop(context, [
                        for (var i = 0; i < logs.length; i++)
                          if (selected.contains(i)) logs[i]
                      ]);
                    },
              child: const Text('Confirmar e enviar')),
        ],
      ));
}
