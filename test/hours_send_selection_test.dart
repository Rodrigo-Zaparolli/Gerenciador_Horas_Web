import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/hours_send_selection.dart';
import 'package:gerenciador_horas/features/tasks/daily_hours_voice_command.dart';
import 'voice_dictation_test.dart' show FakeVoice;

void main() {
  testWidgets('voice review forwards only the selected hours', (tester) async {
    final clients = <FakeVoice>[];
    List<TimeLog>? result;
    final day = DateTime(2026, 10, 15);
    final logs = List.generate(2, (i) => TimeLog(id: '$i', targetId: 'project-$i',
      date: day, startTime: '08:00', endTime: '09:00',
      durationFormatted: '01:00', isRegistered: true));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyHoursVoiceCommand(
      accountKey: 'owner', clock: () => day, loadDay: (_) async => logs,
      clientFactory: (callback) {
        final client = FakeVoice(callback); clients.add(client); return client;
      }, onSend: (selected, _) async { result = selected; }))));
    await tester.tap(find.text('Comando de voz'));
    await tester.pump();
    clients.last.onEvent('final', 'enviar horas do dia');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('hours-selection-0')));
    await tester.tap(find.byKey(const ValueKey('hours-selection-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e enviar'));
    await tester.pumpAndSettle();
    expect(result, [same(logs[1])]);
  });
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
