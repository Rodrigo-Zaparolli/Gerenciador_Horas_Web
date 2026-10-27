import 'dart:async';
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
  testWidgets(
      'saved non-Cronogramas guide keeps project header and retries busy reads',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
            projectId: '2262248',
            client: 'MESARO',
            serviceType: 'Consultoria',
            initialWorksheet: 'Consultoria',
            allowed: () => true,
            call: (args) async {
              if (args['action'] == 'excel-editor-sheets') {
                return {
                  'sheetNames': ['Consultoria']
                };
              }
              expect(args['firstRow'], 1);
              expect(args['firstColumn'], 1);
              if (reads++ == 0) {
                throw StateError(
                    'Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.');
              }
              return {
                'worksheet': 'Consultoria',
                'firstRow': 1,
                'firstColumn': 1,
                'fields': []
              };
            })));
    await tester.pump();
    expect(find.text('Planilha do projeto'), findsOneWidget);
    expect(find.text('Todas as guias da planilha'), findsNothing);
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.textContaining('Aguarde a leitura'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing while read waits for Excel cancels the next attempt',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => WorkbookSheetDialog(
                            projectId: '2265173',
                            initialWorksheet: 'Cronogramas',
                            allowed: () => true,
                            call: (args) async {
                              calls++;
                              throw StateError(
                                  'Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.');
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 1);
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(WorkbookSheetDialog), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('busy save is not retried automatically', (tester) async {
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
            projectId: '2265173',
            initialWorksheet: 'Cronogramas',
            allowed: () => true,
            call: (args) async {
              if (args['action'] == 'excel-editor-sheets') {
                return {
                  'sheetNames': ['Cronogramas']
                };
              }
              if (args['action'] == 'excel-editor-write') {
                writes++;
                throw StateError(
                    'Aguarde a leitura ou grava\u00e7\u00e3o da planilha em andamento.');
              }
              return {
                'worksheet': 'Cronogramas',
                'firstRow': 5,
                'firstColumn': 2,
                'scheduleTable': true,
                'worksheetTypesVersion': 2,
                'revision': 'rev',
                'fields': fields()
              };
            })));
    await tester.pumpAndSettle();
    final status = find.byKey(const ValueKey('schedule-status-H6'));
    await tester.ensureVisible(status);
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('50%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(writes, 1);
    expect(find.textContaining('Aguarde a leitura'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('retry after failed direct read keeps schedule coordinates',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
            projectId: '2265173',
            client: 'RIMO',
            initialWorksheet: 'Cronogramas',
            allowed: () => true,
            call: (args) async {
              if (args['action'] == 'excel-editor-sheets') {
                return {
                  'sheetNames': ['Cronogramas']
                };
              }
              expect(args['firstRow'], 5);
              expect(args['firstColumn'], 2);
              if (reads++ == 0) throw StateError('Falha temporaria');
              return {
                'worksheet': 'Cronogramas',
                'firstRow': 5,
                'firstColumn': 2,
                'worksheetTypesVersion': 2,
                'scheduleTable': true,
                'fields': fields(),
                'revision': 'rev'
              };
            })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Falha temporaria'), findsOneWidget);
    await tester.tap(find.text('Recarregar do Excel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-status-H6')), findsOneWidget);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'project header and tabs remain visible while schedule loads directly',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
            projectId: '2265173',
            client: 'RIMO',
            serviceType: 'Treinamento Catalog',
            initialWorksheet: 'Cronogramas',
            allowed: () => true,
            call: (args) async {
              calls.add(args['action']);
              if (args['action'] == 'excel-editor-sheets') {
                return {
                  'sheetNames': ['Cronogramas']
                };
              }
              return pending.future;
            })));
    await tester.pump();
    expect(find.text('Planilha do projeto'), findsOneWidget);
    expect(find.text('Cronograma'), findsOneWidget);
    expect(find.text('Todas as guias da planilha'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(calls, ['excel-editor-read']);
    pending.complete({
      'worksheet': 'Cronogramas',
      'firstRow': 5,
      'firstColumn': 2,
      'scheduleTable': true,
      'worksheetTypesVersion': 2,
      'revision': 'rev',
      'fields': fields()
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-status-H6')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final recognized in [false, null]) {
    testWidgets(
        'unrecognized schedule never falls back to old grid: $recognized',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: WorkbookSheetDialog(
        initialWorksheet: 'Cronogramas',
        allowed: () => true,
        call: (args) async => args['action'] == 'excel-editor-sheets'
            ? {
                'sheetNames': ['Cronogramas']
              }
            : {
                'worksheet': 'Cronogramas',
                'firstRow': 5,
                'firstColumn': 2,
                'worksheetTypesVersion': 2,
                if (recognized != null) 'scheduleTable': recognized,
                'fields': fields()
              },
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('O editor antigo'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Salvar na planilha'));
      expect(save.onPressed, isNull);
    });
  }
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
              projectId: '2265173',
              client: 'RIMO',
              serviceType: 'Treinamento Catalog',
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
