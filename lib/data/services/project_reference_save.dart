/// Explicit edits are compared with the values originally shown in the form.
class ProjectReferenceChanges {
  const ProjectReferenceChanges({
    required this.previousFolder,
    required this.previousExcel,
  });
  final String? previousFolder, previousExcel;
}

Map<String, dynamic> projectReferenceSave(
  Map<String, dynamic> incoming,
  Map<String, dynamic>? latest, {
  ProjectReferenceChanges? changes,
}) {
  final result = Map<String, dynamic>.from(incoming);
  if (latest == null) return result;
  final previous = {
    'folderPath': changes?.previousFolder,
    'excelLink': changes?.previousExcel,
  };
  for (final field in previous.keys) {
    final selected = incoming[field];
    final before = previous[field];
    final current = latest[field]?.toString();
    if (changes == null || selected == before) {
      // A status/task save, or an untouched editor field, must not restore a
      // stale reference after migration, folder move or another editor save.
      result[field] = current;
    } else {
      if (current != before && current != selected) {
        throw StateError('A pasta ou planilha foi alterada em outra tela. '
            'Reabra o editor para carregar o caminho atual antes de alterar o vínculo.');
      }
      result[field] = selected;
    }
  }
  return result;
}
