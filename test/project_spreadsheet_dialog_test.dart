import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_status_cache.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_status_preview.dart';
import 'dart:async';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_stage_dialog.dart';
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

Finder stagePercentField() => find.byWidgetPredicate((w) =>
    w is DropdownButtonFormField<double> &&
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('stage-percent-'));

void main() {
  testWidgets(
      'confirmed status persists and reopens without Excel, including failure',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySpreadsheetStore();
    var calls = 0;
    Future<Map<String, dynamic>> transport(Map<String, dynamic> args) async {
      calls++;
      if (args['action'] == 'excel-editor-preview')
        return {
          'preview': true,
          'checklistSheet': 'Checklist-Processo',
          'statusPreview': {
            'total': .60,
            'rows': [
              {'label': 'Implanta\u00e7\u00e3o', 'percentage': .60}
            ]
          },
        };
      return snapshot();
    }

    Widget app(
            Future<Map<String, dynamic>> Function(Map<String, dynamic>) call) =>
        MaterialApp(
            home: ProjectSpreadsheetDialog(
                project: ProjectModel.fromJson({
                  'id': '1',
                  'serviceType': 'Enterprise',
                  'excelLink': 'reference'
                }),
                uidProvider: () => 'owner',
                emailProvider: () => 'other@example.com',
                store: store,
                transport: call));
    await tester.pumpWidget(app(transport));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist-Processo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(savedSpreadsheetStatus(store.data, {})!['total'], .60);
    await tester.pumpWidget(const SizedBox());
    calls = 0;
    await tester.pumpWidget(app((_) async {
      calls++;
      throw StateError('Excel ocupado');
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist-Processo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('60,0%'), findsWidgets);
    await tester.tap(find.byTooltip('Atualizar pr\u00e9via'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('60,0%'), findsWidgets);
    expect(find.textContaining('Excel ocupado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'six complete status rows and tasks fit side by side at notebook height $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const labels = [
        'Gerencia do Projeto',
        'Contato Inicial',
        'Levantamento de Escopo',
        'Desenvolvimento',
        'Implantacao',
        'Pos-Implantacao'
      ];
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: ProjectSpreadsheetDialog(
              project: ProjectModel.fromJson(
                  {'id': '1', 'serviceType': 'Enterprise'}),
              uidProvider: () => 'owner',
              emailProvider: () => 'other@example.com',
              transport: (args) async =>
                  args['action'] == 'excel-editor-preview'
                      ? {
                          'preview': true,
                          'checklistSheet': 'Checklist-Processo',
                          'statusPreview': {
                            'total': .64,
                            'rows': [
                              for (final label in labels)
                                {
                                  'label': label,
                                  'percentage': .64,
                                  'weight': .2,
                                  'planned': .75,
                                  'start': '2026-10-01',
                                  'end': '2026-10-26'
                                }
                            ]
                          }
                        }
                      : snapshot())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checklist-Processo'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('checklist-side-by-side')), findsOneWidget);
      final panel = tester.getRect(find.byType(ChecklistStatusPanel));
      final table = tester.getRect(find.byType(DataTable));
      expect(table.right, lessThanOrEqualTo(panel.right));
      for (final label in labels) {
        final cell = find.descendant(
            of: find.byType(DataTable), matching: find.text(label));
        expect(tester.getRect(cell).bottom, lessThanOrEqualTo(panel.bottom));
        expect(tester.getRect(cell).top, greaterThanOrEqualTo(panel.top));
      }
      final task = find.byKey(const ValueKey('checklist-stage-Implantação'));
      expect(tester.getRect(task).left, greaterThanOrEqualTo(panel.right));
      expect(
          tester.getRect(task).bottom,
          lessThanOrEqualTo(
              tester.getTopLeft(find.text('Salvar na planilha')).dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'pending stage opens, applies and reopens while original Excel preview is blocked',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = Completer<Map<String, dynamic>>();
    var previews = 0;
    Map<String, dynamic> preview() => {
          'preview': true,
          'checklistSheet': 'Checklist-Processo',
          'statusPreview': {'rows': []}
        };
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project:
                ProjectModel.fromJson({'id': '1', 'serviceType': 'Enterprise'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'other@example.com',
            transport: (args) async {
              if (args['action'] == 'excel-editor-preview') {
                previews++;
                if (previews == 1) return original.future;
                return preview();
              }
              return snapshot();
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist-Processo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(previews, 1);
    expect(original.isCompleted, isFalse);
    await tester.tap(find.text('Pendentes'));
    await tester.pump();
    final stage = find.byKey(const ValueKey('checklist-stage-Implantação'));
    final open = tester.widget<ListTile>(stage).onTap!;
    open();
    open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChecklistStageDialog), findsOneWidget);
    await tester.tap(stagePercentField());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('75%').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar ajustes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChecklistStageDialog), findsNothing);
    expect(original.isCompleted, isFalse);
    await tester.tap(stage);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChecklistStageDialog), findsOneWidget);
    expect(
        tester
            .widget<DropdownButtonFormField<double>>(stagePercentField())
            .initialValue,
        .75);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.descendant(
        of: find.byType(ChecklistStageDialog),
        matching: find.text('Cancelar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    original.complete(preview());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(previews, 2); // Obsolete closed-stage requests never reach Excel.
    expect(find.text('Planilha do projeto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing stage releases UI while Excel requests stay serialized',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<Map<String, dynamic>>();
    var previews = 0, active = 0, maxActive = 0;
    Map<String, dynamic> preview() => {
          'preview': true,
          'checklistSheet': 'Checklist-Processo',
          'statusPreview': {'rows': []}
        };
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project:
                ProjectModel.fromJson({'id': '1', 'serviceType': 'Enterprise'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'other@example.com',
            transport: (args) async {
              if (args['action'] == 'excel-editor-preview') {
                previews++;
                active++;
                if (active > maxActive) maxActive = active;
                try {
                  if (previews == 2) return await pending.future;
                  return preview();
                } finally {
                  active--;
                }
              }
              return snapshot();
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist-Processo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checklist-stage-Implantação')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(previews, 2);
    await tester.tap(find.descendant(
        of: find.byType(ChecklistStageDialog),
        matching: find.text('Cancelar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChecklistStageDialog), findsNothing);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(active, 1);
    expect(previews, 2);
    pending.complete(preview());
    await tester.pumpAndSettle();
    expect(maxActive, 1);
    expect(find.text('Planilha do projeto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline opens separately and only editable dates open calendar',
      (tester) async {
    final data = snapshot();
    data['fields'] = List<Map<String, dynamic>>.from(data['fields'] as List);
    (data['fields'] as List).addAll(<Map<String, dynamic>>[
      {
        'sheet': 'Implantação - Linha do Tempo',
        'cell': 'C20',
        'label': 'Evento editavel',
        'kind': 'date',
        'group': 'Linha do tempo',
        'timeline': true,
        'value': '2026-10-23',
        'readOnly': false
      },
      {
        'sheet': 'Implantação - Linha do Tempo',
        'cell': 'C19',
        'label': 'Evento calculado',
        'kind': 'date',
        'group': 'Linha do tempo',
        'timeline': true,
        'value': '2026-10-22',
        'readOnly': true
      },
    ]);
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
      project: ProjectModel.fromJson({
        'id': '2263800',
        'client': 'Cliente',
        'serviceType': 'Enterprise',
        'excelLink': 'C:/Projeto.xlsm'
      }),
      uidProvider: () => 'owner',
      emailProvider: () => 'rodrigozaparolli79@gmail.com',
      contactsLoader: () async => [],
      transport: (_) async => data,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Evento editavel'), findsNothing);
    await tester.ensureVisible(find.text('Implantação - Linha do Tempo'));
    await tester.tap(find.text('Implantação - Linha do Tempo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextFormField, 'Evento calculado'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    await tester.tap(find.widgetWithText(TextFormField, 'Evento editavel'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(1366, 768), const Size(390, 844)]) {
      testWidgets('Approved spreadsheet layout fits $size in $brightness',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: ProjectSpreadsheetDialog(
                project: ProjectModel.fromJson({
                  'id': '2261144',
                  'client': 'ORQUINARE PLANEJADOS',
                  'serviceType': 'Enterprise'
                }),
                uidProvider: () => 'owner',
                emailProvider: () => 'rodrigozaparolli79@gmail.com',
                transport: (args) async =>
                    args['action'] == 'excel-editor-preview'
                        ? {
                            'preview': true,
                            'checklistSheet': 'Checklist-Processo',
                            'statusPreview': {
                              'total': .64,
                              'rows': [
                                for (final name in [
                                  'Contato Inicial',
                                  'Levantamento de Escopo',
                                  'Desenvolvimento',
                                  'Implantação',
                                  'Pós-Implantação'
                                ])
                                  {
                                    'label': name,
                                    'percentage': .5,
                                    'weight': .2,
                                    'planned': 1.0,
                                    'start': '2026-07-07',
                                    'end': '2026-10-16'
                                  }
                              ]
                            }
                          }
                        : snapshot())));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Checklist-Processo'));
        await tester.tap(find.text('Checklist-Processo'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        expect(find.text('Status Projeto'), findsOneWidget);
        expect(find.text('64,0%'), findsOneWidget);
        expect(find.text('Progresso total'), findsOneWidget);
        expect(tester.getBottomRight(find.text('Salvar na planilha')).dy,
            lessThan(size.height));
        final stageCard =
            find.byKey(const ValueKey('checklist-stage-Implantação'));
        if (size.width < 1100) {
          await tester.scrollUntilVisible(stageCard, 180,
              scrollable: find
                  .descendant(
                      of: find
                          .byKey(const ValueKey('checklist-stacked-scroll')),
                      matching: find.byType(Scrollable))
                  .first);
          await tester.pumpAndSettle();
          await tester.ensureVisible(stageCard);
          await tester.pumpAndSettle();
        }
        await tester
            .tap(find.byKey(const ValueKey('checklist-stage-Implantação')));
        await tester.pumpAndSettle();
        expect(stagePercentField(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'Preview uses pending checklist edits without saving or replacing the snapshot',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    final store = MemorySpreadsheetStore();
    await tester.pumpWidget(MaterialApp(
        home: ProjectSpreadsheetDialog(
            project:
                ProjectModel.fromJson({'id': '1', 'serviceType': 'Enterprise'}),
            uidProvider: () => 'owner',
            emailProvider: () => 'rodrigozaparolli79@gmail.com',
            store: store,
            transport: (args) async {
              calls.add(args);
              if (args['action'] == 'excel-editor-preview') {
                return {
                  'preview': true,
                  'checklistSheet': 'Checklist-Processo',
                  'statusPreview': {
                    'total': .64,
                    'source': 'Dados!AG5:AL11',
                    'rows': [
                      {'label': 'Implantação', 'percentage': .25, 'weight': .45}
                    ]
                  }
                };
              }
              return snapshot();
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist-Processo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final writes = store.writes;
    await tester.tap(find.byKey(const ValueKey('checklist-stage-Implantação')));
    await tester.pumpAndSettle();
    await tester.tap(stagePercentField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('25%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('64,0%'), findsOneWidget);
    expect(
        find.textContaining('Prévia das alterações pendentes'), findsOneWidget);
    expect(calls.last['changes'], [
      {
        'sheet': 'Checklist-Processo',
        'cell': 'E18',
        'before': 0.0,
        'value': .25
      }
    ]);
    expect(calls.any((c) => c['action'] == 'excel-editor-write'), isFalse);
    expect(store.writes, writes);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('1 alteração pendente'), findsOneWidget);
  });
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
    await tester.tap(find.byKey(const ValueKey('checklist-stage-Implantação')));
    await tester.pumpAndSettle();
    await tester.tap(stagePercentField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('25%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    final write =
        calls.singleWhere((call) => call['action'] == 'excel-editor-write');
    expect(write['serviceType'], 'Professional');
    expect(
        (write['changes'] as List).single['sheet'], 'Maker Checklist-Processo');
    expect((write['changes'] as List).single['cell'], 'E5');
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
      expect(find.text('1 alteração pendente'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Mais ações da planilha'));
    await tester.pumpAndSettle();
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
    expect(find.text('2 alterações pendentes'), findsOneWidget);
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

  testWidgets('Unauthenticated session never loads spreadsheet data',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectSpreadsheetDialog(
                project: ProjectModel.fromJson({'id': '1'}),
                uidProvider: () => null,
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
