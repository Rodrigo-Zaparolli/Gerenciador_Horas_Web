import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_sheet_settings.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_kind.dart';

class MemorySettings extends SpreadsheetSheetSettingsStore {
  final values = <String, Map<String, String>>{};
  @override
  Future<Map<String, String>> load(
          String uid, String project, String reference) async =>
      values['$uid/$project'] ?? {};
  @override
  Future<void> save(String uid, String project, String reference,
      Map<String, String> names) async {
    values['$uid/$project'] = Map.of(names);
  }
}

void main() {
  test('cached data must match both configured tabs', () {
    final cached = {
      'entrySheet': 'Entrada do cliente',
      'checklistSheet': 'Professional'
    };
    expect(
        spreadsheetMatchesProject(cached, 'Enterprise',
            entrySheet: 'Entrada do cliente', checklistSheet: 'Professional'),
        isTrue);
    expect(spreadsheetMatchesProject(cached, 'Enterprise'), isFalse);
    expect(
        spreadsheetMatchesProject(cached, 'Enterprise',
            entrySheet: 'Outra entrada', checklistSheet: 'Professional'),
        isFalse);
  });
  testWidgets(
      'Abas selects an existing renamed tab and restores it when reopening the project',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = MemorySettings();
    final requests = <Map<String, dynamic>>[];
    Widget editor() => MaterialApp(
            home: ProjectSpreadsheetDialog(
          project: ProjectModel.fromJson({
            'id': 'project',
            'serviceType': 'Enterprise',
            'excelLink': 'book'
          }),
          uidProvider: () => 'owner',
          emailProvider: () => 'rodrigozaparolli79@gmail.com',
          sheetSettingsStore: settings,
          transport: (args) async {
            requests.add(args);
            if (args['action'] == 'excel-editor-sheets') {
              return {
                'sheetNames': [
                  'Informações de entrada',
                  'Checklist-Processo',
                  'Professional CheckList-Processo'
                ]
              };
            }
            final names = args['sheetNames'] as Map<String, String>? ?? {};
            return {
              'revision': 'v1',
              'filename': 'Projeto.xlsm',
              'entrySheet': names['entry'] ?? 'Informações de entrada',
              'checklistSheet': names['checklist'] ?? 'Checklist-Processo',
              'fields': [],
              'tasks': []
            };
          },
        ));
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Configurar abas do modelo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professional CheckList-Processo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar estas abas'));
    await tester.pumpAndSettle();
    expect(settings.values['owner/project']?['checklist'],
        'Professional CheckList-Processo');
    expect(requests.last['sheetNames'], settings.values['owner/project']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    requests.clear();
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    expect(requests.single['sheetNames'], settings.values['owner/project']);
    expect(await settings.load('owner', 'other', 'book'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
