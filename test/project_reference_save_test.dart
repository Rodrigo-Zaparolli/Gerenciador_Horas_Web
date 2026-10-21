import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_reference_save.dart';

void main() {
  const original = {'folderPath': 'old folder', 'excelLink': 'old excel'};
  const latest = {'folderPath': 'new folder', 'excelLink': 'new excel'};
  const unchanged = ProjectReferenceChanges(
      previousFolder: 'old folder', previousExcel: 'old excel');
  test('status and task updates cannot restore stale or empty file references',
      () {
    for (final fields in [
      original,
      {'folderPath': null, 'excelLink': null}
    ]) {
      final saved = projectReferenceSave({
        ...fields,
        'status': 'TRAB',
        'subTasks': ['updated']
      }, latest);
      expect(saved['folderPath'], 'new folder');
      expect(saved['excelLink'], 'new excel');
      expect(saved['status'], 'TRAB');
      expect(saved['subTasks'], ['updated']);
    }
  });
  test('untouched editor fields retain newer migrated or moved references', () {
    expect(projectReferenceSave(original, latest, changes: unchanged), latest);
  });
  test('explicit folder edit preserves a concurrent spreadsheet update', () {
    final saved = projectReferenceSave({
      'folderPath': 'selected folder',
      'excelLink': 'old excel'
    }, {
      'folderPath': 'old folder',
      'excelLink': 'new excel'
    }, changes: unchanged);
    expect(saved, {'folderPath': 'selected folder', 'excelLink': 'new excel'});
  });
  test('explicit removal is retained and normal saves cannot restore it', () {
    final removed = projectReferenceSave(
        {'folderPath': null, 'excelLink': 'old excel'}, original,
        changes: unchanged);
    expect(removed['folderPath'], isNull);
    expect(projectReferenceSave(original, removed)['folderPath'], isNull);
  });
  test('conflicting explicit edits fail instead of overwriting another path',
      () {
    expect(
        () => projectReferenceSave(
            {'folderPath': 'selected folder', 'excelLink': 'old excel'}, latest,
            changes: unchanged),
        throwsStateError);
    expect(latest['folderPath'], 'new folder');
  });
  test('idempotent retry accepts a selection already persisted', () {
    expect(projectReferenceSave(latest, latest, changes: unchanged), latest);
  });
  test(
      'new project retains selected paths and finalization retains latest paths',
      () {
    expect(projectReferenceSave(latest, null), latest);
    final completed =
        projectReferenceSave({...original, 'status': 'TRAB_FIM'}, latest);
    expect(completed, {...latest, 'status': 'TRAB_FIM'});
  });
}
