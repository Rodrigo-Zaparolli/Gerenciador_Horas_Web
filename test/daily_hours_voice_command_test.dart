import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/voice.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/daily_hours_voice_command.dart';
import 'voice_dictation_test.dart' show FakeVoice;

TimeLog entry(String id, DateTime day, {bool registered = true}) => TimeLog(
    id: id,
    targetId: '226144_1',
    date: day,
    startTime: '08:00',
    endTime: '09:00',
    durationFormatted: '01:00',
    isRegistered: registered,
    projectName: 'Projeto Orquinare',
    taskName: 'Implantação',
    description: 'Treinamento');

void main() {
  test('review total matches submitted clock times instead of stale durations',
      () {
    final log = entry('today', DateTime(2026, 10, 15));
    log.durationFormatted = '99:00';
    expect(dayHoursMinutes(log), 60);
    log.endTime = '07:00';
    expect(dayHoursMinutes(log), 0);
  });
  testWidgets('long day stays scrollable on a small screen', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final clients = <FakeVoice>[];
    FakeVoice factory(VoiceEventHandler cb) {
      final c = FakeVoice(cb);
      clients.add(c);
      return c;
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyHoursVoiceCommand(
                accountKey: 'a',
                clock: () => DateTime(2026, 10, 15),
                clientFactory: factory,
                loadDay: (_) async => List.generate(
                    30, (i) => entry('$i', DateTime(2026, 10, 15))),
                onSend: (_, spokenReplies) async =>
                    fail('Must not send without confirmation')))));
    await tester.tap(find.text('Comando de voz'));
    await tester.pump();
    clients.last.onEvent('final', 'enviar horas do dia');
    await tester.pumpAndSettle();
    expect(find.text('15/10/2026 · 30 apontamento(s) · 30:00'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), null);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
  test('only explicit supported commands may prepare a send', () {
    expect(isSendTodayHoursCommand('Enviar horas do dia.'), true);
    expect(isSendTodayHoursCommand('  ENVIAR   AS HORAS DE HOJE! '), true);
    for (final phrase in [
      'não enviar horas do dia',
      'enviar horas de ontem',
      'enviar horas do dia e excluir tudo',
      'enviar',
      'confirmar e enviar'
    ]) {
      expect(isSendTodayHoursCommand(phrase), false);
    }
  });
  for (final confirm in [false, true]) {
    testWidgets('today-only review, stopped microphone, confirmation=$confirm',
        (tester) async {
      final clients = <FakeVoice>[];
      FakeVoice factory(VoiceEventHandler cb) {
        final c = FakeVoice(cb);
        clients.add(c);
        return c;
      }

      final sent = <List<TimeLog>>[];
      final day = DateTime(2026, 10, 15);
      DateTime? requested;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DailyHoursVoiceCommand(
                  accountKey: 'a',
                  clock: () => day,
                  clientFactory: factory,
                  loadDay: (date) async {
                    requested = date;
                    return [
                      entry('today', day),
                      entry('yesterday', day.subtract(const Duration(days: 1))),
                      entry('running', day, registered: false)
                    ];
                  },
                  onSend: (logs, spokenReplies) async => sent.add(logs)))));
      expect(clients.any((c) => c.started), false);
      await tester.tap(find.text('Comando de voz'));
      await tester.pump();
      final mic = clients.last;
      mic.onEvent('interim', 'enviar horas do dia');
      await tester.pump();
      expect(requested, null);
      mic.onEvent('final', 'enviar horas do dia');
      mic.onEvent('final', 'enviar horas do dia');
      await tester.pumpAndSettle();
      expect(mic.disposed, true);
      expect(requested, day);
      expect(find.text('Conferir horas do dia'), findsOneWidget);
      expect(
          find.text('15/10/2026 · 1 apontamento(s) · 01:00'), findsOneWidget);
      expect(sent, isEmpty);
      await tester.tap(find.text(confirm ? 'Confirmar e enviar' : 'Cancelar'));
      await tester.pumpAndSettle();
      expect(sent.length, confirm ? 1 : 0);
      if (confirm) expect(sent.single.map((log) => log.id), ['today']);
      mic.onEvent('final', 'enviar horas do dia');
      await tester.pumpAndSettle();
      expect(find.text('Conferir horas do dia'), findsNothing);
      expect(tester.takeException(), null);
    });
  }
  for (final outcome in ['empty', 'error', 'unknown', 'account', 'disabled']) {
    testWidgets('no send for $outcome', (tester) async {
      final clients = <FakeVoice>[];
      FakeVoice factory(VoiceEventHandler cb) {
        final c = FakeVoice(cb);
        clients.add(c);
        return c;
      }

      final pending = Completer<List<TimeLog>>();
      var sends = 0, loads = 0;
      String owner = 'a';
      var enabled = true;
      late StateSetter change;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (context, set) {
        change = set;
        return DailyHoursVoiceCommand(
            accountKey: owner,
            enabled: enabled,
            clock: () => DateTime(2026, 10, 15),
            clientFactory: factory,
            loadDay: (_) {
              loads++;
              return pending.future;
            },
            onSend: (_, spokenReplies) async {
              sends++;
            });
      }))));
      await tester.tap(find.text('Comando de voz'));
      await tester.pump();
      clients.last.onEvent(
          'final',
          outcome == 'unknown'
              ? 'não enviar horas do dia'
              : 'enviar horas do dia');
      await tester.pump();
      await tester.pump();
      if (outcome == 'account') {
        change(() => owner = 'b');
        await tester.pump();
      }
      if (outcome == 'disabled') {
        change(() => enabled = false);
        await tester.pump();
      }
      if (outcome == 'error') {
        pending.completeError(StateError('offline'));
      } else {
        pending.complete(
            outcome == 'empty' ? [] : [entry('today', DateTime(2026, 10, 15))]);
      }
      await tester.pumpAndSettle();
      expect(sends, 0);
      expect(loads, outcome == 'unknown' ? 0 : 1);
      expect(find.text('Confirmar e enviar'), findsNothing);
      expect(tester.takeException(), null);
    });
  }
}
