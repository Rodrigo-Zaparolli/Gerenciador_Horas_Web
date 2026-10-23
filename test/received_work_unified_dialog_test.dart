import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'received_work_store_test.dart' show ImportAuth;

void main() {
  for (final width in [390.0, 1400.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'single route lookup and registration at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var queries = 0, writes = 0;
        ProjectModel? saved;
        final receipt = Completer<Map<String, dynamic>>();
        await tester.pumpWidget(MaterialApp(
            theme:
                brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          child: const Text('Abrir'),
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => ReceivedWorkDialog(
                                    importById: true,
                                    auth: ImportAuth(),
                                    loadFormats: () async => [
                                      WorkFormat(
                                          id: 'p',
                                          name: 'Professional',
                                          steps: ['Implantação'])
                                    ],
                                    loadExisting: (_) async => null,
                                    query: (script, data) {
                                      queries++;
                                      expect(script, 'edesk_conferencia.py');
                                      expect(
                                          data['solicitacoes'][0]
                                              ['solicitacao'],
                                          '226144');
                                      return receipt.future;
                                    },
                                    importProject: (project) async {
                                      writes++;
                                      saved = project;
                                      return 1;
                                    },
                                  )),
                        )))));
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Novo trabalho'), findsOneWidget);
        final id = find.byKey(const ValueKey('import-request-id'));
        await tester.enterText(id, '226144');
        await tester.tap(find.text('Buscar no E-Desk'));
        await tester.pump();
        expect(queries, 1);
        expect(writes, 0);
        receipt.complete({
          'rows': [
            {
              'solicitacao': '226144',
              'idTrabalho': '7',
              'values': {
                'name': 'Implantação',
                'estimatedHours': '01:00',
                'client': 'Cliente de teste',
                'requestTitle': 'Professional Produção completa - Cliente',
                'leader': 'Líder'
              }
            }
          ]
        });
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(ReceivedWorkReview), findsOneWidget);
        expect(find.textContaining('Total previsto: 01:00'), findsOneWidget);
        expect(writes, 0);
        await tester.ensureVisible(id);
        await tester.enterText(id, '999');
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Cadastrar no app');
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        expect(find.textContaining('ID alterado.'), findsOneWidget);
        await tester.enterText(id, '226144');
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(saved!.id, '226144');
        expect(saved!.subTasks!.single.edeskWorkNumber, '7');
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
