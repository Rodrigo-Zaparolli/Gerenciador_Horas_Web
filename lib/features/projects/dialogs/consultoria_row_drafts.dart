class ConsultoriaRowDrafts {
  final Map<int, List<Map<String, dynamic>>> added = {};
  final Set<int> deleted = {};
  int _next = 1000000;
  bool get dirty => added.isNotEmpty || deleted.isNotEmpty;
  int get count => added.length + deleted.length;
  static int? rowOf(String cell) =>
      int.tryParse(cell.replaceAll(RegExp('[A-Z]'), ''));
  void add(String sheet, String description) {
    final row = ++_next;
    added[row] = [
      for (final c in ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'])
        {
          'sheet': sheet,
          'cell': '$c$row',
          'kind': c == 'B'
              ? 'date'
              : ['C', 'D', 'E', 'F'].contains(c)
                  ? 'time'
                  : 'text',
          'readOnly': c == 'G' || c == 'I',
          'value': c == 'H'
              ? 'Programado'
              : c == 'I'
                  ? description
                  : '',
        }
    ];
  }

  void remove(int row, Map<String, Map<String, dynamic>> edits) {
    if (added.remove(row) != null) {
      edits.removeWhere((cell, _) => rowOf(cell) == row);
    } else {
      deleted.add(row);
    }
  }

  void clear() {
    added.clear();
    deleted.clear();
  }

  List<Map<String, dynamic>> payload(Map<String, Map<String, dynamic>> edits) {
    return [
      for (final entry in edits.entries)
        if (!added.containsKey(rowOf(entry.key)) &&
            !deleted.contains(rowOf(entry.key)))
          entry.value,
      for (final row in deleted)
        {'operation': 'delete-consultoria-row', 'row': row},
      for (final entry in added.entries)
        {
          'operation': 'add-consultoria-row',
          'id': 'new-${entry.key - 1000000}',
          'values': {
            for (final field in entry.value)
              if (const ['B', 'C', 'D', 'E', 'F', 'H']
                  .contains(field['cell'].toString()[0]))
                field['cell'].toString()[0]:
                    edits[field['cell']]?['value'] ?? field['value']
          },
        },
    ];
  }

  String get label {
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add(
          '${added.length} ${added.length == 1 ? 'encontro adicionado' : 'encontros adicionados'}');
    }
    if (deleted.isNotEmpty) {
      parts.add(
          '${deleted.length} ${deleted.length == 1 ? 'exclus\u00e3o pendente' : 'exclus\u00f5es pendentes'}');
    }
    return parts.join(' \u00b7 ');
  }
}
