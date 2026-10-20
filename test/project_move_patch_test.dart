import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_move_patch.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_archive_dialog.dart';

void main() {
  test('Folder movement is offered for local Windows links, not web links', () {
    for (final path in [
      r'C:\Clientes\Projeto',
      r'\\servidor\Clientes\Projeto',
      'desktop-folder://local/ref',
      'browser-folder://local/ref'
    ]) {
      expect(ProjectArchiveDialog.acceptsFolder(path), isTrue);
    }
    for (final path in [
      '',
      'https://company.sharepoint.com/folder',
      'gs://bucket/file'
    ]) {
      expect(ProjectArchiveDialog.acceptsFolder(path), isFalse);
    }
  });
  final move = {
    'moved': true,
    'oldFolderReference': 'old-folder',
    'folderReference': 'new-folder',
    'oldExcelReference': 'old-excel',
    'excelReference': 'new-excel'
  };
  test('Updates both links and accepts recovery of the same confirmed move',
      () {
    final first = projectMovePatch(
        {'folderPath': 'old-folder', 'excelLink': 'old-excel'}, move);
    expect(first, {'folderPath': 'new-folder', 'excelLink': 'new-excel'});
    expect(projectMovePatch(first, move), first);
  });
  test('Never overwrites links edited elsewhere or an unconfirmed move', () {
    expect(
        () => projectMovePatch(
            {'folderPath': 'another-project', 'excelLink': 'old-excel'}, move),
        throwsStateError);
    expect(
        () => projectMovePatch(
            {'folderPath': 'old-folder', 'excelLink': 'edited'}, move),
        throwsStateError);
    expect(() => projectMovePatch({}, {...move, 'moved': false}),
        throwsStateError);
  });
}
