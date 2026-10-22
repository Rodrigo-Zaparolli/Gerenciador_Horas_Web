import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/received_work.dart';

void main() {
  final date = DateTime(2026, 10, 22);
  final steps = [
    {
      'id': '3',
      'name': 'Implantação Plugin',
      'hours': '08:30',
      'start': '01/10/2026',
      'end': '31/02/2026'
    }
  ];
  build() => receivedProject(
      request: '226144',
      client: 'Cliente',
      type: 'Professional',
      leader: 'Líder',
      receivedAt: date,
      hourType: 'Hs Cobradas',
      steps: steps);
  test(
      'legacy E-Desk IDs remain unique and unallocated existing hours are not counted twice',
      () {
    final incoming = build();
    expect(
        planReceivedImport(incoming, {
          'estimatedHours': '08:30',
          'subTasks': [
            {'subId': 'legacy-key', 'edeskIdTrabalho': '3'}
          ]
        }, {}).added,
        0);
    expect(
        () => planReceivedImport(
            incoming, {'estimatedHours': '08:30', 'subTasks': []}, {}),
        throwsFormatException);
  });
  test(
      'received project preserves the exact work number and computes planned hours without inventing dates',
      () {
    final p = build();
    expect(p.id, '226144');
    expect(p.subTasks!.single.edeskWorkNumber, '3');
    expect(p.subTasks!.single.planStart, DateTime(2026, 10, 1));
    expect(p.subTasks!.single.planEnd, isNull);
    expect(p.estimatedHours, '08:30');
    expect(p.startDate, date);
    expect(p.leader, 'Líder');
  });
  test('missing and malformed data are rejected before creating anything', () {
    for (final hours in ['', '08:99', '8.5', '-01:00']) {
      expect(() => receivedMinutes(hours), throwsFormatException);
    }
    expect(
        () => receivedProject(
            request: '226144',
            client: 'Cliente',
            type: 'Professional',
            leader: '',
            receivedAt: date,
            hourType: 'Hs Cobradas',
            steps: steps),
        throwsFormatException);
    expect(
        () => receivedProject(
            request: '226144',
            client: 'Cliente',
            type: 'Professional',
            leader: 'Líder',
            receivedAt: date,
            hourType: 'Hs Cobradas',
            steps: [...steps, ...steps]),
        throwsFormatException);
  });
  test(
      'retrying an import never duplicates a task or changes existing metadata',
      () {
    final p = build();
    final first = planReceivedImport(p, null, {});
    expect(first.added, 1);
    final current = {
      ...first.patch,
      'client': 'Nome editado',
      'leader': 'Outro líder',
      'folderPath': 'C:/Clientes/Cliente',
      'workedHours': '02:00'
    };
    final repeat = planReceivedImport(p, current, {});
    expect(repeat.added, 0);
    expect(repeat.patch, isEmpty);
    expect(planReceivedImport(p, null, {'226144/3'}).added, 0);
    final other = receivedProject(
        request: '226144',
        client: 'Novo nome',
        type: 'Outro tipo',
        leader: 'Outro',
        receivedAt: date,
        hourType: 'Hs Cobradas',
        steps: [
          {'id': '6', 'name': 'Pós-implantação', 'hours': '02:00'}
        ]);
    final append = planReceivedImport(other, current, {});
    expect(append.added, 1);
    expect(append.patch['estimatedHours'], '10:30');
    expect(append.patch.containsKey('leader'), false);
    expect(append.patch.containsKey('folderPath'), false);
    expect(append.patch.containsKey('workedHours'), false);
    expect((append.patch['subTasks'] as List).first,
        (current['subTasks'] as List).first);
    expect(current['client'], 'Nome editado');
    final retried =
        planReceivedImport(other, {...current, ...append.patch}, {'226144/6'});
    expect(retried.added, 0);
  });
  test('work number collision with another request is rejected', () {
    expect(
        () => planReceivedImport(build(), {
              'estimatedHours': '01:00',
              'subTasks': [
                {'subId': '3', 'edeskSolicitacao': '999'}
              ]
            }, {}),
        throwsFormatException);
  });
}
