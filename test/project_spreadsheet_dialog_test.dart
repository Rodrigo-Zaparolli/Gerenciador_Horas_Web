import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';

Map<String, dynamic> snapshot() => {'revision': 'v1', 'filename': 'Projeto.xlsm', 'progress': .5,
  'fields': [{'sheet': 'Informações de entrada', 'cell': 'C27', 'label': 'Nome do sistema',
    'kind': 'text', 'group': 'Sistema', 'value': 'Sistema anterior'}],
  'tasks': [{'sheet': 'Checklist-Processo', 'cell': 'E18', 'label': 'Configurar os plugins',
    'kind': 'percent', 'group': 'Implantação', 'value': 0.0, 'estimated': '02:00', 'note': ''}]};

void main() {
  testWidgets('Loads original values and sends only edits with revision and before value', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProjectSpreadsheetDialog(
      project: ProjectModel.fromJson({'id': '2261144', 'client': 'Orquinare', 'excelLink': 'file-reference'}),
      uidProvider: () => 'owner', emailProvider: () => 'rodrigozaparolli79@gmail.com',
      transport: (args) async {
        calls.add(args);
        if (args['action'] == 'excel-editor-write') {
          final result = snapshot();
          (result['fields'] as List).first['value'] = 'Novo sistema';
          return {...result, 'revision': 'v2', 'saved': true, 'backup': 'backup.xlsm'};
        }
        return snapshot();
      }))));
    await tester.pumpAndSettle();
    expect(find.text('Sistema anterior'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Novo sistema');
    await tester.pump();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.last['revision'], 'v1');
    expect(calls.last['reference'], 'file-reference');
    expect(calls.last['changes'], [{'sheet': 'Informações de entrada', 'cell': 'C27',
      'before': 'Sistema anterior', 'value': 'Novo sistema'}]);
    expect(find.textContaining('Planilha atualizada e conferida.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Other account never loads spreadsheet data', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProjectSpreadsheetDialog(
      project: ProjectModel.fromJson({'id': '1'}), uidProvider: () => 'other',
      emailProvider: () => 'other@example.com', transport: (_) async { calls++; return snapshot(); }))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Sistema anterior'), findsNothing);
  });
}
