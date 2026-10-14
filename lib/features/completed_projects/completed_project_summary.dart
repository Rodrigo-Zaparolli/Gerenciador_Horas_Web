import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

DateTime? completedProjectEndDate(
    Map<String, dynamic> project, DateTime? Function(dynamic) parseDate) {
  final dates = (project['subTasks'] as List? ?? [])
      .whereType<Map>()
      .map((task) => parseDate(task['planEnd']))
      .whereType<DateTime>()
      .toList()
    ..sort();
  return dates.isNotEmpty ? dates.last : parseDate(project['finalizedAt']);
}

class CompletedHoursRow {
  const CompletedHoursRow(this.name, this.planned, this.used);
  final String name;
  final int planned;
  final int used;
  int get balance => planned - used;
  double get ratio => planned > 0 ? used / planned : 0;
}

class CompletedHoursSummary {
  const CompletedHoursSummary(this.total, this.stages);
  final CompletedHoursRow total;
  final List<CompletedHoursRow> stages;

  factory CompletedHoursSummary.calculate({
    required String projectId,
    required String estimatedHours,
    required List<Map<String, dynamic>> tasks,
    required List<TimeLog> logs,
    required int Function(String) parseMinutes,
    required int Function(TimeLog) logMinutes,
  }) {
    final usedByTarget = <String, int>{};
    var total = 0;
    for (final log in logs) {
      final minutes = logMinutes(log);
      total += minutes;
      usedByTarget.update(log.targetId, (value) => value + minutes,
          ifAbsent: () => minutes);
    }
    final stages = <CompletedHoursRow>[];
    final matched = <String>{};
    for (final task in tasks) {
      final subId = task['subId']?.toString() ?? '';
      final target = '${projectId}_$subId';
      final used = subId.isNotEmpty && matched.add(target)
          ? usedByTarget[target] ?? 0
          : 0;
      stages.add(CompletedHoursRow(task['stage']?.toString() ?? 'Etapa',
          parseMinutes(task['estimatedHours']?.toString() ?? '00:00'), used));
    }
    final unmatched = usedByTarget.entries
        .where((entry) => !matched.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
    if (unmatched > 0) {
      stages.add(CompletedHoursRow('Sem etapa vinculada', 0, unmatched));
    }
    return CompletedHoursSummary(
        CompletedHoursRow('Total', parseMinutes(estimatedHours), total),
        stages);
  }
}

String completedHoursText(int minutes) {
  final value = minutes.abs();
  return '${minutes < 0 ? '-' : ''}${(value ~/ 60).toString().padLeft(2, '0')}:'
      '${(value % 60).toString().padLeft(2, '0')}';
}

class CompletedProjectSummaryCard extends StatelessWidget {
  const CompletedProjectSummaryCard({super.key, required this.summary});
  final CompletedHoursSummary summary;

  Widget text(String value,
          {Color? color, double size = 12, bool bold = false}) =>
      Text(value,
          style: TextStyle(
              color: color ?? AppPalette.text,
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400));

  Widget progress(CompletedHoursRow row) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
          value: row.ratio.clamp(0.0, 1.0),
          minHeight: 7,
          color: row.balance < 0 ? AppPalette.warning : AppPalette.accent,
          backgroundColor: AppPalette.field));

  Widget metric(String title, int minutes, Color color) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppPalette.field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.border.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        text(title, color: AppPalette.secondary),
        const SizedBox(height: 5),
        text(completedHoursText(minutes), color: color, size: 24, bold: true),
      ]));

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final total = summary.total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppPalette.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        text('Resumo de horas do projeto', size: 16, bold: true),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final cards = [
            metric('Previstas', total.planned, AppPalette.text),
            metric('Utilizadas', total.used, AppPalette.accent),
            metric('Saldo', total.balance,
                total.balance < 0 ? AppPalette.warning : AppPalette.success)
          ];
          if (constraints.maxWidth < 480) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final card in cards)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8), child: card)
                ]);
          }
          return Row(children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i])
            ]
          ]);
        }),
        const SizedBox(height: 12),
        progress(total),
        const SizedBox(height: 6),
        text(
            total.planned > 0
                ? '${(total.ratio * 100).round()}% das horas previstas utilizadas'
                : 'Sem horas previstas cadastradas',
            color: AppPalette.secondary),
        if (total.balance < 0) ...[
          const SizedBox(height: 4),
          text('Excedente: ${completedHoursText(-total.balance)}',
              color: AppPalette.warning),
        ],
        const SizedBox(height: 12),
        if (summary.stages.isEmpty)
          text('Nenhuma etapa cadastrada', color: AppPalette.secondary)
        else
          LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                      width: constraints.maxWidth < 650
                          ? 650
                          : constraints.maxWidth,
                      child: Table(
                          columnWidths: const {
                            0: FlexColumnWidth(3),
                            1: FlexColumnWidth(2.5),
                            2: FlexColumnWidth(1),
                            3: FlexColumnWidth(1),
                            4: FlexColumnWidth(1)
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                                decoration:
                                    BoxDecoration(color: AppPalette.header),
                                children: [
                                  for (final title in [
                                    'Etapa',
                                    'Progresso',
                                    'Previstas',
                                    'Utilizadas',
                                    'Saldo'
                                  ])
                                    Padding(
                                        padding: const EdgeInsets.all(8),
                                        child:
                                            text(title, size: 11, bold: true))
                                ]),
                            for (final row in summary.stages)
                              TableRow(
                                  decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(
                                              color: AppPalette.border
                                                  .withValues(alpha: 0.45)))),
                                  children: [
                                    Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: text(row.name, size: 11)),
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Row(children: [
                                          Expanded(child: progress(row)),
                                          const SizedBox(width: 6),
                                          text(
                                              row.planned > 0
                                                  ? '${(row.ratio * 100).round()}%'
                                                  : '—',
                                              size: 10)
                                        ])),
                                    Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: text(
                                            completedHoursText(row.planned),
                                            size: 11)),
                                    Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: text(
                                            completedHoursText(row.used),
                                            size: 11,
                                            color: AppPalette.accent)),
                                    Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: text(
                                            completedHoursText(row.balance),
                                            size: 11,
                                            color: row.balance < 0
                                                ? AppPalette.warning
                                                : AppPalette.success)),
                                  ]),
                          ]))))
      ]),
    );
  }
}
