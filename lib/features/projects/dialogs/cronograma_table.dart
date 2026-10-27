import 'package:flutter/material.dart';

/// Reads the entire recognized Excel table; the aggregate is weighted by hours.
class ScheduleRow {
  ScheduleRow(this.fields, this.edits);
  final Map<String, Map<String, dynamic>> fields;
  final Map<String, Map<String, dynamic>> edits;
  dynamic value(String column) {
    final field = fields[column];
    return field == null
        ? null
        : edits[field['cell']]?['value'] ?? field['value'];
  }

  String get work => (value('I') ?? '').toString().trim();
  double? get minutes {
    if (['Cancelado', 'Reprogramado', ''].contains(value('H'))) return 0;
    double parse(dynamic v) {
      if (v == null || v == '') return 0;
      final parts = v.toString().split(':');
      if (parts.length != 2) return double.nan;
      return (double.tryParse(parts[0]) ?? double.nan) * 60 +
          (double.tryParse(parts[1]) ?? double.nan);
    }

    final morning = parse(value('D')) - parse(value('C'));
    final afternoon = parse(value('F')) - parse(value('E'));
    final total = morning + afternoon;
    return total.isFinite && morning >= 0 && afternoon >= 0 ? total : null;
  }
}

List<ScheduleRow> scheduleRows(List<Map<String, dynamic>> fields,
    Map<String, Map<String, dynamic>> edits) {
  final rows = <int, Map<String, Map<String, dynamic>>>{};
  for (final field in fields) {
    final match =
        RegExp(r'^([B-I])([0-9]+)$').firstMatch(field['cell'] as String);
    if (match == null) continue;
    final row = int.parse(match[2]!);
    if (row <= 5) continue;
    (rows[row] ??= {})[match[1]!] = field;
  }
  return rows.values
      .map((r) => ScheduleRow(r, edits))
      .where((r) => r.work.isNotEmpty)
      .toList();
}

Map<String, double?> scheduleProgress(List<ScheduleRow> rows) {
  final totals = <String, double>{}, done = <String, double>{};
  final invalid = <String>{};
  for (final row in rows) {
    final minutes = row.minutes;
    if (minutes == null) {
      invalid.add(row.work);
      continue;
    }
    totals.update(row.work, (v) => v + minutes, ifAbsent: () => minutes);
    final status = row.value('H');
    final completed = status is num ? minutes * status : 0.0;
    done.update(row.work, (v) => v + completed, ifAbsent: () => completed);
  }
  return {
    for (final work in rows.map((r) => r.work).toSet())
      work: invalid.contains(work)
          ? null
          : (totals[work] ?? 0) == 0
              ? 0
              : (done[work] ?? 0) / totals[work]!
  };
}

class CronogramaTable extends StatelessWidget {
  const CronogramaTable(
      {super.key,
      required this.fields,
      required this.edits,
      required this.onEdit,
      required this.onStatus,
      required this.busy,
      required this.vertical,
      required this.horizontal});
  final List<Map<String, dynamic>> fields;
  final Map<String, Map<String, dynamic>> edits;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>, dynamic) onStatus;
  final bool busy;
  final ScrollController vertical, horizontal;

  String display(ScheduleRow row, String col) {
    final field = row.fields[col];
    final v = row.value(col);
    if (col == 'G') {
      if (['Cancelado', 'Reprogramado', ''].contains(row.value('H'))) return '';
      final minutes = row.minutes;
      if (minutes == null) return 'Horário inválido';
      return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes.toInt() % 60).toString().padLeft(2, '0')}';
    }
    if (col == 'B') {
      final date = DateTime.tryParse(v.toString());
      if (date != null) {
        const days = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${days[date.weekday - 1]}';
      }
    }
    if (field != null && !edits.containsKey(field['cell'])) {
      return (field['display'] ?? v ?? '').toString();
    }
    return (v ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final rows = scheduleRows(fields, edits);
    final progress = scheduleProgress(rows);
    final colors = Theme.of(context).colorScheme;
    const columns = ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'];
    return LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
            controller: vertical,
            thumbVisibility: true,
            child: SingleChildScrollView(
                controller: vertical,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Scrollbar(
                          controller: horizontal,
                          thumbVisibility: true,
                          notificationPredicate: (n) => n.depth == 0,
                          child: SingleChildScrollView(
                              controller: horizontal,
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth),
                                  child: DataTable(
                                      headingRowColor: WidgetStatePropertyAll(
                                          colors.primaryContainer),
                                      dataRowMinHeight: 44,
                                      dataRowMaxHeight: 52,
                                      columnSpacing: 20,
                                      columns: [
                                        for (final title in [
                                          'Data',
                                          'Manhã início',
                                          'Manhã fim',
                                          'Tarde início',
                                          'Tarde fim',
                                          'Total',
                                          'Status',
                                          'Trabalho / Descrição'
                                        ])
                                          DataColumn(label: Text(title))
                                      ],
                                      rows: [
                                        for (var index = 0;
                                            index < rows.length;
                                            index++)
                                          DataRow(
                                              color: WidgetStatePropertyAll(rows[
                                                          index]
                                                      .fields
                                                      .values
                                                      .any((f) =>
                                                          edits.containsKey(
                                                              f['cell']))
                                                  ? colors.tertiaryContainer
                                                  : index.isOdd
                                                      ? colors
                                                          .surfaceContainerLow
                                                      : null),
                                              cells: [
                                                for (final col in columns)
                                                  DataCell(
                                                      col == 'H' &&
                                                              rows[index].fields[col]?['readOnly'] !=
                                                                  true
                                                          ? SizedBox(
                                                              width: 134,
                                                              child:
                                                                  DropdownButton<
                                                                          dynamic>(
                                                                      key: ValueKey(
                                                                          'schedule-status-${rows[index].fields[col]?['cell']}'),
                                                                      isExpanded:
                                                                          true,
                                                                      value: rows[index]
                                                                          .value(
                                                                              col),
                                                                      items: [
                                                                        for (final status
                                                                            in <dynamic>{
                                                                          0.0,
                                                                          .25,
                                                                          .5,
                                                                          .75,
                                                                          1.0,
                                                                          'Programado',
                                                                          'Cancelado',
                                                                          rows[index]
                                                                              .value(col)
                                                                        })
                                                                          DropdownMenuItem(
                                                                              value: status,
                                                                              child: Text(status is num ? '${(status * 100).toStringAsFixed(status * 100 == (status * 100).roundToDouble() ? 0 : 1)}%' : (status ?? '').toString()))
                                                                      ],
                                                                      onChanged: busy
                                                                          ? null
                                                                          : (v) => onStatus(
                                                                              rows[index].fields[
                                                                                  col]!,
                                                                              v)))
                                                          : Text(display(
                                                              rows[index],
                                                              col)),
                                                      onTap: busy ||
                                                              col == 'G' ||
                                                              col == 'H' ||
                                                              rows[index].fields[col] ==
                                                                  null ||
                                                              rows[index].fields[col]!['readOnly'] == true
                                                          ? null
                                                          : () => onEdit(rows[index].fields[col]!))
                                              ])
                                      ])))),
                      const SizedBox(height: 16),
                      const Text('Progresso por trabalho · prévia',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'Ponderado pelas horas de cada encontro. As fórmulas do Excel são preservadas.'),
                      for (final entry in progress.entries)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      '${entry.key} · ${entry.value == null ? 'Confira os horários' : '${(entry.value! * 100).toStringAsFixed(1).replaceAll('.', ',')}%'}'),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                      value: (entry.value ?? 0).clamp(0, 1)),
                                ])),
                    ]))));
  }
}
