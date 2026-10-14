import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gerenciador_horas/data/services/project_update_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/atualizacoes_pendentes_modal.dart';

ProjectModel project(String id, {String status = 'TRAB'}) => ProjectModel(
    id: id,
    id2: '',
    client: 'Cliente $id',
    serviceType: 'Consultoria',
    stage: '',
    task: '',
    status: status,
    startDate: DateTime(2026, 1, 1),
    estimatedHours: '08:00',
    leader: 'Lider',
    hourType: 'Hs Cobradas');

class FixtureService extends ProjectUpdateService {
  FixtureService(this.comments) : super('test-owner');
  final Map<String, ProjectCommentUpdate?> comments;
  final readIds = <String>[];
  @override
  Future<ProjectCommentUpdate?> lastComment(String projectId) async {
    readIds.add(projectId);
    return comments[projectId];
  }
}

void main() {
  test('Dias corridos: zero no dia do comentario, aviso exatamente no dia 14',
      () {
    final date = DateTime(2026, 9, 26, 23, 59);
    expect(ProjectUpdateService.daysSince(date, DateTime(2026, 9, 26)), 0);
    expect(ProjectUpdateService.daysSince(date, DateTime(2026, 9, 27)), 1);
    expect(ProjectUpdateService.isDue(date, DateTime(2026, 10, 9, 23, 59)),
        isFalse);
    expect(ProjectUpdateService.isDue(date, DateTime(2026, 10, 10)), isTrue);
    expect(ProjectUpdateService.nextUpdate(date), DateTime(2026, 10, 10));
    expect(ProjectUpdateService.nextUpdate(DateTime(2026, 12, 25)),
        DateTime(2027, 1, 8));
    expect(
        ProjectUpdateService.daysSince(
            DateTime(2026, 10, 11), DateTime(2026, 10, 10)),
        0);
  });

  test('Somente enviados: data do envio prevalece sobre criacao do rascunho',
      () {
    final latest = ProjectUpdateService.latestSent([
      {'id': 'draft', 'status': 'Pendente', 'dataHora': DateTime(2026, 10, 12)},
      {'id': 'test', 'status': 'Teste', 'dataHora': DateTime(2026, 10, 12)},
      {'id': 'error', 'status': 'Erro', 'enviadoEm': DateTime(2026, 10, 12)},
      {'id': 'old', 'status': 'Enviado', 'criadoEm': DateTime(2026, 9, 1)},
      {
        'id': 'sent',
        'status': 'Enviado',
        'dataHora': DateTime(2026, 9, 1),
        'enviadoEm': Timestamp.fromDate(DateTime(2026, 10, 10, 12)),
        'comentario': 'Novo'
      },
    ]);
    expect(latest!.id, 'sent');
    expect(latest.date, DateTime(2026, 10, 10, 12));
    expect(
        ProjectUpdateService.nextUpdate(latest.date), DateTime(2026, 10, 24));
    expect(
        ProjectUpdateService.latestSent([
          {'status': 'Teste', 'dataHora': DateTime.now()}
        ]),
        isNull);
    expect(
        ProjectUpdateService.latestSent([
          {'status': 'Enviado', 'dataHora': '09/10/2026'}
        ])!
            .date,
        DateTime(2026, 10, 9));
  });

  test(
      'Pendencias incluem hoje e atrasados, excluem finalizados e sem comentario',
      () async {
    final service = FixtureService({
      'today': ProjectCommentUpdate('1', DateTime(2026, 9, 26), 'Hoje'),
      'late': ProjectCommentUpdate('2', DateTime(2026, 9, 24), 'Atrasado'),
      'recent': ProjectCommentUpdate('3', DateTime(2026, 10, 9), 'Novo'),
      'done': ProjectCommentUpdate('4', DateTime(2026, 1, 1), 'Finalizado'),
    });
    final pending = await service.pending([
      project('today'),
      project('late'),
      project('recent'),
      project('empty'),
      project('done', status: 'TRAB_FIM'),
    ], DateTime(2026, 10, 10));
    expect(pending.map((row) => row.project.id), ['late', 'today']);
    expect(pending.map((row) => row.overdueDays), [2, 0]);
    expect(service.readIds, isNot(contains('done')));
    // A new confirmed send resets the obligation.
    service.comments['late'] =
        ProjectCommentUpdate('5', DateTime(2026, 10, 10), 'Atualizado');
    expect((await service.pending([project('late')], DateTime(2026, 10, 10))),
        isEmpty);
  });

  for (final size in [const Size(1200, 800), const Size(390, 700)]) {
    testWidgets('Popup sem overflow, comentar e reabrir em $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = [
        PendingProjectUpdate(
            project('2265173'),
            ProjectCommentUpdate('c1', DateTime(2026, 9, 26), 'Enviado'),
            DateTime(2026, 10, 10))
      ];
      String? action;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async {
                        action = await AtualizacoesPendentesModal.show(
                            context, pending);
                      },
                      child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Vence hoje'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Comentar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comentar'));
      await tester.pumpAndSettle();
      expect(action, '2265173');
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Atualizações pendentes'), findsOneWidget);
      await tester.tap(find.text('Ver solicitações'));
      await tester.pumpAndSettle();
      expect(action, AtualizacoesPendentesModal.requestsAction);
      expect(tester.takeException(), isNull);
    });
  }
}
