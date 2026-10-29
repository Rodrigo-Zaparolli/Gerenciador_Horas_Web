import 'package:flutter/material.dart';
import 'work_audit.dart';

class WorkAuditResultCard extends StatelessWidget {
  const WorkAuditResultCard(
      {super.key,
      required this.reference,
      required this.fields,
      this.error,
      this.showPhaseDates = true});
  final String reference;
  final List<AuditFieldResult> fields;
  final String? error;
  final bool showPhaseDates;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mapped = {for (final f in fields) f.field: f};
    final identity = RegExp(r'^(\d+)(?:/(\d+))?$').firstMatch(reference);
    final heading = identity == null
        ? reference
        : identity[2] == null
            ? 'Solicita\u00e7\u00e3o ${identity[1]}'
            : 'Solicita\u00e7\u00e3o ${identity[1]} / Trabalho ${identity[2]}';
    final name = mapped['name'];
    final title = name?.edesk.trim().isNotEmpty == true
        ? name!.edesk
        : name?.app.isNotEmpty == true
            ? '${name!.app} (app)'
            : '';
    final summary = auditWorkSummary(fields, error: error);
    final hasReadValues = fields.any((f) => f.edesk.trim().isNotEmpty);
    final partial = summary == 'Confer\u00eancia parcial';
    final needsReview = summary != 'Consulta conclu\u00edda';
    final completed = auditNormalized(mapped['completed']?.edesk ?? '');
    const labels = {
      'start': 'In\u00edcio ajustado (Fases)',
      'end': 'Fim ajustado (Fases)',
      'estimatedHours': 'Horas previstas',
      'hours': 'Horas trabalhadas',
      'remainingHours': 'Horas restantes',
      'overrunHours': 'Horas excedentes',
    };
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(heading,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: colors.onSurfaceVariant)),
                          if (title.isNotEmpty)
                            Text(title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                        ]),
                    Chip(
                        avatar: Icon(
                            needsReview
                                ? Icons.info_outline
                                : Icons.check_circle_outline,
                            size: 18),
                        label: Text(summary)),
                  ]),
              if (hasReadValues && mapped.containsKey('phaseName'))
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(mapped['phaseName']!.edesk.isEmpty
                        ? 'Fase n\u00e3o consultada'
                        : 'Fase: ${mapped['phaseName']!.edesk}')),
              if (hasReadValues)
                Wrap(spacing: 12, runSpacing: 4, children: [
                  if (mapped.containsKey('completed'))
                    Chip(
                        avatar: Icon(
                            completed == 'sim'
                                ? Icons.task_alt
                                : Icons.pending_outlined,
                            size: 18),
                        label: Text(completed == 'sim'
                            ? 'Trabalho conclu\u00eddo'
                            : completed == 'nao'
                                ? 'Trabalho n\u00e3o conclu\u00eddo'
                                : 'Conclus\u00e3o n\u00e3o consultada')),
                  if (mapped['status']?.edesk.isNotEmpty == true)
                    Chip(label: Text(mapped['status']!.edesk)),
                ]),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SelectableText(error!,
                        style: TextStyle(color: colors.error))),
              if (hasReadValues)
                LayoutBuilder(builder: (context, size) {
                  final columns = size.maxWidth >= 800
                      ? (showPhaseDates ? 3 : 4)
                      : size.maxWidth >= 420
                          ? 2
                          : 1;
                  final width = (size.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final entry in labels.entries)
                      if (mapped.containsKey(entry.key) &&
                          (showPhaseDates ||
                              !const {'start', 'end'}.contains(entry.key)))
                        SizedBox(
                            width: width,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.value,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                        mapped[entry.key]!.edesk.isEmpty
                                            ? 'N\u00e3o consultado'
                                            : mapped[entry.key]!.edesk,
                                        style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                mapped[entry.key]!.edesk.isEmpty
                                                    ? colors.onSurfaceVariant
                                                    : colors.onSurface)),
                                    if (mapped[entry.key]!.state ==
                                        'Diverg\u00eancia')
                                      Text('No app: ${mapped[entry.key]!.app}',
                                          style:
                                              TextStyle(color: colors.error)),
                                    if (mapped[entry.key]!
                                        .state
                                        .startsWith('Revisar'))
                                      Text(mapped[entry.key]!.state,
                                          style:
                                              TextStyle(color: colors.error)),
                                  ]),
                            )),
                  ]);
                }),
              if (partial && hasReadValues)
                const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                        'Campos n\u00e3o consultados permanecem sem valor; n\u00e3o representam zero.')),
              if (fields.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Comparar com os dados do app'),
                  subtitle: const Text(
                      'Consulta; nenhuma altera\u00e7\u00e3o foi salva.'),
                  children: [
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(columns: const [
                          DataColumn(label: Text('Campo')),
                          DataColumn(label: Text('App')),
                          DataColumn(label: Text('E-Desk')),
                          DataColumn(label: Text('Resultado')),
                        ], rows: [
                          for (final f in fields)
                            DataRow(cells: [
                              DataCell(Text(auditFields[f.field] ?? f.field)),
                              DataCell(SelectableText(
                                  f.app.isEmpty ? '\u2014' : f.app)),
                              DataCell(SelectableText(f.edesk.isEmpty
                                  ? 'N\u00e3o consultado'
                                  : f.edesk)),
                              DataCell(Text(f.state)),
                            ])
                        ]))
                  ],
                ),
            ],
          )),
    );
  }
}
