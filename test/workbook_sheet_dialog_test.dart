import 'dart:async';
import 'package:gerenciador_horas/features/projects/dialogs/project_worksheet_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';

void main() {
  testWidgets('reading a preferred sheet never blocks closing the dialog',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Open'),
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => WorkbookSheetDialog(
                            initialWorksheet: 'Cronogramas',
                            allowed: () => true,
                            call: (args) async =>
                                args['action'] == 'excel-editor-sheets'
                                    ? {
                                        'sheetNames': ['Cronogramas']
                                      }
                                    : pending.future)))))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(pending.isCompleted, isFalse);
    await tester.tap(find.text('Fechar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkbookSheetDialog), findsNothing);
    pending.complete({
      'worksheet': 'Cronogramas',
      'firstRow': 5,
      'firstColumn': 2,
      'fields': []
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('catalog training including combined service chooses Cronogramas only',
      () {
    expect(defaultProjectWorksheet('Treinamento Catalog'), 'Cronogramas');
    expect(defaultProjectWorksheet('Treinamento Catálogo'), 'Cronogramas');
    expect(defaultProjectWorksheet('Treinamento Catalog + Consultoria'),
        'Cronogramas');
    expect(defaultProjectWorksheet('Promob Enterprise'), isNull);
    expect(defaultProjectWorksheet('Professional'), isNull);
  });
  testWidgets(
      'Cronogramas opens directly, remembers selection and edits time and percent',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    final remembered = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
            initialWorksheet: 'Cronogramas',
            allowed: () => true,
            onWorksheetOpened: (name) async {
              remembered.add(name);
            },
            call: (args) async {
              calls.add(args);
              if (args['action'] == 'excel-editor-sheets') {
                return {
                  'sheetNames': ['Cronogramas', 'Dados']
                };
              }
              return {
                'worksheet': args['worksheet'],
                'worksheetTypesVersion': 2,
                'scheduleTable': true,
                'firstRow': args['firstRow'],
                'firstColumn': args['firstColumn'],
                'revision': 'revision',
                if (args['action'] == 'excel-editor-write') 'saved': true,
                'fields': [
                  for (var r = 5; r < 30; r++)
                    for (var c = 2; c < 10; c++)
                      {
                        'sheet': 'Cronogramas',
                        'cell': '${String.fromCharCode(64 + c)}$r',
                        'kind': r == 6 && c == 3
                            ? 'time'
                            : r == 6 && c == 8
                                ? 'number'
                                : 'text',
                        'percent': r == 6 && c == 8,
                        'readOnly': false,
                        'value': r == 6 && c == 9
                            ? 'Consultoria Catalog'
                            : r == 6 && c == 3
                                ? '08:00'
                                : r == 6 && c == 8
                                    ? .99
                                    : '',
                        'display': r == 6 && c == 3
                            ? '08:00'
                            : r == 6 && c == 8
                                ? '99%'
                                : ''
                      }
                ]
              };
            })));
    await tester.pumpAndSettle();
    expect(calls[1]['worksheet'], 'Cronogramas');
    expect(calls[1]['firstRow'], 5);
    expect(calls[1]['firstColumn'], 2);
    expect(remembered, ['Cronogramas']);
    for (final step in [('08:00', '09:15')]) {
      await tester.ensureVisible(find.text(step.$1));
      await tester.tap(find.text(step.$1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), step.$2);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
    }
    final status = find.byKey(const ValueKey('schedule-status-H6'));
    await tester.ensureVisible(status);
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('50%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    final write = calls.singleWhere((c) => c['action'] == 'excel-editor-write');
    expect(write['changes'], [
      {
        'sheet': 'Cronogramas',
        'cell': 'C6',
        'before': '08:00',
        'value': '09:15'
      },
      {'sheet': 'Cronogramas', 'cell': 'H6', 'before': .99, 'value': .5}
    ]);
    expect(tester.takeException(), isNull);
  });

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
