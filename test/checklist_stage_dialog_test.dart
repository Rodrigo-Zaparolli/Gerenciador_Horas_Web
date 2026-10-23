import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_stage_dialog.dart';

Finder field(String cell) => find.byWidgetPredicate((w) =>
    w is DropdownButtonFormField<double> &&
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>)
        .value
        .startsWith('stage-percent-Checklist!$cell-'));

Future<void> choose(WidgetTester tester, String cell, String value) async {
  await tester.ensureVisible(field(cell));
  await tester.tap(field(cell));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$value%').last);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'percent labels and pending filter preserve hidden drafts at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, double>? result;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        child: const Text('Abrir'),
                        onPressed: () async {
                          result = await showDialog<Map<String, double>>(
                              context: context,
                              builder: (_) => ChecklistStageDialog(
                                  stage: 'Implantação',
                                  tasks: const [
                                    {
                                      'sheet': 'Checklist',
                                      'cell': 'E1',
                                      'label': 'Não iniciada',
                                      'estimated': '01:00'
                                    },
                                    {
                                      'sheet': 'Checklist',
                                      'cell': 'E2',
                                      'label': 'Em andamento',
                                      'estimated': '02:00'
                                    },
                                    {
                                      'sheet': 'Checklist',
                                      'cell': 'E3',
                                      'label': 'Terminada',
                                      'estimated': '03:00',
                                      'readOnly': true
                                    },
                                  ],
                                  values: const {
                                    'Checklist!E1': 0,
                                    'Checklist!E2': .5,
                                    'Checklist!E3': 1
                                  },
                                  canApply: () => true));
                        })))));
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        expect(find.text('0%'), findsOneWidget);
        expect(find.text('50%'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('stage-pending-only')));
        await tester.pumpAndSettle();
        expect(find.text('Terminada'), findsNothing);
        expect(find.text('2 de 3 tarefas'), findsOneWidget);
        await choose(tester, 'E2', '100');
        expect(find.text('Em andamento'), findsNothing);
        expect(find.text('1 de 3 tarefas'), findsOneWidget);
        await choose(tester, 'E1', '25');
        await tester.tap(find.byKey(const ValueKey('stage-pending-only')));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<DropdownButtonFormField<double>>(field('E2'))
                .initialValue,
            1);
        await tester.tap(find.text('Aplicar ajustes'));
        await tester.pumpAndSettle();
        expect(result,
            {'Checklist!E1': .25, 'Checklist!E2': 1, 'Checklist!E3': 1});
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        await choose(tester, 'E1', '75');
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('empty pending list preserves completed and exact legacy values',
      (tester) async {
    Map<String, double>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Abrir'),
                    onPressed: () async {
                      result = await showDialog<Map<String, double>>(
                          context: context,
                          builder: (_) => ChecklistStageDialog(
                              stage: 'Implantação',
                              tasks: const [
                                {
                                  'sheet': 'Checklist',
                                  'cell': 'E1',
                                  'label': 'Legada'
                                }
                              ],
                              values: const {'Checklist!E1': .333333},
                              canApply: () => true));
                    })))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('33,33%'), findsOneWidget);
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    expect(result, {'Checklist!E1': .333333});
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await choose(tester, 'E1', '100');
    await tester.tap(find.byKey(const ValueKey('stage-pending-only')));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma tarefa pendente nesta etapa.'), findsOneWidget);
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    expect(result, {'Checklist!E1': 1});
    expect(tester.takeException(), isNull);
  });
}
