String projectChecklistSheet(String serviceType) {
  final value = serviceType.trim().toLowerCase();
  return value.contains('professional') || value.contains('profissional')
      ? 'Maker CheckList-Processo'
      : 'Checklist-Processo';
}

bool spreadsheetMatchesProject(Map<String, dynamic> data, String serviceType) {
  final expected = projectChecklistSheet(serviceType).toLowerCase();
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
