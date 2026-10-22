import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'received_work_store_test.dart' show ImportAuth;

void main() {
  for (final width in [390.0, 1300.0]) {
    testWidgets(
        'Import by ID reviews real work numbers before any write at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var queries = 0;
      ProjectModel? saved;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReceivedWorkDialog(
        importById: true,
        auth: ImportAuth(),
        query: (script, data) async {
          queries++;
          expect(script, 'edesk_conferencia.py');
          expect(data['solicitacoes'], [
            {'solicitacao': '2265173', 'trabalhos': <String>[]}
          ]);
          return {
            'rows': [
              for (final id in ['3', '6'])
                {
                  'solicitacao': '2265173',
                  'idTrabalho': id,
                  'values': {
                    'client': 'Cliente',
                    'leader': 'Lider',
                    'serviceType': 'Enterprise',
                    'name': 'Etapa $id',
                    'estimatedHours': '02:30'
                  }
                }
            ]
          };
        },
        loadTypes: () async => ['Enterprise'],
        loadExisting: (request) async {
          expect(request, '2265173');
          return null;
        },
        importProject: (project) async {
          saved = project;
          return project.subTasks!.length;
        },
      ))));
      await tester.pumpAndSettle();
      expect(queries, 0);
      await tester.tap(find.text('Buscar no E-Desk'));
      await tester.pumpAndSettle();
      expect(queries, 0);
      await tester.enterText(find.byType(TextField), '2265173/3');
      await tester.tap(find.text('Buscar no E-Desk'));
      await tester.pumpAndSettle();
      expect(queries, 0);
      await tester.enterText(find.byType(TextField), ' 2265173 ');
      await tester.tap(find.text('Buscar no E-Desk'));
      await tester.pumpAndSettle();
      expect(queries, 1);
      expect(find.byType(ReceivedWorkReview), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('Cadastrar no app'));
      await tester.pumpAndSettle();
      expect(saved!.id, '2265173');
      expect(saved!.subTasks!.map((t) => t.edeskWorkNumber), ['3', '6']);
      expect(saved!.estimatedHours, '05:00');
      expect(
          find.text(
              '2 trabalho(s) cadastrados no app. Nenhuma alteração foi feita no E-Desk.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final mode in ['empty', 'other', 'failed']) {
    testWidgets('Import by ID never offers registration for $mode query',
        (tester) async {
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReceivedWorkDialog(
        importById: true,
        auth: ImportAuth(),
        query: (_, data) async {
          if (mode == 'failed') throw StateError('Integração indisponível');
          return {
            'rows': mode == 'empty'
                ? []
                : [
                    {'solicitacao': '999', 'idTrabalho': '3', 'values': {}}
                  ]
          };
        },
        loadTypes: () async => ['Enterprise'],
        loadExisting: (_) async => null,
        importProject: (_) async {
          saves++;
          return 1;
        },
      ))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2265173');
      await tester.tap(find.text('Buscar no E-Desk'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceivedWorkReview), findsNothing);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
