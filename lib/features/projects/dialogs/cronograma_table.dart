import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Reads the entire recognized Excel table; the aggregate is weighted by hours.
class ScheduleRow {
  ScheduleRow(this.fields, this.edits, {this.consultoria = false});
  final bool consultoria;
  final Map<String, Map<String, dynamic>> fields;
  final Map<String, Map<String, dynamic>> edits;
  dynamic value(String column) {
    final field = fields[column];
    return field == null
        ? null
        : edits[field['cell']]?['value'] ?? field['value'];
  }

  int get index => int.parse(
      fields.values.first['cell'].toString().replaceAll(RegExp('[A-Z]'), ''));
  String get work => (value('I') ?? '').toString().trim();
  double? get minutes {
    if (!consultoria &&
        ['Cancelado', 'Reprogramado', ''].contains(value('H'))) {
      return 0;
    }
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

List<ScheduleRow> scheduleRows(
    List<Map<String, dynamic>> fields, Map<String, Map<String, dynamic>> edits,
    {bool consultoria = false}) {
  final rows = <int, Map<String, Map<String, dynamic>>>{};
  for (final field in fields) {
    final match =
        RegExp(r'^([B-I])([0-9]+)$').firstMatch(field['cell'] as String);
    if (match == null) continue;
    final row = int.parse(match[2]!);
    if (row <= (consultoria ? 6 : 5)) continue;
    (rows[row] ??= {})[match[1]!] = field;
  }
  return rows.values
      .map((r) => ScheduleRow(r, edits, consultoria: consultoria))
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
    final completed = row.consultoria
        ? (status == 'Realizado' ? minutes : 0.0)
        : status is num
            ? minutes * status
            : 0.0;
    done.update(row.work, (v) => v + completed, ifAbsent: () => completed);
  }
  if (rows.isNotEmpty && rows.first.consultoria) {
    final total = totals.values.fold<double>(0, (a, b) => a + b);
    return {
      for (final work in rows.map((r) => r.work).toSet())
        work: invalid.isNotEmpty
            ? null
            : total == 0
                ? 0
                : (done[work] ?? 0) / total
    };
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
      required this.horizontal,
      this.consultoria = false,
      this.contractHours,
      this.addedRows = const {},
      this.deletedRows = const {},
      this.onAddRow,
      this.onAddRowBelow,
      this.onDeleteRow,
      this.onUndoRow,
      this.onEditValue});
  final List<Map<String, dynamic>> fields;
  final Map<String, Map<String, dynamic>> edits;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>, dynamic) onStatus;
  final bool busy;
  final bool consultoria;
  final String? contractHours;
  final Set<int> addedRows, deletedRows;
  final VoidCallback? onAddRow;
  final void Function(int)? onDeleteRow, onUndoRow, onAddRowBelow;
  final void Function(Map<String, dynamic>, dynamic)? onEditValue;
  final ScrollController vertical, horizontal;

  String display(ScheduleRow row, String col) {
    final field = row.fields[col];
    final v = row.value(col);
    if (col == 'G') {
      if (!consultoria &&
          ['Cancelado', 'Reprogramado', ''].contains(row.value('H'))) {
        return '';
      }
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

  Widget cellWidget(BuildContext context, ScheduleRow row, String col) {
    final field = row.fields[col];
    final removed = deletedRows.contains(row.index);
    final fresh = addedRows.contains(row.index);
    if (col == 'H' && field?['readOnly'] != true) {
      return SizedBox(
          width: 134,
          child: DropdownButton<dynamic>(
              key: ValueKey('schedule-status-${field?['cell']}'),
              isExpanded: true,
              value: row.value(col),
              items: [
                for (final status in <dynamic>{
                  if (!consultoria) ...[0.0, .25, .5, .75, 1.0],
                  if (consultoria) 'Realizado',
                  'Programado',
                  'Cancelado',
                  row.value(col)
                })
                  DropdownMenuItem(
                      value: status,
                      child: Text(
                          status is num
                              ? '${(status * 100).toStringAsFixed(status * 100 == (status * 100).roundToDouble() ? 0 : 1)}%'
                              : (status ?? '').toString(),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis))
              ],
              onChanged: busy || removed ? null : (v) => onStatus(field!, v)));
    }
    if (fresh && field != null && col == 'B') {
      return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Novo',
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.primary)),
            OutlinedButton.icon(
                onPressed: busy ? null : () => onEdit(field),
                icon: const Icon(Icons.event_outlined, size: 14),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                label: Text(
                    row.value('B') == '' ? 'dd/mm/aaaa' : display(row, 'B'))),
          ]);
    }
    if (fresh && field != null && 'CDEF'.contains(col)) {
      return SizedBox(
          width: 78,
          child: TextFormField(
              key: ValueKey('new-time-${field['cell']}'),
              initialValue: (row.value(col) ?? '').toString(),
              enabled: !busy,
              maxLength: 5,
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9:]'))
              ],
              decoration: const InputDecoration(
                  hintText: 'hh:mm',
                  counterText: '',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8)),
              onChanged: (v) => (onEditValue ?? onStatus)(field, v)));
    }
    return Text(display(row, col),
        style: removed
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null);
  }

  Widget consultationSummary(
      List<ScheduleRow> rows, Map<String, double?> progress) {
    String hours(double minutes) =>
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes.toInt() % 60).toString().padLeft(2, '0')}';
    String date(DateTime? value) => value == null
        ? '\u2014'
        : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Resumo da Consultoria \u00b7 pr\u00e9via',
          style: TextStyle(fontWeight: FontWeight.bold)),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final label in [
                'Horas contratadas',
                'Horas programadas',
                'In\u00edcio',
                'Fim',
                'Realizado / Restante',
                'Realizado %',
                'Descri\u00e7\u00e3o'
              ])
                DataColumn(label: Text(label))
            ],
            rows: [
              for (final entry in progress.entries)
                (() {
                  final work = rows.where((r) => r.work == entry.key).toList();
                  final planned =
                      rows.fold<double>(0, (v, r) => v + (r.minutes ?? 0));
                  final done = work
                      .where((r) => r.value('H') == 'Realizado')
                      .fold<double>(0, (v, r) => v + (r.minutes ?? 0));
                  final dates = work
                      .map((r) => DateTime.tryParse(r.value('B').toString()))
                      .whereType<DateTime>()
                      .toList()
                    ..sort();
                  return DataRow(cells: [
                    DataCell(Text(contractHours ?? '\u2014')),
                    DataCell(Text(entry.value == null
                        ? 'Confira os hor\u00e1rios'
                        : hours(planned))),
                    DataCell(Text(date(dates.isEmpty ? null : dates.first))),
                    DataCell(Text(date(dates.isEmpty ? null : dates.last))),
                    DataCell(Text('${hours(done)} / ${hours(planned - done)}')),
                    DataCell(Text(entry.value == null || planned == 0
                        ? '\u2014'
                        : '${(entry.value! * 100).round()}%')),
                    DataCell(Text(entry.key)),
                  ]);
                })()
            ],
          )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final rows = scheduleRows(fields, edits, consultoria: consultoria);
    final activeRows =
        rows.where((r) => !deletedRows.contains(r.index)).toList();
    final progress = scheduleProgress(activeRows);
    if (consultoria && progress.isEmpty) progress['Consultoria'] = 0;
    final colors = Theme.of(context).colorScheme;
    const columns = ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'];
    return LayoutBuilder(builder: (context, constraints) {
      final summary =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (consultoria)
          consultationSummary(activeRows, progress)
        else
          const Text('Progresso por trabalho · prévia',
              style: TextStyle(fontWeight: FontWeight.bold)),
        if (!consultoria)
          const Text(
              'Ponderado pelas horas de cada encontro. As fórmulas do Excel são preservadas.'),
        if (!consultoria)
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
      ]);
      final height =
          constraints.maxHeight < 180 ? 360.0 : constraints.maxHeight;
      final content = SizedBox(
          height: height,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (consultoria) ...[
              const Text('Treinamento / Acompanhamentos',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Horas contratadas: ${contractHours ?? "N\u00e3o informado"}'),
              Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                      key: const ValueKey('add-consultoria-row'),
                      onPressed: busy ? null : onAddRow,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar linha'))),
              const SizedBox(height: 8),
            ],
            Expanded(
                child: Scrollbar(
                    controller: vertical,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                        controller: vertical,
                        child: Scrollbar(
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
                                        columnSpacing: consultoria ? 12 : 20,
                                        columns: [
                                          for (final title in [
                                            'Data',
                                            'Manhã início',
                                            'Manhã fim',
                                            'Tarde início',
                                            'Tarde fim',
                                            'Total',
                                            'Status',
                                            consultoria
                                                ? 'Descri\u00e7\u00e3o'
                                                : 'Trabalho / Descri\u00e7\u00e3o'
                                          ])
                                            DataColumn(label: Text(title)),
                                          if (consultoria)
                                            const DataColumn(
                                                label: Text('A\u00e7\u00f5es')),
                                        ],
                                        rows: [
                                          for (var i = 0; i < rows.length; i++)
                                            DataRow(
                                                color: WidgetStatePropertyAll(deletedRows
                                                        .contains(rows[i].index)
                                                    ? colors.errorContainer
                                                    : addedRows.contains(
                                                            rows[i].index)
                                                        ? colors
                                                            .primaryContainer
                                                        : rows[i]
                                                                .fields
                                                                .values
                                                                .any((f) => edits
                                                                    .containsKey(f[
                                                                        'cell']))
                                                            ? colors
                                                                .tertiaryContainer
                                                            : i.isOdd
                                                                ? colors
                                                                    .surfaceContainerLow
                                                                : null),
                                                cells: [
                                                  for (final col in columns)
                                                    DataCell(cellWidget(context, rows[i], col),
                                                        onTap: busy ||
                                                                deletedRows.contains(
                                                                    rows[i]
                                                                        .index) ||
                                                                col == 'G' ||
                                                                col == 'H' ||
                                                                rows[i].fields[col] ==
                                                                    null ||
                                                                rows[i].fields[col]![
                                                                        'readOnly'] ==
                                                                    true ||
                                                                addedRows.contains(
                                                                        rows[i]
                                                                            .index) &&
                                                                    ('BCDEF'
                                                                        .contains(
                                                                            col))
                                                            ? null
                                                            : () => onEdit(rows[i]
                                                                .fields[col]!)),
                                                  if (consultoria)
                                                    DataCell(deletedRows
                                                            .contains(
                                                                rows[i].index)
                                                        ? Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                                const Text(
                                                                    'Excluir ao salvar',
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            11)),
                                                                TextButton(
                                                                    onPressed: busy
                                                                        ? null
                                                                        : () => onUndoRow?.call(rows[i]
                                                                            .index),
                                                                    style: TextButton.styleFrom(
                                                                        minimumSize: const Size(
                                                                            64,
                                                                            24),
                                                                        padding:
                                                                            EdgeInsets
                                                                                .zero,
                                                                        tapTargetSize:
                                                                            MaterialTapTargetSize
                                                                                .shrinkWrap),
                                                                    child: const Text(
                                                                        'Desfazer'))
                                                              ])
                                                        : Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                                IconButton(
                                                                    key: ValueKey(
                                                                        'add-below-consultoria-row-${rows[i].index}'),
                                                                    tooltip:
                                                                        'Adicionar linha abaixo',
                                                                    onPressed: busy
                                                                        ? null
                                                                        : () => onAddRowBelow?.call(rows[i]
                                                                            .index),
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .playlist_add)),
                                                                IconButton(
                                                                    key: ValueKey(
                                                                        'delete-consultoria-row-${rows[i].index}'),
                                                                    tooltip:
                                                                        'Excluir linha',
                                                                    onPressed: busy
                                                                        ? null
                                                                        : () => onDeleteRow?.call(rows[i]
                                                                            .index),
                                                                    icon: Icon(
                                                                        Icons
                                                                            .delete_outline,
                                                                        color: colors
                                                                            .error))
                                                              ])),
                                                ]),
                                        ]))))))),
            const SizedBox(height: 12),
            SizedBox(
                height: (height * .28).clamp(40.0, 190.0),
                child: SingleChildScrollView(primary: false, child: summary)),
          ]));
      return constraints.maxHeight < 180
          ? SingleChildScrollView(primary: false, child: content)
          : content;
    });
  }
}
