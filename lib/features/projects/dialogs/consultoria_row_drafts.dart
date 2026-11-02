class ConsultoriaRowDrafts {
  final Map<int, List<Map<String, dynamic>>> added = {};
  final Set<int> deleted = {};
  final Map<int, int?> after = {};
  int _next = 1000000;
  Map<String, dynamic> toJson() => {
        'next': _next,
        'added': {
          for (final entry in added.entries) '${entry.key}': entry.value
        },
        'deleted': deleted.toList(),
        'after': {
          for (final entry in after.entries) '${entry.key}': entry.value
        },
      };

  bool restore(dynamic raw) {
    if (raw is! Map ||
        raw['added'] is! Map ||
        raw['deleted'] is! List ||
        raw['after'] is! Map) {
      return false;
    }
    try {
      final restored = <int, List<Map<String, dynamic>>>{};
      final parents = <int, int?>{};
      final removed = (raw['deleted'] as List).map((v) => v as int).toSet();
      if ((raw['added'] as Map).length > 200 ||
          removed.length > 500 ||
          removed.any((r) => r < 1 || r >= 1000000)) {
        return false;
      }
      for (final entry in (raw['added'] as Map).entries) {
        final row = int.parse(entry.key as String);
        if (row <= 1000000 || row > 1001000 || entry.value is! List) {
          return false;
        }
        final fields = (entry.value as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        if (fields.length != 8 ||
            fields.map((f) => f['cell']).toSet().length != 8 ||
            fields
                .any((f) => !RegExp('^[B-I]$row\$').hasMatch('${f['cell']}'))) {
          return false;
        }
        for (final field in fields) {
          final column = '${field['cell']}'[0];
          final kind = column == 'B'
              ? 'date'
              : const ['C', 'D', 'E', 'F'].contains(column)
                  ? 'time'
                  : 'text';
          if (field['kind'] != kind ||
              field['readOnly'] != (column == 'G' || column == 'I')) {
            return false;
          }
        }
        restored[row] = fields;
        final parent = raw['after']['$row'];
        if (parent != null && parent is! int) return false;
        parents[row] = parent as int?;
      }
      for (final row in restored.keys) {
        final seen = <int>{row};
        var parent = parents[row];
        while (parent != null && parent > 1000000) {
          if (!restored.containsKey(parent) || !seen.add(parent)) return false;
          parent = parents[parent];
        }
        if (parent != null && (parent < 1 || removed.contains(parent))) {
          return false;
        }
      }
      clear();
      added.addAll(restored);
      deleted.addAll(removed);
      after.addAll(parents);
      _next = restored.keys.fold(1000000, (a, b) => a > b ? a : b);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get dirty => added.isNotEmpty || deleted.isNotEmpty;
  int get count => added.length + deleted.length;
  static int? rowOf(String cell) =>
      int.tryParse(cell.replaceAll(RegExp('[A-Z]'), ''));
  void add(String sheet, String description, {int? below}) {
    final row = ++_next;
    after[row] = below;
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
      for (final child in after.keys.toList()) {
        if (after[child] == row) after[child] = after[row];
      }
      after.remove(row);
      edits.removeWhere((cell, _) => rowOf(cell) == row);
    } else {
      deleted.add(row);
    }
  }

  void clear() {
    added.clear();
    after.clear();
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
          if (after[entry.key] != null)
            'after': after[entry.key]! >= 1000001
                ? 'new-${after[entry.key]! - 1000000}'
                : after[entry.key],
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

  List<Map<String, dynamic>> orderedFields(
      List<Map<String, dynamic>> original) {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final field in original) {
      (grouped[rowOf(field['cell'])!] ??= []).add(field);
    }
    final result = <Map<String, dynamic>>[];
    void append(int row, List<Map<String, dynamic>> fields) {
      result.addAll(fields);
      for (final child
          in added.keys.where((r) => after[r] == row).toList().reversed) {
        append(child, added[child]!);
      }
    }

    for (final entry in grouped.entries) {
      append(entry.key, entry.value);
    }
    for (final row in added.keys.where((r) => after[r] == null)) {
      append(row, added[row]!);
    }
    return result;
  }

  String get label {
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add(
          '${added.length} ${added.length == 1 ? 'linha adicionada' : 'linhas adicionadas'}');
    }
    if (deleted.isNotEmpty) {
      parts.add(
          '${deleted.length} ${deleted.length == 1 ? 'exclus\u00e3o pendente' : 'exclus\u00f5es pendentes'}');
    }
    return parts.join(' \u00b7 ');
  }
}
