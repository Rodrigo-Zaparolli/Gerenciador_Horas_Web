import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/cronograma_table.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';

List<Map<String, dynamic>> fields() => [
      for (var r = 5; r <= 7; r++)
        for (final c in ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'])
          {
            'cell': '$c$r',
            'sheet': 'Cronogramas',
            'readOnly': r == 5 || c == 'G',
            'kind': c == 'H' ? 'number' : 'text',
            'value': r == 5
                ? c
                : switch (c) {
                    'B' => '2026-10-28',
                    'C' => '08:00',
                    'D' => r == 6 ? '12:00' : '10:00',
                    'H' => 0.0,
                    'I' => 'Consultoria Catalog',
                    _ => ''
                  },
          }
    ];

void main() {
  test(
      'weighted progress includes all encounters, cancellation and restored edits',
      () {
    final f = fields();
    final edits = <String, Map<String, dynamic>>{
      'H6': {'value': .5}
    };
    expect(scheduleProgress(scheduleRows(f, edits))['Consultoria Catalog'],
        closeTo(1 / 3, 1e-9));
    edits['H7'] = {'value': 'Cancelado'};
    expect(scheduleProgress(scheduleRows(f, edits))['Consultoria Catalog'], .5);
    edits['H7'] = {'value': 'Programado'};
    expect(scheduleProgress(scheduleRows(f, edits))['Consultoria Catalog'],
        closeTo(1 / 3, 1e-9));
    edits['D6'] = {'value': '07:00'};
    expect(scheduleProgress(scheduleRows(f, edits))['Consultoria Catalog'],
        isNull);
  });
  for (final width in [390.0, 1366.0]) {
    testWidgets(
        'schedule status updates preview and saves exact cell at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? written;
      final pending = fields();
      await tester.pumpWidget(MaterialApp(
          home: WorkbookSheetDialog(
              initialWorksheet: 'Cronogramas',
              allowed: () => true,
              call: (args) async {
                if (args['action'] == 'excel-editor-sheets') {
                  return {
                    'sheetNames': ['Cronogramas']
                  };
                }
                if (args['action'] == 'excel-editor-write') {
                  written = args;
                  for (final change in args['changes'] as List) {
                    pending.singleWhere(
                            (f) => f['cell'] == change['cell'])['value'] =
                        change['value'];
                  }
                }
                return {
                  'worksheet': 'Cronogramas',
                  'firstRow': 5,
                  'firstColumn': 2,
                  'worksheetTypesVersion': 2,
                  'scheduleTable': true,
                  'revision': 'rev',
                  'fields': pending,
                  if (args['action'] == 'excel-editor-write') 'saved': true
                };
              })));
      await tester.pumpAndSettle();
      final status = find.byKey(const ValueKey('schedule-status-H6'));
      await tester.ensureVisible(status);
      await tester.pumpAndSettle();
      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('50%').last);
      await tester.pumpAndSettle();
      expect(find.text('Consultoria Catalog · 33,3%'), findsOneWidget);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pumpAndSettle();
      expect(written!['changes'], [
        {'sheet': 'Cronogramas', 'cell': 'H6', 'before': 0.0, 'value': .5}
      ]);
      expect(tester.takeException(), isNull);
    });
  }
}
