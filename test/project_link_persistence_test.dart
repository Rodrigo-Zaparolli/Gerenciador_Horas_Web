import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'received_work_store_test.dart' show ImportAuth, ImportDatabase;

String durable(String kind, String path) => Uri(
        scheme: 'desktop-$kind',
        host: 'local',
        pathSegments: ['owner', '12345678-1234-1234-1234-123456789abc', path])
    .toString();

void main() {
  test(
      'Moving a legacy completed project updates both links and preserves its snapshot',
      () async {
    final db = ImportDatabase();
    final service = FirebaseService(database: db, auth: ImportAuth());
    const record = 'users/owner/completed_projects/legacy';
    const cache = 'users/owner/projects/226144/spreadsheet/snapshot';
    db.documents[record] = {
      'id': '226144',
      'status': 'TRAB_FIM',
      'folderPath': 'old-folder',
      'excelLink': 'old-excel'
    };
    db.documents[cache] = {'reference': 'old-excel', 'payload': 'unchanged'};
    await service.applyProjectFolderMove('226144', {
      'moved': true,
      'operation': 'move-test',
      'source': 'old-location',
      'target': 'new-location',
      'oldFolderReference': 'old-folder',
      'folderReference': 'new-folder',
      'oldExcelReference': 'old-excel',
      'excelReference': 'new-excel',
    });
    expect(db.documents[record], {
      'id': '226144',
      'status': 'TRAB_FIM',
      'folderPath': 'new-folder',
      'excelLink': 'new-excel'
    });
    expect(db.documents[cache],
        {'reference': 'new-excel', 'payload': 'unchanged'});
    expect(db.documents.containsKey('users/owner/completed_projects/226144'),
        false);
  });
  for (final collection in ['projects', 'completed_projects']) {
    test(
        'Link upgrade updates the real legacy $collection record and preserves the workbook cache',
        () async {
      final db = ImportDatabase();
      final auth = ImportAuth();
      final service = FirebaseService(database: db, auth: auth);
      final path = 'users/owner/$collection/legacy-document';
      final cache = 'users/owner/projects/226144/spreadsheet/snapshot';
      const old = r'C:\Clientes\Orquinare\Projeto.xlsm';
      final resolved = durable('file', old);
      db.documents[path] = {
        'id': '226144',
        'excelLink': old,
        'folderPath': 'keep-folder',
        'hours': '08:00'
      };
      db.documents[cache] = {
        'reference': old,
        'schema': 1,
        'payload': 'unchanged'
      };
      await service.upgradeProjectLocalReference('226144',
          field: 'excelLink', previous: old, resolved: resolved);
      expect(db.documents[path]!['excelLink'], resolved);
      expect(db.documents[path]!['folderPath'], 'keep-folder');
      expect(db.documents[path]!['hours'], '08:00');
      expect(db.documents[cache],
          {'reference': resolved, 'schema': 1, 'payload': 'unchanged'});
      expect(db.documents.containsKey('users/owner/$collection/226144'), false);
      await service.upgradeProjectLocalReference('226144',
          field: 'excelLink', previous: old, resolved: resolved);
      expect(db.documents, hasLength(2));
    });
  }
  test('A concurrent link change is preserved and cannot be reported as saved',
      () async {
    final db = ImportDatabase();
    final service = FirebaseService(database: db, auth: ImportAuth());
    const path = 'users/owner/projects/226144';
    db.documents[path] = {'id': '226144', 'folderPath': 'old'};
    db.beforeTransaction =
        () => db.documents[path]!['folderPath'] = 'changed elsewhere';
    await expectLater(
        service.upgradeProjectLocalReference('226144',
            field: 'folderPath',
            previous: 'old',
            resolved: durable('folder', r'C:\Clientes\Orquinare\Documentos')),
        throwsStateError);
    expect(db.documents[path]!['folderPath'], 'changed elsewhere');
  });
  test('Account change or duplicate IDs never changes another project link',
      () async {
    for (final duplicate in [false, true]) {
      final db = ImportDatabase();
      final auth = ImportAuth();
      final service = FirebaseService(database: db, auth: auth);
      db.documents['users/owner/projects/legacy'] = {
        'id': '226144',
        'folderPath': 'old'
      };
      if (duplicate) {
        db.documents['users/owner/projects/duplicate'] = {
          'id': '226144',
          'folderPath': 'another'
        };
      } else {
        db.beforeTransaction = () => auth.user = null;
      }
      await expectLater(
          service.upgradeProjectLocalReference('226144',
              field: 'folderPath',
              previous: 'old',
              resolved: durable('folder', r'C:\Clientes\Orquinare\Documentos')),
          throwsStateError);
      expect(db.documents['users/owner/projects/legacy']!['folderPath'], 'old');
    }
  });
}
