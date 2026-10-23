import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_stage_dialog.dart';

void main() {
  testWidgets('validates an invalid task after it scrolls out of view',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChecklistStageDialog(
      stage: 'Implantação',
      tasks: List.generate(40,
          (i) => {'sheet': 'Checklist', 'cell': 'E$i', 'label': 'Tarefa $i'}),
      values: {for (var i = 0; i < 40; i++) 'Checklist!E$i': 0},
      canApply: () => true,
    )));
    final field = find.byKey(const ValueKey('stage-percent-Checklist!E0'));
    await tester.enterText(field, '101');
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Confira o percentual de Tarefa 0.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
        'stage draft validates accepted values and cancel discards at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, double>? result;
      var closed = 0;
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
                                    'cell': 'E18',
                                    'label': 'Configurar plugins',
                                    'estimated': '02:00',
                                    'note': ''
                                  }
                                ],
                                values: const {'Checklist!E18': .333333},
                                canApply: () => true));
                        closed++;
                      })))));
      final field = find.byKey(const ValueKey('stage-percent-Checklist!E18'));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar ajustes'));
      await tester.pumpAndSettle();
      expect(result, {'Checklist!E18': .333333});
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(field, '101');
      await tester.tap(find.text('Aplicar ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('Use 0 a 100'), findsOneWidget);
      expect(closed, 1);
      await tester.enterText(field, '62,5');
      await tester.tap(find.text('Aplicar ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('Use 0, 25, 50, 75 ou 100'), findsOneWidget);
      await tester.enterText(field, '75');
      await tester.tap(find.text('Aplicar ajustes'));
      await tester.pumpAndSettle();
      expect(result, {'Checklist!E18': .75});
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(field, '100');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
