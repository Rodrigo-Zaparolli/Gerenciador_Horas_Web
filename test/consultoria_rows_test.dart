import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/consultoria_row_drafts.dart';
import 'consultoria_table_test.dart' show consultationFields;

class RowBackend {
  List<Map<String, dynamic>> fields = consultationFields();
  final writes = <List<Map<String, dynamic>>>[];
  bool fail = false, capable = true;
  Completer<void>? pending;
  Future<Map<String, dynamic>> call(Map<String, dynamic> args) async {
    if (args['action'] == 'excel-editor-sheets') {
      return {
        'sheetNames': ['Consultorias']
      };
    }
    if (args['action'] == 'excel-editor-write') {
      final payload = (args['changes'] as List).cast<Map<String, dynamic>>();
      writes.add(payload);
      if (pending != null) await pending!.future;
      if (fail) throw StateError('Arquivo bloqueado');
      final rows = <int, List<Map<String, dynamic>>>{};
      for (final field in fields) {
        final row = ConsultoriaRowDrafts.rowOf(field['cell'])!;
        if (row > 6) (rows[row] ??= []).add(Map.from(field));
      }
      for (final item in payload.where((p) => p['operation'] == null)) {
        rows.values
                .expand((v) => v)
                .singleWhere((f) => f['cell'] == item['cell'])['value'] =
            item['value'];
      }
      for (final op
          in payload.where((p) => p['operation'] == 'delete-consultoria-row')) {
        rows.remove(op['row']);
      }
      final result = rows.values.toList();
      for (final op
          in payload.where((p) => p['operation'] == 'add-consultoria-row')) {
        final values = op['values'] as Map;
        result.add([
          for (final c in 'BCDEFGHI'.split(''))
            {
              'sheet': 'Consultorias',
              'cell': '${c}0',
              'kind': c == 'B'
                  ? 'date'
                  : 'CDEF'.contains(c)
                      ? 'time'
                      : 'text',
              'readOnly': c == 'G' || c == 'I',
              'value': c == 'I' ? 'Consultoria' : values[c] ?? ''
            }
        ]);
      }
      fields = [
        ...fields.where((f) => ConsultoriaRowDrafts.rowOf(f['cell']) == 6),
        for (var i = 0; i < result.length; i++)
          for (final field in result[i])
            {...field, 'cell': '${field['cell'].toString()[0]}${7 + i}'}
      ];
    }
    return {
      'worksheet': 'Consultorias',
      'firstRow': 1,
      'firstColumn': 1,
      'consultoriaTable': true,
      'consultoriaRowOperationsVersion': capable ? 1 : null,
      'revision': 'rev-${writes.length}',
      'consultoriaDetails': {
        'contractedHours': '19:00',
        'description': 'Consultoria'
      },
      'fields': [for (final field in fields) Map<String, dynamic>.from(field)],
      if (args['action'] == 'excel-editor-write') ...{
        'saved': true,
        'rowsApplied': {
          'added': writes.last
              .where((p) => p['operation'] == 'add-consultoria-row')
              .length,
          'deleted': writes.last
              .where((p) => p['operation'] == 'delete-consultoria-row')
              .length
        }
      }
    };
  }
}

Future<void> mount(WidgetTester tester, RowBackend backend,
    {double width = 1366}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: WorkbookSheetDialog(
          projectId: '2262248',
          client: 'MESARO',
          serviceType: 'Consultoria',
          initialWorksheet: 'Consultorias',
          allowed: () => true,
          call: backend.call)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancel asks to discard row-only drafts without writing to Excel',
      (tester) async {
    final backend = RowBackend();
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => WorkbookSheetDialog(
                            projectId: '2262248',
                            initialWorksheet: 'Consultorias',
                            allowed: () => true,
                            call: backend.call)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-consultoria-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar altera\u00e7\u00f5es desta guia?'),
        findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('1 encontro adicionado'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Descartar'))
        .onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(find.byType(WorkbookSheetDialog), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(backend.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('draft commands never send fake Excel addresses or read-only fields',
      () {
    final draft = ConsultoriaRowDrafts();
    draft.add('Consultorias', 'Consultoria');
    final edits = <String, Map<String, dynamic>>{
      'C1000001': {'cell': 'C1000001', 'value': '08:00'},
      'H7': {'cell': 'H7', 'value': 'Realizado'}
    };
    draft.deleted.add(7);
    final payload = draft.payload(edits);
    expect(payload.length, 2);
    expect(payload.first, {'operation': 'delete-consultoria-row', 'row': 7});
    expect((payload.last['values'] as Map)['C'], '08:00');
    expect((payload.last['values'] as Map).containsKey('G'), isFalse);
    draft.remove(1000001, edits);
    expect(edits.containsKey('C1000001'), isFalse);
  });
  for (final width in [390.0, 1366.0]) {
    testWidgets(
        'add, mark deletion, preview and save actual row commands at $width',
        (tester) async {
      final backend = RowBackend();
      await mount(tester, backend, width: width);
      await tester.tap(find.byKey(const ValueKey('add-consultoria-row')));
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('new-time-C1000001'));
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.enterText(start, '08:00');
      final end = find.byKey(const ValueKey('new-time-D1000001'));
      await tester.ensureVisible(end);
      await tester.pumpAndSettle();
      await tester.enterText(end, '10:00');
      await tester.pumpAndSettle();
      expect(find.text('02:00 / 19:00'), findsOneWidget);
      final remove = find.byKey(const ValueKey('delete-consultoria-row-13'));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar para excluir'));
      await tester.pumpAndSettle();
      expect(find.text('1 encontro adicionado \u00b7 1 exclus\u00e3o pendente'),
          findsOneWidget);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pumpAndSettle();
      expect(backend.writes.length, 1);
      final payload = backend.writes.single;
      expect(payload.first, {'operation': 'delete-consultoria-row', 'row': 13});
      expect(payload.last['operation'], 'add-consultoria-row');
      expect((payload.last['values'] as Map)['D'], '10:00');
      expect(
          payload.any((p) => p['cell']?.toString().contains('1000001') == true),
          isFalse);
      expect(find.text('Sem altera\u00e7\u00f5es pendentes'), findsOneWidget);
      expect(find.text('02:00 / 19:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('undo restores summary and a failed save keeps the new row',
      (tester) async {
    final backend = RowBackend();
    await mount(tester, backend);
    final remove = find.byKey(const ValueKey('delete-consultoria-row-7'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar para excluir'));
    await tester.pumpAndSettle();
    expect(find.text('00:50 / 17:00'), findsOneWidget);
    await tester.ensureVisible(find.text('Desfazer'));
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(find.text('02:00 / 17:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-consultoria-row')));
    await tester.pumpAndSettle();
    backend.fail = true;
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Arquivo bloqueado'), findsOneWidget);
    expect(find.text('1 encontro adicionado'), findsOneWidget);
    expect(backend.writes.length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('old integration cannot start row changes', (tester) async {
    final backend = RowBackend()..capable = false;
    await mount(tester, backend);
    await tester.tap(find.byKey(const ValueKey('add-consultoria-row')));
    await tester.pumpAndSettle();
    expect(find.textContaining('v53'), findsOneWidget);
    expect(backend.writes, isEmpty);
    expect(find.text('1 encontro adicionado'), findsNothing);
  });
  testWidgets('save pending disables a second write', (tester) async {
    final backend = RowBackend();
    await mount(tester, backend);
    await tester.tap(find.byKey(const ValueKey('add-consultoria-row')));
    await tester.pumpAndSettle();
    backend.pending = Completer<void>();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pump();
    expect(backend.writes.length, 1);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Salvar na planilha'));
    expect(button.onPressed, isNull);
    backend.pending!.complete();
    await tester.pumpAndSettle();
    expect(backend.writes.length, 1);
  });
}
