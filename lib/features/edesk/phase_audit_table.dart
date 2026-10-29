import 'package:flutter/material.dart';
import 'work_audit.dart';

typedef PhaseAuditEntry = ({
  String reference,
  String? error,
  List<AuditFieldResult> fields
});

class PhaseAuditTable extends StatelessWidget {
  const PhaseAuditTable(
      {super.key,
      required this.results,
      required this.onAdjust,
      this.busy = false});
  final List<PhaseAuditEntry> results;
  final void Function(String reference, List<AuditFieldResult> fields) onAdjust;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final rows = results.where((r) =>
        r.fields.any((f) => f.field == 'phaseName' && f.edesk.isNotEmpty));
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Fases do projeto',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Text(
                      'Datas ajustadas da aba Fases do E-Desk e datas planejadas no sistema.'),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(columns: const [
                        DataColumn(
                            label: Text('Solicita\u00e7\u00e3o / trabalho')),
                        DataColumn(label: Text('Fase')),
                        DataColumn(label: Text('Sistema\nIn\u00edcio / fim')),
                        DataColumn(
                            label:
                                Text('E-Desk (ajustadas)\nIn\u00edcio / fim')),
                        DataColumn(label: Text('Resultado')),
                        DataColumn(label: Text('Ajustar')),
                      ], rows: [
                        for (final row in rows) _row(row)
                      ])),
                  const SizedBox(height: 8),
                  const Text(
                      'Escolha o sentido e confirme as datas antes de salvar. A consulta n\u00e3o altera cadastros.'),
                ])));
  }

  DataRow _row(PhaseAuditEntry row) {
    final fields = {for (final f in row.fields) f.field: f};
    String dates(bool app) => ['start', 'end'].map((key) {
          final value = app ? fields[key]?.app : fields[key]?.edesk;
          return value?.isNotEmpty == true ? value! : 'N\u00e3o informado';
        }).join('\n');
    final consulted =
        ['start', 'end'].every((k) => fields[k]?.edesk.isNotEmpty == true);
    final equal = ['start', 'end'].every((k) => fields[k]?.state == 'Igual');
    return DataRow(cells: [
      DataCell(Text(row.reference)),
      DataCell(Text(fields['phaseName']!.edesk)),
      DataCell(Text(dates(true))),
      DataCell(Text(dates(false))),
      DataCell(Text(!consulted
          ? 'Consulta parcial'
          : equal
              ? 'Datas iguais'
              : 'Conferir diferen\u00e7as')),
      DataCell(OutlinedButton.icon(
          onPressed: busy ? null : () => onAdjust(row.reference, row.fields),
          icon: const Icon(Icons.sync_alt),
          label: const Text('Ajustar datas')))
    ]);
  }
}
