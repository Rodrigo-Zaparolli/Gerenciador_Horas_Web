import 'project_spreadsheet_dialog_test.dart' show snapshot;
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/cronograma_table.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_worksheet_preference.dart';

List<Map<String, dynamic>> consultationFields() {
  const hours = {
    7: ['14:30', '15:40'],
    8: ['15:00', '15:30'],
    9: ['15:00', '15:20'],
    10: ['13:30', '17:30'],
    11: ['13:30', '17:30'],
    14: ['13:30', '15:20'],
    15: ['13:30', '17:00'],
    16: ['13:30', '17:10']
  };
  return [
    for (var r = 6; r <= 19; r++)
      for (final col in ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'])
        {
          'sheet': 'Consultorias',
          'cell': '$col$r',
          'readOnly': r == 6 || col == 'G',
          'kind': col == 'B'
              ? 'date'
              : ['C', 'D', 'E', 'F'].contains(col)
                  ? 'time'
                  : 'text',
          'value': r == 6
              ? ''
              : switch (col) {
                  'B' => '2026-08-${(r + 1).toString().padLeft(2, '0')}',
                  'E' => hours[r]?[0] ?? '',
                  'F' => hours[r]?[1] ?? '',
                  'H' => r <= 9 ? 'Realizado' : 'Programado',
                  'I' => 'Consultoria',
                  _ => ''
                }
        }
  ];
}

void main() {
  testWidgets(
      'choosing mapped entry returns to the original form instead of cell grid',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project:
                ProjectModel.fromJson({'id': '1', 'serviceType': 'Enterprise'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'owner@example.com',
            transport: (args) async {
              calls.add(args);
              if (args['action'] == 'excel-editor-sheets') {
                return {
                  'sheetNames': [
                    'Informa\u00e7\u00f5es de entrada',
                    'Checklist-Processo'
                  ]
                };
              }
              return snapshot();
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher guia'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(TextButton, 'Informa\u00e7\u00f5es de entrada'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkbookSheetDialog), findsNothing);
    expect(find.text('Nome do sistema'), findsOneWidget);
    expect(calls.any((c) => c.containsKey('worksheet')), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('Consultoria uses textual status and hours as denominator', () {
    expect(defaultProjectWorksheet('Consultoria'), 'Consultorias');
    expect(defaultProjectWorksheet('Treinamento Catalog + Consultoria'),
        'Cronogramas');
    expect(mappedWorksheetTab('Informa\u00e7\u00f5es de entrada'), 0);
    expect(mappedWorksheetTab('Professional Checklist-Processo'), 1);
    expect(mappedWorksheetTab('Implanta\u00e7\u00e3o - Linha do Tempo'), 2);
    final rows = scheduleRows(consultationFields(), {}, consultoria: true);
    expect(rows.length, 13);
    expect(scheduleProgress(rows)['Consultoria'], closeTo(2 / 19, 1e-9));
  });
  for (final width in [390.0, 1366.0]) {
    testWidgets(
        'Consultoria renders actual columns and saves Realizado at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fields = consultationFields();
      Map<String, dynamic>? write;
      await tester.pumpWidget(MaterialApp(
          home: WorkbookSheetDialog(
              projectId: '2262248',
              client: 'MESARO',
              serviceType: 'Consultoria',
              initialWorksheet: 'Consultorias',
              allowed: () => true,
              call: (args) async {
                if (args['action'] == 'excel-editor-sheets') {
                  return {
                    'sheetNames': ['Consultorias']
                  };
                }
                if (args['action'] == 'excel-editor-write') {
                  write = args;
                  for (final change in args['changes'] as List) {
                    fields.singleWhere(
                            (f) => f['cell'] == change['cell'])['value'] =
                        change['value'];
                  }
                }
                return {
                  'worksheet': 'Consultorias',
                  'firstRow': 1,
                  'firstColumn': 1,
                  'consultoriaTable': true,
                  'consultoriaDetails': {'contractedHours': '19:00'},
                  'fields': fields,
                  'revision': 'rev',
                  if (args['action'] == 'excel-editor-write') 'saved': true
                };
              })));
      await tester.pumpAndSettle();
      expect(find.text('Linha'), findsNothing);
      expect(find.text('Colunas 1–8'), findsNothing);
      expect(find.text('Horas contratadas: 19:00'), findsOneWidget);
      expect(find.text('02:00 / 17:00'), findsOneWidget);
      expect(find.text('11%'), findsOneWidget);
      final status = find.byKey(const ValueKey('schedule-status-H10'));
      await tester.ensureVisible(status);
      await tester.pumpAndSettle();
      await tester.tap(status);
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsNothing);
      await tester.tap(find.text('Realizado').last);
      await tester.pumpAndSettle();
      expect(find.text('06:00 / 13:00'), findsOneWidget);
      expect(find.text('32%'), findsOneWidget);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pumpAndSettle();
      expect(write!['changes'], [
        {
          'sheet': 'Consultorias',
          'cell': 'H10',
          'before': 'Programado',
          'value': 'Realizado'
        }
      ]);
      expect(tester.takeException(), isNull);
    });
  }
  for (final recognized in [null, false]) {
    testWidgets(
        'unrecognized consultation cannot fall back to cells: $recognized',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: WorkbookSheetDialog(
              projectId: '2262248',
              initialWorksheet: 'Consultorias',
              allowed: () => true,
              call: (args) async => args['action'] == 'excel-editor-sheets'
                  ? {
                      'sheetNames': ['Consultorias']
                    }
                  : {
                      'worksheet': 'Consultorias',
                      'firstRow': 1,
                      'firstColumn': 1,
                      'fields': consultationFields(),
                      if (recognized != null) 'consultoriaTable': recognized,
                    })));
      await tester.pumpAndSettle();
      expect(
          find.textContaining(
              recognized == null ? 'v52' : 'n\u00e3o foi reconhecida'),
          findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
    });
  }
}
