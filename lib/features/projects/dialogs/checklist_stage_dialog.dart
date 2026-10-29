import 'checklist_stage_progress.dart';
import 'package:flutter/material.dart';
import 'checklist_live_preview.dart';

class ChecklistStageDialog extends StatefulWidget {
  const ChecklistStageDialog(
      {super.key,
      required this.stage,
      required this.tasks,
      required this.values,
      required this.canApply,
      this.expandableBlocks = false,
      this.calculatePreview,
      this.initialPreview});
  final Map<String, dynamic>? initialPreview;
  final String stage;
  final bool expandableBlocks;
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
  bool _closing = false;
  final Set<String> _collapsedBlocks = {};
  ChecklistLivePreview? _preview;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final task in widget.tasks)
        ChecklistStageDialog.fieldKey(task):
            widget.values[ChecklistStageDialog.fieldKey(task)] ?? 0
    };
    _collapsedBlocks.addAll(
        widget.tasks.map(blockId).where((id) => id.isNotEmpty).toSet().skip(1));
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

  Widget stagePreview() {
    Widget content(BuildContext context) {
      final preview = _preview;
      final data = preview?.data ?? widget.initialPreview;
      final matches = (data?['rows'] as List? ?? [])
          .whereType<Map>()
          .where((row) =>
              row['label']?.toString().trim().toLowerCase() ==
              widget.stage.trim().toLowerCase())
          .toList();
      final immediate =
          immediateStageProgress(widget.stage, widget.tasks, _values, data);
      final value = immediate ??
          (matches.length == 1 ? matches.single['percentage'] : null);
      final valid = value is num && value.isFinite && value >= 0 && value <= 1;
      final colors = Theme.of(context).colorScheme;
      final status = preview?.error != null
          ? (immediate != null
              ? 'Pr\u00e9via dos ajustes; confirma\u00e7\u00e3o da planilha pendente.'
              : 'N\u00e3o foi poss\u00edvel atualizar a pr\u00e9via.')
          : preview != null && (preview.updating || preview.stale)
              ? (immediate != null
                  ? 'Pr\u00e9via imediata dos ajustes'
                  : 'Atualizando na planilha...')
              : valid
                  ? 'Percentual conforme os pesos do Excel.'
                  : 'Percentual ainda indispon\u00edvel';
      Widget progress() => Row(children: [
            Expanded(
                child: LinearProgressIndicator(
              key: const ValueKey('stage-live-progress'),
              value: valid ? value.toDouble() : 0,
              minHeight: 10,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: colors.primary.withValues(alpha: .14),
              semanticsLabel: 'Progresso de ${widget.stage}',
              semanticsValue: valid
                  ? '${(value.toDouble() * 100).toStringAsFixed(2)}%'
                  : null,
            )),
            const SizedBox(width: 12),
            SizedBox(
                width: 76,
                child: Text(
                  valid ? percentage(value.toDouble()) : '\u2014',
                  key: const ValueKey('stage-live-percentage'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.onSurface),
                )),
          ]);
      final title =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.stage, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(status, style: Theme.of(context).textTheme.bodySmall),
      ]);
      return Card(
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
            builder: (context, size) => Row(children: [
                  Expanded(
                      child: size.maxWidth >= 540
                          ? Row(children: [
                              SizedBox(width: 220, child: title),
                              const SizedBox(width: 16),
                              Expanded(child: progress()),
                            ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  title,
                                  const SizedBox(height: 10),
                                  progress(),
                                ])),
                  if (preview != null)
                    IconButton(
                        tooltip: 'Atualizar pr\u00e9via',
                        onPressed: preview.updating ? null : preview.refresh,
                        icon: Icon(
                            preview.updating || preview.stale
                                ? Icons.sync
                                : Icons.refresh,
                            size: 18)),
                ])),
      ));
    }

    return _preview == null
        ? content(context)
        : ListenableBuilder(
            listenable: _preview!, builder: (context, _) => content(context));
  }

  void finish({required bool applyChanges}) {
    if (_closing || !mounted) return;
    _closing = true;
    // Stop scheduling and invalidate replies without blocking navigation on Excel.
    _preview?.clear();
    Navigator.pop(
        context,
        applyChanges && widget.canApply()
            ? Map<String, double>.from(_values)
            : null);
  }

  void apply() => finish(applyChanges: true);

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
    final completed = widget.tasks
        .where((task) => _values[ChecklistStageDialog.fieldKey(task)] == 1)
        .length;
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
            if (_preview != null || widget.initialPreview != null)
              stagePreview(),
            Wrap(spacing: 16, runSpacing: 4, children: [
              Text(
                  '$completed de ${widget.tasks.length} tarefas conclu\u00eddas',
                  key: const ValueKey('stage-completed-count'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${shown.length} de ${widget.tasks.length} tarefas'),
            ]),
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
                        child: ListView(
                            controller: _scroll,
                            children: widget.expandableBlocks
                                ? taskGroups(shown, colors)
                                : legacyTasks(shown, colors)))),
            const SizedBox(height: 12),
            const Text(
                'Aplicar ajustes atualiza o editor e a prévia do Status Projeto. Para gravar no Excel, use Salvar na planilha.'),
          ])),
      actions: [
        TextButton(
            onPressed: () => finish(applyChanges: false),
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

  List<Widget> legacyTasks(
          List<Map<String, dynamic>> shown, ColorScheme colors) =>
      [
        for (var index = 0; index < shown.length; index++) ...[
          if (blockId(shown[index]).isNotEmpty &&
              (index == 0 ||
                  blockId(shown[index - 1]) != blockId(shown[index])))
            legacyBlockControl(blockId(shown[index]),
                shown[index]['block']?.toString() ?? 'Bloco de tarefas'),
          taskCard(shown[index], colors),
        ],
      ];

  Widget legacyBlockControl(String id, String label) {
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

  List<Widget> taskGroups(
      List<Map<String, dynamic>> shown, ColorScheme colors) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final task in shown) {
      final id = blockId(task);
      final groupKey =
          id.isEmpty ? 'task:${ChecklistStageDialog.fieldKey(task)}' : id;
      groups.putIfAbsent(groupKey, () => []).add(task);
    }
    return [
      for (final members in groups.values)
        if (blockId(members.first).isEmpty)
          taskCard(members.first, colors)
        else
          blockCard(blockId(members.first), members, colors),
    ];
  }

  Widget blockCard(
      String id, List<Map<String, dynamic>> shown, ColorScheme colors) {
    final all = widget.tasks.where((task) => blockId(task) == id).toList();
    final editable = all.where((task) => task['readOnly'] != true).toList();
    final current =
        all.map((task) => _values[ChecklistStageDialog.fieldKey(task)]).toSet();
    final value = current.length == 1 ? current.single : null;
    final expanded = !_collapsedBlocks.contains(id);
    final steps = <double>[
      0,
      .25,
      .5,
      .75,
      1,
      if (value != null && !const [0, .25, .5, .75, 1].contains(value)) value
    ]..sort();
    final label = all.first['block']?.toString() ?? 'Bloco de tarefas';
    final control = DropdownButtonFormField<double>(
      key: ValueKey('stage-block-$id-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
          labelText: 'Aplicar a todo o bloco', border: OutlineInputBorder()),
      hint: const Text('Valores diferentes'),
      items: [
        for (final step in steps)
          DropdownMenuItem(value: step, child: Text(percentage(step)))
      ],
      onChanged: editable.isEmpty
          ? null
          : (next) {
              if (next == null || !widget.canApply()) return;
              setState(() {
                for (final task in editable) {
                  _values[ChecklistStageDialog.fieldKey(task)] = next;
                }
              });
              _preview?.invalidate();
            },
    );
    final title = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      IconButton.outlined(
        key: ValueKey('stage-toggle-$id'),
        tooltip: expanded ? 'Recolher tarefas' : 'Expandir tarefas',
        onPressed: () => setState(() {
          if (expanded) {
            _collapsedBlocks.add(id);
          } else {
            _collapsedBlocks.remove(id);
          }
        }),
        icon: Icon(expanded ? Icons.remove : Icons.add, size: 20),
      ),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${all.length} tarefas',
            style: Theme.of(context).textTheme.bodySmall),
      ])),
    ]);
    return Container(
      key: ValueKey('stage-group-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            color: colors.primary.withValues(alpha: .07),
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
                builder: (context, size) => size.maxWidth < 480
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [title, const SizedBox(height: 12), control])
                    : Row(children: [
                        Expanded(child: title),
                        const SizedBox(width: 16),
                        SizedBox(width: 190, child: control)
                      ]))),
        if (expanded)
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 10, 0),
              child: Column(children: [
                for (final task in shown) taskCard(task, colors)
              ])),
      ]),
    );
  }

  bool zeroWeight(Map<String, dynamic> task) {
    final data = _preview?.data ?? widget.initialPreview;
    final weights = data?['taskProgress'];
    if (weights is! Map) return false;
    final item = weights[ChecklistStageDialog.fieldKey(task)];
    return item is Map && item['weight'] is num && item['weight'] == 0;
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
                  Row(children: [
                    Expanded(
                        child: Text(
                            'Estimado: ${task['estimated'] ?? '\u2014'}',
                            style: TextStyle(color: colors.onSurfaceVariant))),
                    if (zeroWeight(task))
                      const Tooltip(
                          message:
                              'Peso zero na planilha: n\u00e3o aumenta a barra.',
                          child: Icon(Icons.info_outline, size: 18)),
                  ]),
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
