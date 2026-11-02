import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_draft.dart';
import 'package:gerenciador_horas/features/projects/dialogs/consultoria_row_drafts.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_value_validation.dart';
import 'package:gerenciador_horas/features/edesk/integration_readiness_panel.dart';
import 'package:gerenciador_horas/features/projects/dialogs/workbook_sheet_dialog.dart';
import 'package:gerenciador_horas/features/edesk/received_work_dialog.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'received_work_store_test.dart' show ImportAuth;
import 'project_spreadsheet_dialog_test.dart' show snapshot;

void main() {
  test(
      'field parser matches Excel percentages, localized decimals and named statuses',
      () {
    expect(
        parseWorkbookInput({'kind': 'number', 'percent': true}, '25,5'), .255);
    expect(() => parseWorkbookInput({'kind': 'number', 'percent': true}, '150'),
        throwsFormatException);
    expect(() => parseWorkbookInput({'kind': 'time', 'value': ''}, '08:99'),
        throwsFormatException);
    expect(
        parseWorkbookInput(
            {'kind': 'number', 'percent': true, 'scheduleStatus': true},
            'Programado'),
        'Programado');
  });
  testWidgets('repeated import callbacks send only one local save',
      (tester) async {
    final pending = Completer<int>();
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: ReceivedWorkReview(
      auth: ImportAuth(),
      summary: const {
        'solicitacao': '1',
        'client': 'Cliente',
        'leader': 'Lider',
        'serviceType': 'Enterprise'
      },
      types: const ['Enterprise'],
      formats: [
        WorkFormat(id: 'e', name: 'Enterprise', steps: ['Implantação'])
      ],
      details: const [
        {
          'idTrabalho': '3',
          'values': {'name': 'Implantação', 'estimatedHours': '01:00'}
        }
      ],
      importProject: (_) {
        writes++;
        return pending.future;
      },
    )));
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Cadastrar no app'))
        .onPressed!;
    action();
    action();
    await tester.pump();
    expect(writes, 1);
    pending.complete(1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'worksheet draft restores pending cells and clears only after confirmed Excel save',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = ConsultoriaRowDrafts();
    SpreadsheetDraft.save('u', '1', 'file-a', 'Dados', {
      'revision': 'v1',
      'changes': [
        {
          'sheet': 'Dados',
          'cell': 'A1',
          'before': 'Original',
          'value': 'Recuperado'
        }
      ],
      'rows': rows.toJson()
    });
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: WorkbookSheetDialog(
      projectId: '1',
      draftOwner: 'u',
      fileReference: 'file-a',
      initialWorksheet: 'Dados',
      allowed: () => true,
      call: (args) async {
        if (args['action'] == 'excel-editor-sheets')
          return {
            'sheetNames': ['Dados']
          };
        final writing = args['action'] == 'excel-editor-write';
        if (writing) writes++;
        return {
          'worksheet': 'Dados',
          'firstRow': 1,
          'firstColumn': 1,
          'revision': writing ? 'v2' : 'v1',
          if (writing) 'saved': true,
          'fields': [
            for (var col = 0; col < 8; col++)
              {
                'sheet': 'Dados',
                'cell': '${String.fromCharCode(65 + col)}1',
                'kind': 'text',
                'value': col == 0 ? (writing ? 'Recuperado' : 'Original') : '',
                'display':
                    col == 0 ? (writing ? 'Recuperado' : 'Original') : '',
                'readOnly': false
              }
          ]
        };
      },
    )));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('Recuperar ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver células (avançado)'));
    await tester.pumpAndSettle();
    expect(find.text('Recuperado'), findsOneWidget);
    expect(SpreadsheetDraft.read('u', '1', 'file-a', 'Dados'), isNotNull);
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(SpreadsheetDraft.read('u', '1', 'file-a', 'Dados'), isNull);
    expect(find.text('Salvo no Excel'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  test('drafts require exact account, project, file, worksheet and revision',
      () {
    final draft = {
      'revision': 'v1',
      'changes': [
        {'sheet': 'S', 'cell': 'A1', 'before': 0, 'value': .5}
      ]
    };
    expect(SpreadsheetDraft.save('u', '1', 'file-a', 'S', draft), isTrue);
    for (final scope in [
      ('other', '1', 'file-a', 'S'),
      ('u', '2', 'file-a', 'S'),
      ('u', '1', 'file-b', 'S'),
      ('u', '1', 'file-a', 'T')
    ]) {
      expect(SpreadsheetDraft.read(scope.$1, scope.$2, scope.$3, scope.$4),
          isNull);
    }
    final stored = SpreadsheetDraft.read('u', '1', 'file-a', 'S')!;
    final fields = [
      {'sheet': 'S', 'cell': 'A1', 'value': 0, 'kind': 'percent'}
    ];
    expect(
        SpreadsheetDraft.validatedChanges(stored, 'v1', fields), hasLength(1));
    expect(SpreadsheetDraft.validatedChanges(stored, 'v2', fields), isNull);
    expect(
        SpreadsheetDraft.validatedChanges(stored, 'v1', [
          {...fields.first, 'value': .25}
        ]),
        isNull);
    expect(
        SpreadsheetDraft.validatedChanges(stored, 'v1', [
          {...fields.first, 'readOnly': true}
        ]),
        isNull);
  });
  test('restored added and deleted rows preserve payload and reject cycles',
      () {
    final rows = ConsultoriaRowDrafts()..add('S', 'Consultoria', below: 7);
    rows.add('S', 'Consultoria', below: rows.added.keys.first);
    rows.deleted.add(9);
    final restored = ConsultoriaRowDrafts();
    expect(restored.restore(rows.toJson()), isTrue);
    expect(restored.payload({}), rows.payload({}));
    final corrupt = rows.toJson();
    (corrupt['after'] as Map)['1000001'] = 1000002;
    expect(ConsultoriaRowDrafts().restore(corrupt), isFalse);
  });
  test(
      'typed fields reject invalid values and permit Excel durations and clearing',
      () {
    expect(validateWorkbookValue({'percent': true}, 1.1), isNotNull);
    expect(validateWorkbookValue({'percent': true}, -.1), isNotNull);
    expect(validateWorkbookValue({'percent': true}, .75), isNull);
    expect(validateWorkbookValue({'kind': 'time'}, '08:99'), isNotNull);
    expect(validateWorkbookValue({'kind': 'time'}, '120:30'), isNull);
    expect(validateWorkbookValue({'kind': 'time'}, ''), isNull);
  });
  testWidgets('mapped editor closes during read and ignores late response',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ProjectSpreadsheetDialog(
                            project: ProjectModel.fromJson(
                                {'id': '1', 'serviceType': 'Enterprise'}),
                            uidProvider: () => 'u',
                            emailProvider: () => 'rodrigozaparolli79@gmail.com',
                            transport: (_) => pending.future)),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Fechar planilha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProjectSpreadsheetDialog), findsNothing);
    pending.complete(snapshot());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final revision in ['v1', 'v2']) {
    testWidgets(
        'mapped draft restoration is explicit and checks live revision $revision',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SpreadsheetDraft.save('u', '1', 'file-a',
          'mapped:Informações de entrada:Checklist-Processo', {
        'revision': 'v1',
        'changes': [
          {
            'sheet': 'Informações de entrada',
            'cell': 'C27',
            'before': 'Sistema anterior',
            'value': 'Recuperado'
          }
        ]
      });
      var writes = 0;
      await tester.pumpWidget(MaterialApp(
          home: ProjectSpreadsheetDialog(
              project: ProjectModel.fromJson({
                'id': '1',
                'serviceType': 'Enterprise',
                'excelLink': 'file-a'
              }),
              uidProvider: () => 'u',
              emailProvider: () => 'rodrigozaparolli79@gmail.com',
              transport: (args) async {
                if (args['action'] == 'excel-editor-write') writes++;
                if (args['action'] == 'excel-editor-preview')
                  return {
                    'preview': true,
                    'checklistSheet': 'Checklist-Processo',
                    'statusPreview': {'rows': []}
                  };
                return {...snapshot(), 'revision': revision};
              })));
      await tester.pumpAndSettle();
      expect(writes, 0);
      if (revision == 'v1') {
        await tester.tap(find.text('Recuperar ajustes'));
        await tester.pumpAndSettle();
        expect(find.text('1 alteração pendente'), findsOneWidget);
        expect(
            tester
                .widgetList<EditableText>(find.byType(EditableText))
                .map((field) => field.controller.text),
            contains('Recuperado'));
        expect(find.text('Salvo no Excel'), findsNothing);
      } else {
        expect(find.text('Recuperar ajustes'), findsNothing);
        await tester.tap(find.text('Descartar rascunho'));
        await tester.pumpAndSettle();
        expect(
            SpreadsheetDraft.read('u', '1', 'file-a',
                'mapped:Informações de entrada:Checklist-Processo'),
            isNull);
      }
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final mode in ['ready', 'busy', 'files', 'offline']) {
    testWidgets('integration readiness distinguishes $mode without saving',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: IntegrationReadinessPanel(
                  allowed: () => true,
                  check: () async {
                    if (mode == 'offline') throw TimeoutException('offline');
                    return {
                      'service': 'gerenciador-horas-edesk',
                      'mode': mode == 'files' ? 'files-only' : 'local',
                      'busy': mode == 'busy',
                      'integrationPackageVersion': 'work-diagnostics-59',
                      'workGridImport': true,
                      'requestTitleImport': true
                    };
                  }))));
      await tester.tap(find.text('Verificar integração'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining(switch (mode) {
            'ready' => 'pronta para importar',
            'busy' => 'ocupada',
            'files' => 'Somente arquivos',
            _ => 'Sem resposta'
          }),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
