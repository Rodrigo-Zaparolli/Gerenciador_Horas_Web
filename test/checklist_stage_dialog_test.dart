import 'dart:async';
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
  testWidgets(
      'header shows only opened work immediately while Excel calculates',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: ChecklistStageDialog(
      stage: 'Implantacao',
      tasks: const [
        {'sheet': 'Checklist', 'cell': 'E1', 'label': 'Tarefa'}
      ],
      values: const {'Checklist!E1': 0},
      canApply: () => true,
      initialPreview: const {
        'rows': [
          {'label': 'Desenvolvimento', 'percentage': .99},
          {'label': 'Implantacao', 'percentage': .25},
          {'label': 'Pos-Implantacao', 'percentage': .80},
        ]
      },
      calculatePreview: (_) => pending.future,
    )));
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('99%'), findsNothing);
    expect(find.text('80%'), findsNothing);
    expect(find.text('Desenvolvimento'), findsNothing);
    final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('stage-live-progress')));
    expect(progress.value, .25);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('25%'), findsOneWidget);
    pending.complete({
      'rows': [
        {'label': 'Desenvolvimento', 'percentage': .99},
        {'label': 'Implantacao', 'percentage': .50},
      ]
    });
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('stage-live-progress')))
            .value,
        .50);
    expect(tester.takeException(), isNull);
  });

  for (final apply in [false, true]) {
    testWidgets(
        'exit is immediate and single while Excel preview is pending: $apply',
        (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      Map<String, double>? result;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('Editor principal'),
                      onPressed: () async {
                        result = await showDialog<Map<String, double>>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => ChecklistStageDialog(
                                stage: 'Implantacao',
                                tasks: const [
                                  {
                                    'sheet': 'Checklist',
                                    'cell': 'E1',
                                    'label': 'Tarefa'
                                  }
                                ],
                                values: const {'Checklist!E1': 0},
                                canApply: () => true,
                                calculatePreview: (_) => pending.future));
                      })))));
      await tester.tap(find.text('Editor principal'));
      await tester.pumpAndSettle();
      await choose(tester, 'E1', '75');
      await tester.pump(const Duration(milliseconds: 800));
      expect(pending.isCompleted, isFalse);
      final callback = apply
          ? tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Aplicar ajustes'))
              .onPressed!
          : tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
              .onPressed!;
      callback();
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistStageDialog), findsNothing);
      expect(find.text('Editor principal'), findsOneWidget);
      expect(result, apply ? {'Checklist!E1': .75} : null);
      pending.complete({
        'rows': [
          {'label': 'Implantacao', 'percentage': .75}
        ]
      });
      await tester.pumpAndSettle();
      expect(find.text('Editor principal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'bulk edits include hidden tasks, isolate blocks and skip read-only',
      (tester) async {
    Map<String, double>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  child: const Text('Open blocks'),
                  onPressed: () async {
                    result = await showDialog<Map<String, double>>(
                        context: context,
                        builder: (_) => ChecklistStageDialog(
                              stage: 'Implantacao',
                              canApply: () => true,
                              tasks: const [
                                {
                                  'sheet': 'Checklist',
                                  'cell': 'E1',
                                  'label': 'First',
                                  'block': 'Install',
                                  'blockId': 'F1'
                                },
                                {
                                  'sheet': 'Checklist',
                                  'cell': 'E2',
                                  'label': 'Completed',
                                  'block': 'Install',
                                  'blockId': 'F1'
                                },
                                {
                                  'sheet': 'Checklist',
                                  'cell': 'E3',
                                  'label': 'Locked',
                                  'block': 'Install',
                                  'blockId': 'F1',
                                  'readOnly': true
                                },
                                {
                                  'sheet': 'Checklist',
                                  'cell': 'E4',
                                  'label': 'Other',
                                  'block': 'Install',
                                  'blockId': 'F4'
                                },
                              ],
                              values: const {
                                'Checklist!E1': 0,
                                'Checklist!E2': 1,
                                'Checklist!E3': .5,
                                'Checklist!E4': .25
                              },
                            ));
                  },
                )))));
    await tester.tap(find.text('Open blocks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-pending-only')));
    await tester.pumpAndSettle();
    final block = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<double> &&
        w.key.toString().contains('stage-block-F1-'));
    await tester.tap(block);
    await tester.pumpAndSettle();
    await tester.tap(find.text('75%').last);
    await tester.pumpAndSettle();
    await choose(tester, 'E1', '25');
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    expect(result, {
      'Checklist!E1': .25,
      'Checklist!E2': .75,
      'Checklist!E3': .5,
      'Checklist!E4': .25
    });
    await tester.tap(find.text('Open blocks'));
    await tester.pumpAndSettle();
    await tester.tap(block);
    await tester.pumpAndSettle();
    await tester.tap(find.text('100%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage preview uses draft values including hidden tasks',
      (tester) async {
    Map<String, double>? calculated;
    await tester.pumpWidget(MaterialApp(
        home: ChecklistStageDialog(
      stage: 'Implantacao',
      tasks: const [
        {
          'sheet': 'Checklist',
          'cell': 'E1',
          'label': 'Task one',
          'estimated': '01:00'
        },
        {
          'sheet': 'Checklist',
          'cell': 'E2',
          'label': 'Task done',
          'estimated': '03:00'
        },
      ],
      values: const {'Checklist!E1': 0, 'Checklist!E2': 1},
      canApply: () => true,
      calculatePreview: (values) async {
        calculated = values;
        return {
          'rows': [
            {
              'label': 'Implantacao',
              'percentage':
                  (values['Checklist!E1']! + 3 * values['Checklist!E2']!) / 4
            }
          ]
        };
      },
    )));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stage-live-percentage')), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stage-pending-only')));
    await tester.pumpAndSettle();
    await choose(tester, 'E1', '100');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(calculated, {'Checklist!E1': 1, 'Checklist!E2': 1});
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Nenhuma tarefa pendente nesta etapa.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
