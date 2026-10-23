import 'package:flutter/material.dart';

class ChecklistStageDialog extends StatefulWidget {
  const ChecklistStageDialog(
      {super.key,
      required this.stage,
      required this.tasks,
      required this.values,
      required this.canApply});
  final String stage;
  final List<Map<String, dynamic>> tasks;
  final Map<String, double> values;
  final bool Function() canApply;
  static String fieldKey(Map<String, dynamic> task) =>
      '${task['sheet']}!${task['cell']}';
  @override
  State<ChecklistStageDialog> createState() => _ChecklistStageDialogState();
}

class _ChecklistStageDialogState extends State<ChecklistStageDialog> {
  final _scroll = ScrollController();
  late final Map<String, double> _values;
  bool _pendingOnly = false;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final task in widget.tasks)
        ChecklistStageDialog.fieldKey(task):
            widget.values[ChecklistStageDialog.fieldKey(task)] ?? 0
    };
  }

  void apply() {
    if (!widget.canApply()) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, Map<String, double>.from(_values));
  }

  String percentage(double value) {
    final percent = value * 100;
    return '${percent == percent.roundToDouble() ? percent.toInt() : percent.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  List<double> options(String key) {
    const steps = [0.0, .25, .5, .75, 1.0];
    final original = widget.values[key] ?? 0;
    // Preserve pre-existing Excel values exactly when filtering or applying.
    return [...steps, if (!steps.contains(original)) original]..sort();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = widget.tasks
        .where((task) =>
            !_pendingOnly || _values[ChecklistStageDialog.fieldKey(task)] != 1)
        .toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(widget.stage),
      content: SizedBox(
          width: 820,
          height: (MediaQuery.sizeOf(context).height * .60).clamp(160.0, 570.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${shown.length} de ${widget.tasks.length} tarefas'),
            SwitchListTile.adaptive(
                key: const ValueKey('stage-pending-only'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Somente pendentes'),
                value: _pendingOnly,
                onChanged: (value) => setState(() => _pendingOnly = value)),
            const SizedBox(height: 8),
            Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text('Nenhuma tarefa pendente nesta etapa.'))
                    : Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ListView(controller: _scroll, children: [
                          for (final task in shown)
                            Card(
                                key: ValueKey(
                                    'stage-task-${ChecklistStageDialog.fieldKey(task)}'),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    task['label']?.toString() ??
                                                        '',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                Text(
                                                    'Estimado: ${task['estimated'] ?? '—'}',
                                                    style: TextStyle(
                                                        color: colors
                                                            .onSurfaceVariant)),
                                                if ((task['note']?.toString() ??
                                                        '')
                                                    .isNotEmpty)
                                                  Text(task['note'].toString(),
                                                      style: TextStyle(
                                                          color: colors
                                                              .onSurfaceVariant)),
                                              ])),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                              width: 112,
                                              child: DropdownButtonFormField<
                                                  double>(
                                                key: ValueKey(
                                                    'stage-percent-${ChecklistStageDialog.fieldKey(task)}-${_values[ChecklistStageDialog.fieldKey(task)]}'),
                                                initialValue: _values[
                                                    ChecklistStageDialog
                                                        .fieldKey(task)],
                                                isExpanded: true,
                                                decoration: const InputDecoration(
                                                    labelText: 'Realizado',
                                                    border:
                                                        OutlineInputBorder()),
                                                items: [
                                                  for (final value in options(
                                                      ChecklistStageDialog
                                                          .fieldKey(task)))
                                                    DropdownMenuItem(
                                                        value: value,
                                                        child: Text(
                                                            percentage(value)))
                                                ],
                                                onChanged:
                                                    task['readOnly'] == true
                                                        ? null
                                                        : (value) {
                                                            if (value != null) {
                                                              setState(() => _values[
                                                                  ChecklistStageDialog
                                                                      .fieldKey(
                                                                          task)] = value);
                                                            }
                                                          },
                                              )),
                                        ]))),
                        ]))),
            const SizedBox(height: 12),
            const Text(
                'Aplicar ajustes atualiza o editor e a prévia do Status Projeto. Para gravar no Excel, use Salvar na planilha.'),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton.icon(
            onPressed: apply,
            icon: const Icon(Icons.check),
            label: const Text('Aplicar ajustes')),
      ],
    );
  }
}
