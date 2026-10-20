import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_store.dart';
import 'package:gerenciador_horas/features/projects/dialogs/company_contacts.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_kind.dart';

class MemorySpreadsheetStore implements SpreadsheetStore {
  Map<String, dynamic>? data;
  bool failSave = false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> load(
          String uid, String project, String reference) async =>
      data;
  @override
  Future<void> save(String uid, String project, String reference,
      Map<String, dynamic> value) async {
    if (failSave) throw StateError('Sem conexão');
    writes++;
    data = value;
  }
}

Map<String, dynamic> snapshot() => {
      'revision': 'v1',
      'filename': 'Projeto.xlsm',
      'progress': .5,
      'fields': [
        {
          'sheet': 'Informações de entrada',
          'cell': 'C27',
          'label': 'Nome do sistema',
          'kind': 'text',
          'group': 'Sistema',
          'value': 'Sistema anterior'
        }
      ],
      'tasks': [
        {
          'sheet': 'Checklist-Processo',
          'cell': 'E18',
          'label': 'Configurar os plugins',
          'kind': 'percent',
          'group': 'Implantação',
          'value': 0.0,
          'estimated': '02:00',
          'note': ''
        }
      ]
    };

void main() {
  test('Cached checklist must match the current service type', () {
    expect(spreadsheetMatchesProject(snapshot(), 'Enterprise'), isTrue);
    expect(spreadsheetMatchesProject(snapshot(), 'Professional'), isFalse);
    expect(projectChecklistSheet('Promob Professional'),
        'Maker CheckList-Processo');
    expect(
        spreadsheetMatchesProject(
            {'checklistSheet': 'Maker Checklist-Processo'}, 'Professional'),
        isTrue);
    expect(
        spreadsheetMatchesProject(
            {'checklistSheet': 'Maker Checklist-Processo'}, 'Enterprise'),
        isFalse);
  });

  testWidgets(
      'Professional ignores Enterprise cache and routes reads and writes to Maker',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySpreadsheetStore()..data = snapshot();
    final calls = <Map<String, dynamic>>[];
    final maker = snapshot();
    maker['checklistSheet'] = 'Maker Checklist-Processo';
    maker['tasks'] = [
      <String, dynamic>{
        ...(maker['tasks'] as List).first,
        'sheet': 'Maker Checklist-Processo',
        'cell': 'E5'
      }
    ];
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project: ProjectModel.fromJson(
                {'id': '1', 'serviceType': 'Professional'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'rodrigozaparolli79@gmail.com',
            store: store,
            transport: (args) async {
              calls.add(args);
              if (args['action'] == 'excel-editor-write') {
                return {
                  ...maker,
                  'saved': true,
                  'revision': 'v2',
                  'backup': 'backup',
                  'tasks': [
                    <String, dynamic>{
                      ...(maker['tasks'] as List).first,
                      'value': .25
                    }
                  ]
                };
              }
              return maker;
            })));
    await tester.pumpAndSettle();
    expect(calls.single['serviceType'], 'Professional');
    expect(find.text('Maker CheckList-Processo'), findsOneWidget);
    await tester.tap(find.text('Maker CheckList-Processo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Implantação'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(calls.last['serviceType'], 'Professional');
    expect((calls.last['changes'] as List).single['sheet'],
        'Maker Checklist-Processo');
    expect((calls.last['changes'] as List).single['cell'], 'E5');
    expect(store.data!['checklistSheet'], 'Maker Checklist-Processo');
  });

  testWidgets('Professional rejects an older integration returning Enterprise',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project: ProjectModel.fromJson(
                {'id': '1', 'serviceType': 'Professional'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'rodrigozaparolli79@gmail.com',
            transport: (_) async => snapshot())));
    await tester.pumpAndSettle();
    expect(find.textContaining('checklist diferente'), findsOneWidget);
    expect(find.text('Sistema anterior'), findsNothing);
  });
  for (final calculated in ['rodrigo@empresa.com', 'outro@empresa.com']) {
    testWidgets(
        'Calculated consultant email fills and checks Excel result $calculated',
        (tester) async {
      final value = snapshot();
      value['fields'] = [
        {
          'sheet': 'Entrada',
          'cell': 'F37',
          'label': 'Consultor de Implantação — Nome',
          'kind': 'text',
          'group': 'Equipe Cyncly',
          'value': 'Anterior'
        },
        {
          'sheet': 'Entrada',
          'cell': 'G37',
          'label': 'Consultor de Implantação — E-mail',
          'kind': 'text',
          'group': 'Equipe Cyncly',
          'value': 'anterior@empresa.com',
          'readOnly': true
        }
      ];
      final calls = <Map<String, dynamic>>[];
      await tester.pumpWidget(MaterialApp(
          home: ProjectSpreadsheetDialog(
              project: ProjectModel.fromJson({'id': '1'}),
              uidProvider: () => 'owner',
              emailProvider: () => 'rodrigozaparolli79@gmail.com',
              transport: (args) async {
                calls.add(args);
                if (args['action'] == 'excel-editor-write') {
                  return {
                    ...value,
                    'saved': true,
                    'backup': 'backup',
                    'revision': 'v2',
                    'fields': [
                      <String, dynamic>{
                        ...(value['fields'] as List).first,
                        'value': 'Rodrigo'
                      },
                      <String, dynamic>{
                        ...(value['fields'] as List).last,
                        'value': calculated
                      }
                    ]
                  };
                }
                return value;
              },
              contactsLoader: () async => [
                    const CompanyContact('1', 'Rodrigo', 'rodrigo@empresa.com')
                  ])));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Rod');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('rodrigo@empresa.com'), findsOneWidget);
      expect(find.textContaining('fórmula do Excel será conferida'),
          findsOneWidget);
      expect(find.text('1 alteração(ões) não salva(s)'), findsOneWidget);
      await tester.tap(find.text('Salvar na planilha'));
      await tester.pumpAndSettle();
      expect((calls.last['changes'] as List).single['cell'], 'F37');
      expect(find.text(calculated), findsOneWidget);
      expect(
          find.textContaining(calculated == 'rodrigo@empresa.com'
              ? 'Planilha atualizada e conferida.'
              : 'fórmula do Excel retornou um e-mail diferente'),
          findsOneWidget);
    });
  }
  testWidgets('Reopening uses saved project data without requesting Excel',
      (tester) async {
    final store = MemorySpreadsheetStore()
      ..data = {...snapshot(), 'syncedAt': '2026-10-20T10:00:00'};
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project:
                ProjectModel.fromJson({'id': '1', 'excelLink': 'reference'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'rodrigozaparolli79@gmail.com',
            store: store,
            transport: (_) async {
              calls++;
              throw StateError('Integração desligada');
            })));
    await tester.pumpAndSettle();
    expect(find.text('Sistema anterior'), findsOneWidget);
    expect(calls, 0);
    expect(find.textContaining('Última sincronização'), findsOneWidget);
    await tester.tap(find.text('Recarregar do Excel'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Sistema anterior'), findsOneWidget);
  });

  testWidgets(
      'Failed cloud save keeps confirmed Excel result and does not send again',
      (tester) async {
    final store = MemorySpreadsheetStore();
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project:
                ProjectModel.fromJson({'id': '1', 'excelLink': 'reference'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'rodrigozaparolli79@gmail.com',
            store: store,
            transport: (args) async {
              if (args['action'] == 'excel-editor-write') {
                writes++;
                store.failSave = true;
                final next = snapshot();
                (next['fields'] as List).first['value'] = 'Atualizado';
                return {
                  ...next,
                  'revision': 'v2',
                  'saved': true,
                  'backup': 'backup'
                };
              }
              return snapshot();
            })));
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    await tester.enterText(find.byType(TextFormField).first, 'Atualizado');
    await tester.pump();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.textContaining('cópia no sistema não foi atualizada'),
        findsOneWidget);
    expect(find.text('Sem alterações pendentes'), findsOneWidget);
    store.failSave = false;
    await tester.tap(find.text('Salvar cópia no sistema'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(store.data!['revision'], 'v2');
  });

  testWidgets(
      'Selecting collaborator fills paired email and stages both changes',
      (tester) async {
    final value = snapshot();
    value['fields'] = [
      {
        'sheet': 'Entrada',
        'cell': 'F36',
        'label': 'Consultor — Nome',
        'kind': 'text',
        'group': 'Equipe Cyncly',
        'value': ''
      },
      {
        'sheet': 'Entrada',
        'cell': 'G36',
        'label': 'Consultor — E-mail',
        'kind': 'text',
        'group': 'Equipe Cyncly',
        'value': ''
      }
    ];
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project: ProjectModel.fromJson({'id': '1'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'rodrigozaparolli79@gmail.com',
            transport: (_) async => value,
            contactsLoader: () async => [
                  const CompanyContact('1', 'Rodrigo', 'rodrigo@empresa.com')
                ])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Rod');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rodrigo').last);
    await tester.pumpAndSettle();
    expect(find.text('rodrigo@empresa.com'), findsOneWidget);
    expect(find.text('2 alteração(ões) não salva(s)'), findsOneWidget);
  });
  testWidgets(
      'Loads original values and sends only edits with revision and before value',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectSpreadsheetDialog(
                project: ProjectModel.fromJson({
                  'id': '2261144',
                  'client': 'Orquinare',
                  'excelLink': 'file-reference'
                }),
                uidProvider: () => 'owner',
                emailProvider: () => 'rodrigozaparolli79@gmail.com',
                transport: (args) async {
                  calls.add(args);
                  if (args['action'] == 'excel-editor-write') {
                    final result = snapshot();
                    (result['fields'] as List).first['value'] = 'Novo sistema';
                    return {
                      ...result,
                      'revision': 'v2',
                      'saved': true,
                      'backup': 'backup.xlsm'
                    };
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
    expect(calls.last['changes'], [
      {
        'sheet': 'Informações de entrada',
        'cell': 'C27',
        'before': 'Sistema anterior',
        'value': 'Novo sistema'
      }
    ]);
    expect(find.textContaining('Planilha atualizada e conferida.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Other account never loads spreadsheet data', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectSpreadsheetDialog(
                project: ProjectModel.fromJson({'id': '1'}),
                uidProvider: () => 'other',
                emailProvider: () => 'other@example.com',
                transport: (_) async {
                  calls++;
                  return snapshot();
                }))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Sistema anterior'), findsNothing);
  });
}
