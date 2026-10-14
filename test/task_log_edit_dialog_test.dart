import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/task_log_edit_dialog.dart';

TimeLog example() => TimeLog(id: '1', targetId: '123_4', date: DateTime(2026, 10, 14),
  startTime: '13:30', endTime: '17:30', durationFormatted: '04:00', hours: 4,
  isRegistered: true, taskName: 'Original', projectId: '123');

void main() {
  testWidgets('slow storage releases editor without claiming a confirmed save', (tester) async {
    final pending = Completer<void>();
    final log = example();
    await tester.pumpWidget(MaterialApp(home: TaskLogEditDialog(log: log, save: (_) => pending.future)));
    await tester.tap(find.text('Salvar')); await tester.pump();
    await tester.pump(const Duration(seconds: 31)); await tester.pump();
    expect(find.textContaining('ainda não foi confirmado'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(log.hours, 4);
    pending.complete(); await tester.pump();
    expect(find.byType(TaskLogEditDialog), findsOneWidget);
  });
  test('formatted date supports date search and missing query', () {
    expect(example().dateFormatted, '14/10/2026');
    expect(example().dateFormatted.contains('14/10'), isTrue);
    expect(example().dateFormatted.contains('inexistente'), isFalse);
  });
  testWidgets('rejects inverted and zero intervals without saving', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: TaskLogEditDialog(log: example(), save: (_) async { calls++; })));
    final end = find.widgetWithText(TextFormField, '17:30');
    await tester.enterText(end, '12:30');
    await tester.tap(find.text('Salvar')); await tester.pump();
    expect(find.text('Término deve ser após o início.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(2), '13:30');
    await tester.tap(find.text('Salvar')); await tester.pump();
    expect(calls, 0);
  });
  testWidgets('failure preserves original and draft, disables repeated save, then retries', (tester) async {
    final log = example();
    final pending = Completer<void>();
    var calls = 0;
    TimeLog? submitted;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      child: const Text('Editar'), onPressed: () => showDialog<void>(context: context,
        builder: (_) => TaskLogEditDialog(log: log, save: (next) async {
          calls++; submitted = next;
          if (calls == 1) await pending.future;
        })),
    )))));
    await tester.tap(find.text('Editar')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Atualizado');
    await tester.enterText(find.byType(TextFormField).at(1), '8:00');
    await tester.enterText(find.byType(TextFormField).at(2), '18:30');
    await tester.tap(find.text('Salvar')); await tester.pump();
    expect(log.taskName, 'Original'); expect(log.endTime, '17:30');
    expect(submitted, isNot(same(log))); expect(submitted!.hours, 10.5);
    expect(submitted!.startTime, '08:00');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar')).onPressed, isNull);
    expect(calls, 1);
    pending.completeError(StateError('Offline')); await tester.pumpAndSettle();
    expect(find.textContaining('Não foi possível salvar'), findsOneWidget);
    expect(find.text('Atualizado'), findsOneWidget);
    expect(log.hours, 4);
    await tester.tap(find.text('Salvar')); await tester.pumpAndSettle();
    expect(calls, 2); expect(find.byType(TaskLogEditDialog), findsNothing);
    expect(submitted!.projectId, '123'); expect(submitted!.isRegistered, isTrue);
  });
}
