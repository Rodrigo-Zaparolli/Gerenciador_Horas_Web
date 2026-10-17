import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_reference_upgrade.dart';

String reference(String kind, String path, {String owner = 'owner'}) => Uri(
        scheme: 'desktop-$kind',
        host: 'local',
        pathSegments: [owner, '12345678-1234-1234-1234-123456789abc', path])
    .toString();

void main() {
  test('upgrade only replaces the exact old project field', () {
    const previous =
        'browser-folder://local/owner/12345678-1234-1234-1234-123456789abc/Documentos';
    final resolved = reference('folder', r'C:\Clientes\Orquinare\Documentos');
    final data = <String, dynamic>{
      'folderPath': previous,
      'excelLink': 'unchanged',
      'hours': '10:00'
    };
    final patch = projectReferenceUpgrade(data,
        uid: 'owner',
        field: 'folderPath',
        previous: previous,
        resolved: resolved);
    expect({...data, ...patch!},
        {'folderPath': resolved, 'excelLink': 'unchanged', 'hours': '10:00'});
    expect(data['folderPath'], previous);
  });
  test('a concurrent selection for another same-named folder is preserved', () {
    final first = reference('folder', r'C:\Clientes\Orquinare\Documentos');
    final second = reference('folder', r'C:\Clientes\Sin Moveis\Documentos');
    expect(
        projectReferenceUpgrade({'folderPath': second},
            uid: 'owner',
            field: 'folderPath',
            previous: 'old',
            resolved: first),
        isNull);
  });
  test('spreadsheet paths keep accents and URI delimiters', () {
    final resolved =
        reference('file', r'C:\Clientes\Implantação #1 %\Projeto.xlsx');
    expect(
        projectReferenceUpgrade({'excelLink': 'old'},
            uid: 'owner',
            field: 'excelLink',
            previous: 'old',
            resolved: resolved),
        {'excelLink': resolved});
  });
  test(
      'wrong owner, field, resource type and name-only metadata cannot upgrade',
      () {
    for (final entry in [
      (
        'excelLink',
        reference('file', r'C:\Clientes\Projeto.xlsx', owner: 'other')
      ),
      ('excelLink', reference('folder', r'C:\Clientes\Documentos')),
      ('excelLink', reference('file', 'Projeto.xlsx')),
      ('status', reference('file', r'C:\Clientes\Projeto.xlsx')),
    ]) {
      expect(
          projectReferenceUpgrade({entry.$1: 'old'},
              uid: 'owner',
              field: entry.$1,
              previous: 'old',
              resolved: entry.$2),
          isNull);
    }
  });
  test('UNC folders are retained as complete paths', () {
    final resolved =
        reference('folder', r'\\servidor\Clientes\Orquinare\Documentos');
    expect(
        projectReferenceUpgrade({'folderPath': 'old'},
            uid: 'owner',
            field: 'folderPath',
            previous: 'old',
            resolved: resolved),
        {'folderPath': resolved});
  });
}
