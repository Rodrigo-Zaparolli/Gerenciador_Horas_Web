import 'package:flutter/material.dart';
import 'checklist_live_preview.dart';

class ChecklistStageDialog extends StatefulWidget {
  const ChecklistStageDialog(
      {super.key,
      required this.stage,
      required this.tasks,
      required this.values,
      required this.canApply,
      this.calculatePreview});
  final String stage;
  final List<Map<String, dynamic>> tasks;
  final Map<String, double> values;
  final bool Function() canApply;
  final Future<Map<String, dynamic>> Function(Map<String, double>)?
      calculatePreview;
  static String fieldKey(Map<String, dynamic> task) =>
      '${task['sheet']}!${task['cell']}';
  @override
  State<ChecklistStageDialog> createState() => _ChecklistStageDialogState();
}

class _ChecklistStageDialogState extends State<ChecklistStageDialog> {
  final _scroll = ScrollController();
  late final Map<String, double> _values;
  bool _pendingOnly = false;
  ChecklistLivePreview? _preview;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final task in widget.tasks)
        ChecklistStageDialog.fieldKey(task):
            widget.values[ChecklistStageDialog.fieldKey(task)] ?? 0
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preview == null && widget.calculatePreview != null) {
      _preview = ChecklistLivePreview(calculate: () async {
        if (!widget.canApply()) {
          throw StateError('A conta ou a planilha mudou.');
        }
        return widget.calculatePreview!(Map<String, double>.from(_values));
      });
      _preview!.activate();
    }
  }

  Widget stagePreview() => ListenableBuilder(
      listenable: _preview!,
      builder: (context, _) {
        final preview = _preview!;
        final rows = (preview.data?['rows'] as List? ?? []).whereType<Map>();
        final matches = rows
            .where((row) =>
                row['label']?.toString().trim().toLowerCase() ==
                widget.stage.trim().toLowerCase())
            .toList();
        final value = matches.length == 1 ? matches.single['percentage'] : null;
        final valid = value is num;
        return Card(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(widget.stage,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (valid)
                Text(percentage(value.toDouble()),
                    key: const ValueKey('stage-live-percentage')),
              IconButton(
                  tooltip: 'Atualizar prévia',
                  onPressed: preview.updating ? null : preview.refresh,
                  icon: const Icon(Icons.refresh, size: 18)),
            ]),
            if (valid)
              LinearProgressIndicator(
                  value: value.toDouble().clamp(0, 1), minHeight: 8),
            Text(
                preview.error != null
                    ? 'Não foi possível calcular a prévia. Tente atualizar.'
                    : preview.updating || preview.stale
                        ? 'Calculando na planilha...'
                        : valid
                            ? 'Prévia dos ajustes desta etapa'
                            : 'Etapa sem correspondência na tabela Status Projeto.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ));
      });

  Future<void> apply() async {
    await _preview?.pauseAndWait();
    if (!mounted) return;
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
    _preview?.dispose();
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
            if (_preview != null) stagePreview(),
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
                          for (var index = 0;
                              index < shown.length;
                              index++) ...[
                            if (blockId(shown[index]).isNotEmpty &&
                                (index == 0 ||
                                    blockId(shown[index - 1]) !=
                                        blockId(shown[index])))
                              blockControl(
                                  blockId(shown[index]),
                                  shown[index]['block']?.toString() ??
                                      'Bloco de tarefas'),
                            taskCard(shown[index], colors),
                          ],
                        ]))),
            const SizedBox(height: 12),
            const Text(
                'Aplicar ajustes atualiza o editor e a prévia do Status Projeto. Para gravar no Excel, use Salvar na planilha.'),
          ])),
      actions: [
        TextButton(
            onPressed: () async {
              await _preview?.pauseAndWait();
              if (mounted) Navigator.pop(this.context);
            },
            child: const Text('Cancelar')),
        FilledButton.icon(
            onPressed: apply,
            icon: const Icon(Icons.check),
            label: const Text('Aplicar ajustes')),
      ],
    );
  }

  String blockId(Map<String, dynamic> task) =>
      task['blockId']?.toString() ?? '';

  Widget blockControl(String id, String label) {
    final tasks = widget.tasks
        .where((task) => blockId(task) == id && task['readOnly'] != true)
        .toList();
    final current = tasks
        .map((task) => _values[ChecklistStageDialog.fieldKey(task)])
        .toSet();
    final value = current.length == 1 &&
            const [0.0, .25, .5, .75, 1.0].contains(current.single)
        ? current.single
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<double>(
          key: ValueKey('stage-block-$id-$value'),
          initialValue: value,
          decoration: const InputDecoration(
              labelText: 'Aplicar percentual a todo o bloco',
              border: OutlineInputBorder()),
          hint: const Text('Valores diferentes'),
          items: [
            for (final step in const [0.0, .25, .5, .75, 1.0])
              DropdownMenuItem(value: step, child: Text(percentage(step)))
          ],
          onChanged: tasks.isEmpty
              ? null
              : (value) {
                  if (value == null || !widget.canApply()) return;
                  setState(() {
                    for (final task in tasks) {
                      _values[ChecklistStageDialog.fieldKey(task)] = value;
                    }
                  });
                  _preview?.invalidate();
                },
        ),
        const SizedBox(height: 4),
        Text(
            'Aplica a todas as tarefas editáveis deste bloco, inclusive as ocultas pelo filtro.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget taskCard(Map<String, dynamic> task, ColorScheme colors) => Card(
      key: ValueKey('stage-task-${ChecklistStageDialog.fieldKey(task)}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(task['label']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Estimado: ${task['estimated'] ?? '—'}',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  if ((task['note']?.toString() ?? '').isNotEmpty)
                    Text(task['note'].toString(),
                        style: TextStyle(color: colors.onSurfaceVariant)),
                ])),
            const SizedBox(width: 12),
            SizedBox(
                width: 112,
                child: DropdownButtonFormField<double>(
                  key: ValueKey(
                      'stage-percent-${ChecklistStageDialog.fieldKey(task)}-${_values[ChecklistStageDialog.fieldKey(task)]}'),
                  initialValue: _values[ChecklistStageDialog.fieldKey(task)],
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Realizado', border: OutlineInputBorder()),
                  items: [
                    for (final value
                        in options(ChecklistStageDialog.fieldKey(task)))
                      DropdownMenuItem(
                          value: value, child: Text(percentage(value)))
                  ],
                  onChanged: task['readOnly'] == true
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() =>
                                _values[ChecklistStageDialog.fieldKey(task)] =
                                    value);
                            _preview?.invalidate();
                          }
                        },
                )),
          ])));
}
