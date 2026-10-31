import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'project_spreadsheet_dialog_test.dart' show snapshot;

void main() {
  for (final confirm in [true, false]) {
    testWidgets('Excel save status reflects actual confirmation: $confirm',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final write = Completer<Map<String, dynamic>>();
      var writes = 0;
      await tester.pumpWidget(MaterialApp(
          home: ProjectSpreadsheetDialog(
        project: ProjectModel.fromJson({
          'id': '2265001',
          'client': 'Cliente correto',
          'serviceType': 'Enterprise'
        }),
        uidProvider: () => 'owner',
        emailProvider: () => 'rodrigozaparolli79@gmail.com',
        contactsLoader: () async => [],
        transport: (args) async {
          if (args['action'] == 'excel-editor-write') {
            writes++;
            return write.future;
          }
          if (args['action'] == 'excel-editor-preview')
            return {
              'preview': true,
              'checklistSheet': 'Checklist-Processo',
              'statusPreview': {'rows': []}
            };
          return snapshot();
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('Arquivo: Projeto.xlsm'), findsOneWidget);
      expect(find.text('2265001 · Cliente correto'), findsOneWidget);
      expect(find.text('Salvo no Excel'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'Alterado');
      await tester.pumpAndSettle();
      expect(find.text('1 altera\u00e7\u00e3o pendente'), findsOneWidget);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Gravando no Excel...'), findsOneWidget);
      expect(find.text('Salvo no Excel'), findsNothing);
      write.complete({
        ...snapshot(),
        'saved': confirm,
        'revision': 'v2',
        'backup': 'backup.xlsm'
      });
      await tester.pumpAndSettle();
      expect(
          find.text(confirm
              ? 'Salvo no Excel'
              : 'Grava\u00e7\u00e3o n\u00e3o confirmada'),
          findsOneWidget);
      expect(writes, 1);
      if (!confirm) {
        expect(
            tester
                .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Salvar na planilha'))
                .onPressed,
            isNotNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
