import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/hours_send_selection.dart';

void main() {
  testWidgets('review with edit and delete fits a small screen', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final log = TimeLog(id: '1', targetId: '123_4', date: DateTime(2026, 10, 15),
      startTime: '08:00', endTime: '09:00', durationFormatted: '01:00',
      isRegistered: true, projectName: 'Cliente com um nome comprido para conferir');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => selectHoursForSend(context, [log],
        canSend: () => true, save: (_) async {}, delete: (_) async {}),
        child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    expect(find.byTooltip('Editar apontamento'), findsOneWidget);
    expect(find.byTooltip('Excluir apontamento'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.tap(find.text('Cancelar')); await tester.pumpAndSettle();
  });
  for (final failDelete in [false, true]) {
    testWidgets('edit then delete preserves selection; failure=$failDelete', (tester) async {
      final logs = List.generate(2, (i) => TimeLog(id: '$i', targetId: 'project-$i',
        date: DateTime(2026, 10, 15), startTime: '08:00', endTime: '09:00',
        durationFormatted: '01:00', isRegistered: true, taskName: 'Original'));
      List<TimeLog>? result;
      TimeLog? saved;
      var deletes = 0;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () async {
          result = await selectHoursForSend(context, logs, canSend: () => true,
            save: (value) async { saved = value; },
            delete: (_) async { deletes++; if (failDelete) throw Exception('offline'); });
        }, child: const Text('Open'))))));
      await tester.tap(find.text('Open')); await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar apontamento').last); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Revisada');
      await tester.enterText(find.byType(TextFormField).at(2), '10:00');
      await tester.tap(find.text('Salvar')); await tester.pumpAndSettle();
      expect(saved!.id, '1');
      expect(find.text('2 de 2 selecionado(s) · 03:00'), findsOneWidget);
      await tester.tap(find.byTooltip('Excluir apontamento').first); await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir')); await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text(failDelete ? '2 de 2 selecionado(s) · 03:00' : '1 de 1 selecionado(s) · 02:00'), findsOneWidget);
      await tester.tap(find.text('Confirmar e enviar')); await tester.pumpAndSettle();
      expect(result!.map((log) => log.id).toList(), failDelete ? ['0', '1'] : ['1']);
      expect(result!.last.endTime, '10:00');
      expect(logs[1].endTime, '09:00');
    });
  }
  testWidgets('empty selection cannot send; only checked records are returned', (tester) async {
    final logs = List.generate(2, (i) => TimeLog(id: '$i', targetId: 'project-$i',
      date: DateTime(2026, 10, 15), startTime: '08:00', endTime: '09:00',
      durationFormatted: '99:00', isRegistered: true));
    List<TimeLog>? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await selectHoursForSend(context, logs, canSend: () => true);
      }, child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 2 selecionado(s) · 02:00'), findsOneWidget);
    await tester.tap(find.text('Selecionar todas'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('hours-selection-1')));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 selecionado(s) · 01:00'), findsOneWidget);
    await tester.tap(find.text('Confirmar e enviar'));
    await tester.pumpAndSettle();
    expect(result, [same(logs[1])]);
  });
}
