import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('select any sheet, edit and save exact page at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <Map<String, dynamic>>[];
      Map<String, dynamic> page(Map<String, dynamic> args) => {
            'worksheet': args['worksheet'],
            'firstRow': args['firstRow'],
            'firstColumn': args['firstColumn'],
            'revision': 'rev',
            'fields': [
              for (var row = 1; row <= 25; row++)
                for (var col = 0; col < 8; col++)
                  {
                    'sheet': args['worksheet'],
                    'cell': '${String.fromCharCode(65 + col)}$row',
                    'kind': 'text',
                    'value': col == 0 ? 'Original' : '',
                    'display': col == 0 ? 'Original' : '',
                    'readOnly': col == 1,
                  }
            ],
          };
      await tester.pumpWidget(MaterialApp(
          home: WorkbookSheetDialog(
              allowed: () => true,
              call: (args) async {
                calls.add(args);
                if (args['action'] == 'excel-editor-sheets') {
                  return {
                    'sheetNames': ['Entrada', 'Outra guia']
                  };
                }
                return {
                  ...page(args),
                  if (args['action'] == 'excel-editor-write') 'saved': true
                };
              })));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outra guia').last);
      await tester.pumpAndSettle();
      expect(calls.last['worksheet'], 'Outra guia');
      await tester.tap(find.text('Original').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edited');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Edited'), findsOneWidget);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pumpAndSettle();
      final write =
          calls.singleWhere((c) => c['action'] == 'excel-editor-write');
      expect(write['worksheet'], 'Outra guia');
      expect(write['revision'], 'rev');
      expect(write['changes'], [
        {
          'sheet': 'Outra guia',
          'cell': 'A1',
          'before': 'Original',
          'value': 'Edited'
        }
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('old integration response never exposes cells for editing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
            allowed: () => true,
            call: (args) async => args['action'] == 'excel-editor-sheets'
                ? {
                    'sheetNames': ['Entrada']
                  }
                : {'fields': [], 'tasks': []})));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrada').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Atualize a integração'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Salvar na planilha'))
            .onPressed,
        isNull);
  });
}
