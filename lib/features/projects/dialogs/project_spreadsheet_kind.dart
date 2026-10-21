String projectChecklistSheet(String serviceType, {String? override}) {
  if (override != null) return override;
  final value = serviceType.trim().toLowerCase();
  return value.contains('professional') || value.contains('profissional')
      ? 'Maker CheckList-Processo'
      : 'Checklist-Processo';
}

bool spreadsheetMatchesProject(Map<String, dynamic> data, String serviceType,
    {String? checklistSheet, String? entrySheet}) {
  final actualEntry = data['entrySheet'];
  if (actualEntry is String &&
      actualEntry.toLowerCase() !=
          (entrySheet ?? 'Informações de entrada').toLowerCase()) return false;
  if (entrySheet != null &&
      data['entrySheet']?.toString().toLowerCase() != entrySheet.toLowerCase())
    return false;
  final expected = projectChecklistSheet(serviceType, override: checklistSheet)
      .toLowerCase();
  final declared = data['checklistSheet'];
  if (declared is String) return declared.toLowerCase() == expected;
  final sheets = (data['tasks'] as List? ?? [])
      .whereType<Map>()
      .map((t) => t['sheet']?.toString().toLowerCase())
      .whereType<String>()
      .toSet();
  if (sheets.isNotEmpty) return sheets.every((sheet) => sheet == expected);
  // Older snapshots without tasks belonged to the original Enterprise editor.
  return expected == 'checklist-processo';
}
