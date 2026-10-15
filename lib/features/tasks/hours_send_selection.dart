import 'package:flutter/material.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';

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
      required this.onChanged});
  final List<TimeLog> logs;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

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
    {required bool Function() canSend}) {
  var selected = Set<int>.from(List.generate(logs.length, (i) => i));
  return showDialog<List<TimeLog>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
              title: const Text('Selecionar horas para enviar'),
              content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                      child: HoursSendSelection(
                          logs: logs,
                          selected: selected,
                          onChanged: (value) =>
                              setState(() => selected = value)))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () {
                            if (!canSend()) return;
                            Navigator.pop(dialogContext, [
                              for (var i = 0; i < logs.length; i++)
                                if (selected.contains(i)) logs[i]
                            ]);
                          },
                    child: const Text('Confirmar e enviar')),
              ],
            )),
  );
}
