import 'package:flutter/material.dart';
import 'checklist_live_preview.dart';

class ChecklistStatusPanel extends StatefulWidget {
  const ChecklistStatusPanel(
      {super.key, required this.controller, required this.unsaved});
  final ChecklistLivePreview controller;
  final bool unsaved;
  @override
  State<ChecklistStatusPanel> createState() => _ChecklistStatusPanelState();
}

class _ChecklistStatusPanelState extends State<ChecklistStatusPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.activate();
    });
  }

  String percent(dynamic value) => value is num
      ? '${(value * 100).toStringAsFixed(1).replaceAll('.', ',')}%'
      : '—';
  String date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? '—'
        : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  Widget progress(BuildContext context, dynamic value) {
    if (value is! num) return Text(percent(value));
    final colors = Theme.of(context).colorScheme;
    return Semantics(
        value: percent(value),
        child: SizedBox(
            width: 104,
            height: 22,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(children: [
                  Positioned.fill(
                      child: ColoredBox(
                          color: colors.primary.withValues(alpha: .06))),
                  Positioned.fill(
                      child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: value.toDouble().clamp(0.0, 1.0),
                          child: ColoredBox(
                              color: colors.primary.withValues(alpha: .22)))),
                  Center(
                      child: Text(percent(value),
                          style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600))),
                ]))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final preview = widget.controller;
        final data = preview.data;
        final rows = (data?['rows'] as List? ?? []).whereType<Map>().toList();
        final dates = rows.any((r) => r.containsKey('start'));
        final planned = rows.any((r) => r.containsKey('planned'));
        return Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Expanded(
                            child: Text('Status Projeto',
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        if (data != null)
                          Flexible(
                              child: Text('Total: ${percent(data['total'])}',
                                  key:
                                      const ValueKey('checklist-preview-total'),
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                        IconButton(
                            tooltip: 'Atualizar prévia',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                preview.updating ? null : preview.refresh,
                            icon: const Icon(Icons.refresh, size: 18)),
                      ]),
                      Text(
                          preview.error != null
                              ? 'Prévia desatualizada. Tente atualizar novamente.'
                              : preview.stale || preview.updating
                                  ? 'Atualizando porcentagens… Os valores anteriores ainda não incluem os últimos ajustes.'
                                  : widget.unsaved
                                      ? 'Prévia das alterações pendentes. Use Salvar na planilha para gravar.'
                                      : 'Porcentagens calculadas pelo Excel.',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (preview.updating)
                        const LinearProgressIndicator(minHeight: 2),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (preview.error != null)
                              SelectableText(preview.error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                            if (data != null)
                              SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                      headingRowHeight: 30,
                                      dataRowMinHeight: 30,
                                      dataRowMaxHeight: 32,
                                      horizontalMargin: 8,
                                      columnSpacing: 22,
                                      columns: [
                                        const DataColumn(
                                            label: Text('Trabalho')),
                                        const DataColumn(
                                            label: Text('Realizado')),
                                        if (dates) ...[
                                          const DataColumn(
                                              label: Text('Início')),
                                          const DataColumn(label: Text('Fim'))
                                        ],
                                        const DataColumn(label: Text('Peso')),
                                        if (planned)
                                          const DataColumn(
                                              label: Text('Prev. p/data'))
                                      ],
                                      rows: [
                                        for (final row in rows)
                                          DataRow(cells: [
                                            DataCell(Text(
                                                row['label']?.toString() ??
                                                    '')),
                                            DataCell(progress(
                                                context, row['percentage'])),
                                            if (dates) ...[
                                              DataCell(
                                                  Text(date(row['start']))),
                                              DataCell(Text(date(row['end'])))
                                            ],
                                            DataCell(
                                                Text(percent(row['weight']))),
                                            if (planned)
                                              DataCell(Text(
                                                  percent(row['planned']))),
                                          ])
                                      ])),
                          ]),
                    ]))));
      });
}
