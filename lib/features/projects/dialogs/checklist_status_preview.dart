import 'package:flutter/material.dart';

class ChecklistStatusPreview extends StatelessWidget {
  const ChecklistStatusPreview(
      {super.key, required this.data, required this.unsaved});
  final Map<String, dynamic> data;
  final bool unsaved;
  String percent(dynamic value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';
  String date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? '—'
        : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = (data['rows'] as List? ?? []).whereType<Map>().toList();
    final dates = rows.any((r) => r.containsKey('start'));
    final planned = rows.any((r) => r.containsKey('planned'));
    return AlertDialog(
      title: const Text('Prévia da porcentagem — Status Projeto'),
      content: SizedBox(
          width: 800,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Progresso total: ${percent(data['total'])}',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(unsaved
                    ? 'Simulação com as alterações pendentes. O arquivo original não foi alterado. Use Salvar na planilha para confirmar.'
                    : 'Calculado pelo Excel em uma cópia temporária. O arquivo original não foi alterado.'),
                const SizedBox(height: 16),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(columns: [
                      const DataColumn(label: Text('Trabalho')),
                      const DataColumn(label: Text('Realizado')),
                      if (dates) ...[
                        const DataColumn(label: Text('Início')),
                        const DataColumn(label: Text('Fim'))
                      ],
                      const DataColumn(label: Text('Peso')),
                      if (planned) const DataColumn(label: Text('Prev. p/data'))
                    ], rows: [
                      for (final row in rows)
                        DataRow(cells: [
                          DataCell(Text(row['label']?.toString() ?? '')),
                          DataCell(Text(percent(row['percentage']))),
                          if (dates) ...[
                            DataCell(Text(date(row['start']))),
                            DataCell(Text(date(row['end'])))
                          ],
                          DataCell(Text(percent(row['weight']))),
                          if (planned) DataCell(Text(percent(row['planned']))),
                        ])
                    ])),
                const SizedBox(height: 12),
                Text('Origem: ${data['source'] ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall),
              ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar ao checklist'))
      ],
    );
  }
}
