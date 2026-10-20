import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_status_update.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  for (final accepted in [true, false]) {
    test(
        'Table finalization persists once then offers archive, result $accepted',
        () async {
      final project =
          ProjectModel.fromJson({'id': '226144', 'status': 'TRAB_INI'});
      final calls = <String>[];
      final moved = await updateProjectStatus(
          project: project,
          status: 'TRAB_FIM',
          registerLogs: () async {
            calls.add('logs');
          },
          persist: () async {
            expect(project.status, 'TRAB_FIM');
            calls.add('save');
          },
          offerArchive: () async {
            calls.add('archive');
            return accepted;
          });
      expect(calls, ['logs', 'save', 'archive']);
      expect(moved, accepted);
      expect(project.status, 'TRAB_FIM');
    });
  }
  test('Failed finalization restores local status and never opens archive',
      () async {
    final project =
        ProjectModel.fromJson({'id': '226144', 'status': 'TRAB_INI'});
    var opened = false;
    await expectLater(
        updateProjectStatus(
            project: project,
            status: 'TRAB_FIM',
            registerLogs: () async {},
            persist: () async => throw StateError('offline'),
            offerArchive: () async {
              opened = true;
              return true;
            }),
        throwsStateError);
    expect(opened, isFalse);
    expect(project.status, 'TRAB_INI');
  });
  test('Changing a normal status never starts archive or completion logs',
      () async {
    final calls = <String>[];
    final project =
        ProjectModel.fromJson({'id': '226144', 'status': 'TRAB_INI'});
    await updateProjectStatus(
        project: project,
        status: 'TRAB_STOP',
        registerLogs: () async {
          calls.add('logs');
        },
        persist: () async {
          calls.add('save');
        },
        offerArchive: () async {
          calls.add('archive');
          return true;
        });
    expect(calls, ['save']);
    expect(project.status, 'TRAB_STOP');
  });
  test('Archive failure does not undo a confirmed finalization or save twice',
      () async {
    final project =
        ProjectModel.fromJson({'id': '226144', 'status': 'TRAB_INI'});
    var saves = 0;
    await expectLater(
        updateProjectStatus(
            project: project,
            status: 'TRAB_FIM',
            registerLogs: () async {},
            persist: () async {
              saves++;
            },
            offerArchive: () async => throw StateError('dialog failed')),
        throwsStateError);
    expect(saves, 1);
    expect(project.status, 'TRAB_FIM');
  });
}
