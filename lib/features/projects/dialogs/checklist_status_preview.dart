import 'package:flutter/material.dart';
import 'checklist_live_preview.dart';

class ChecklistStatusPanel extends StatefulWidget {
  const ChecklistStatusPanel(
      {super.key,
      required this.controller,
      required this.unsaved,
      this.compact = false});
  final ChecklistLivePreview controller;
  final bool unsaved;
  final bool compact;
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
            width: widget.compact ? 120 : 144,
            child: Row(children: [
              Expanded(
                  child: LinearProgressIndicator(
                      value: value.toDouble().clamp(0.0, 1.0),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(6),
                      color: colors.primary,
                      backgroundColor: colors.primary.withValues(alpha: .12))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 48,
                  child: Text(percent(value),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600))),
            ])));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final preview = widget.controller;
        final data = preview.data;
        final colors = Theme.of(context).colorScheme;
        final rows = (data?['rows'] as List? ?? []).whereType<Map>().toList();
        final dates = rows.any((r) => r.containsKey('start'));
        final planned = rows.any((r) => r.containsKey('planned'));
        return Card(
            elevation: 0,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: Wrap(
                                        spacing: 10,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                      Text('Status Projeto',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700)),
                                      Text('Pr\u00e9via autom\u00e1tica',
                                          style: TextStyle(
                                              color: colors.onSurfaceVariant,
                                              fontSize: 11)),
                                      IconButton(
                                          tooltip: 'Atualizar pr\u00e9via',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: preview.updating
                                              ? null
                                              : preview.refresh,
                                          icon: const Icon(Icons.refresh,
                                              size: 17)),
                                    ])),
                                const SizedBox(width: 12),
                                if (data != null)
                                  SizedBox(
                                      width:
                                          MediaQuery.sizeOf(context).width < 600
                                              ? 120
                                              : 190,
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(percent(data['total']),
                                                key: const ValueKey(
                                                    'checklist-preview-total'),
                                                style: TextStyle(
                                                    fontSize: 28,
                                                    height: 1,
                                                    fontWeight: FontWeight.w700,
                                                    color: colors.onSurface)),
                                            Text('Progresso total',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: colors
                                                        .onSurfaceVariant)),
                                            const SizedBox(height: 7),
                                            if (data['total'] is num)
                                              LinearProgressIndicator(
                                                  value: (data['total'] as num)
                                                      .toDouble()
                                                      .clamp(0.0, 1.0),
                                                  minHeight: 6,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  backgroundColor: colors
                                                      .primary
                                                      .withValues(alpha: .12)),
                                          ])),
                              ]),
                          const SizedBox(height: 10),
                          if (preview.updating)
                            const LinearProgressIndicator(minHeight: 2),
                          if (preview.error != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SelectableText(preview.error!,
                                    style: TextStyle(color: colors.error))),
                          if (data != null)
                            LayoutBuilder(
                                builder: (context, constraints) =>
                                    SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                                minWidth: constraints.maxWidth),
                                            child: DataTable(
                                                headingRowHeight: 28,
                                                dataRowMinHeight: 28,
                                                dataRowMaxHeight: 30,
                                                headingTextStyle: TextStyle(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12),
                                                dataTextStyle: TextStyle(
                                                    color: colors.onSurface,
                                                    fontSize: 12),
                                                horizontalMargin: 4,
                                                columnSpacing:
                                                    widget.compact ? 12 : 18,
                                                columns: [
                                                  const DataColumn(
                                                      label: Text('Etapa')),
                                                  const DataColumn(
                                                      label: Text('Realizado')),
                                                  if (dates) ...[
                                                    const DataColumn(
                                                        label: Text(
                                                            'In\u00edcio')),
                                                    const DataColumn(
                                                        label: Text('Fim'))
                                                  ],
                                                  const DataColumn(
                                                      label: Text('Peso')),
                                                  if (planned)
                                                    const DataColumn(
                                                        label: Text('Previsto'))
                                                ],
                                                rows: [
                                                  for (final row in rows)
                                                    DataRow(cells: [
                                                      DataCell(Text(row['label']
                                                              ?.toString() ??
                                                          '')),
                                                      DataCell(progress(context,
                                                          row['percentage'])),
                                                      if (dates) ...[
                                                        DataCell(Text(date(
                                                            row['start']))),
                                                        DataCell(Text(
                                                            date(row['end'])))
                                                      ],
                                                      DataCell(Text(percent(
                                                          row['weight']))),
                                                      if (planned)
                                                        DataCell(progress(
                                                            context,
                                                            row['planned'])),
                                                    ])
                                                ])))),
                          const SizedBox(height: 7),
                          Text(
                              preview.error != null
                                  ? 'Pr\u00e9via desatualizada. Tente atualizar novamente.'
                                  : preview.stale || preview.updating
                                      ? 'Atualizando porcentagens\u2026 Os valores anteriores ainda n\u00e3o incluem os \u00faltimos ajustes.'
                                      : widget.unsaved
                                          ? 'Pr\u00e9via das altera\u00e7\u00f5es pendentes. Use Salvar na planilha para gravar.'
                                          : 'Porcentagens calculadas pelo Excel.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant)),
                        ]))));
      });
}
