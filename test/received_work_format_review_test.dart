import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'received_work_store_test.dart' show ImportAuth;

void main() {
  for (final width in [390.0, 1400.0]) {
    testWidgets('uses configured stages and real nonsequential IDs at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ProjectModel? saved;
      final formats = [
        WorkFormat(id: 'p', name: 'Professional', steps: [
          'Contato Inicial',
          {'name': 'Implantação'},
          'Etapa opcional ausente',
        ])
      ];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        child: const Text('Abrir'),
                        onPressed: () => showDialog<int>(
                            context: context,
                            builder: (_) => ReceivedWorkReview(
                                  auth: ImportAuth(),
                                  summary: const {
                                    'solicitacao': '226144',
                                    'client': 'Cliente',
                                    'leader': 'Líder',
                                    'serviceType': 'Promob Professional'
                                  },
                                  types: const ['Professional'],
                                  formats: formats,
                                  details: const [
                                    {
                                      'idTrabalho': '7',
                                      'values': {
                                        'name': 'Implantacao (OH)',
                                        'estimatedHours': '02:30',
                                        'start': '22/10/2026',
                                        'end': '23/10/2026'
                                      }
                                    },
                                    {
                                      'idTrabalho': '3',
                                      'values': {
                                        'name': 'Contato Inicial',
                                        'estimatedHours': '01:00'
                                      }
                                    },
                                  ],
                                  importProject: (project) async {
                                    saved = project;
                                    return 2;
                                  },
                                )),
                      )))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 de 3 etapas vinculadas'), findsOneWidget);
      expect(find.textContaining('Total previsto: 03:30'), findsOneWidget);
      await tester.tap(find.text('Cadastrar no app'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.subTasks!.map((s) => s.stage),
          ['Contato Inicial', 'Implantação']);
      expect(saved!.subTasks!.map((s) => s.edeskWorkNumber), ['3', '7']);
      expect(saved!.estimatedHours, '03:30');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unmatched stages block save and never inherit IDs by position',
      (tester) async {
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      child: const Text('Abrir'),
                      onPressed: () => showDialog<int>(
                          context: context,
                          builder: (_) => ReceivedWorkReview(
                                auth: ImportAuth(),
                                summary: const {
                                  'solicitacao': '226144',
                                  'client': 'Cliente',
                                  'leader': 'Líder',
                                  'serviceType': 'Professional'
                                },
                                types: const ['Professional'],
                                formats: [
                                  WorkFormat(
                                      id: 'p',
                                      name: 'Professional',
                                      steps: ['Implantação'])
                                ],
                                details: const [
                                  {
                                    'idTrabalho': '9',
                                    'values': {
                                      'name': 'Outro trabalho',
                                      'estimatedHours': '08:00'
                                    }
                                  }
                                ],
                                importProject: (_) async {
                                  writes++;
                                  return 1;
                                },
                              )),
                    )))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar no app'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(
        find.textContaining(
            'Selecione o trabalho real do E-Desk para Implantação.'),
        findsOneWidget);
    final dropdown = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<String> &&
        w.key == const ValueKey('mapping-Implantação-'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 · Outro trabalho').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar no app'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing legacy service permits choosing a stage template',
      (tester) async {
    ProjectModel? saved;
    final existing = ProjectModel(
        id: '226144',
        id2: '',
        client: 'Cliente',
        serviceType: 'Tipo antigo',
        leader: 'Equipe',
        stage: '',
        task: '',
        status: 'INI_PRO',
        startDate: DateTime(2026, 10, 23),
        estimatedHours: '00:00',
        hourType: 'Hs Cobradas');
    await tester.pumpWidget(MaterialApp(
        home: ReceivedWorkReview(
      auth: ImportAuth(),
      existing: existing,
      summary: const {'solicitacao': '226144'},
      types: const ['Professional'],
      formats: [
        WorkFormat(id: 'p', name: 'Professional', steps: ['Implantacao'])
      ],
      details: const [
        {
          'idTrabalho': '7',
          'values': {'name': 'Implantacao', 'estimatedHours': '02:00'}
        }
      ],
      importProject: (project) async {
        saved = project;
        return 1;
      },
      onCompleted: (_) {},
    )));
    await tester.pumpAndSettle();
    final type = find.byKey(const ValueKey('import-service-type'));
    expect(tester.widget<DropdownButtonFormField<WorkFormat>>(type).onChanged,
        isNotNull);
    await tester.ensureVisible(type);
    await tester.tap(type);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professional').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar no app'));
    await tester.pumpAndSettle();
    expect(saved?.subTasks?.single.edeskWorkNumber, '7');
    expect(tester.takeException(), isNull);
  });
}
