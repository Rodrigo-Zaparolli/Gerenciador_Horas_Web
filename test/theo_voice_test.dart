import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/voice.dart';
import 'package:gerenciador_horas/features/tasks/theo_voice_button.dart';
import 'package:gerenciador_horas/features/tasks/daily_hours_voice_command.dart';
import 'voice_dictation_test.dart' show FakeVoice;
import 'daily_hours_voice_command_test.dart' show entry;

void main() {
  test('name is mandatory and must address the assistant', () {
    final matcher = TheoWakeMatcher();
    for (final text in [
      'enviar horas do dia',
      'não Théo enviar horas do dia',
      'Teodoro enviar horas do dia',
      'Théo não enviar horas do dia',
      'Théo enviar horas de ontem'
    ]) {
      expect(matcher.command(text, isSendTodayHoursCommand), null);
    }
    for (final name in ['Théo', 'Theo', 'Téo', 'Teo']) {
      expect(
          matcher.command(
              '$name, enviar horas do dia.', isSendTodayHoursCommand),
          isNotNull);
    }
  });
  test('standalone name arms only the next phrase for eight seconds', () {
    var now = Duration.zero;
    final matcher = TheoWakeMatcher(elapsed: () => now);
    expect(matcher.command('Théo', isSendTodayHoursCommand), null);
    now = const Duration(seconds: 7);
    expect(matcher.command('enviar horas de hoje', isSendTodayHoursCommand),
        isNotNull);
    expect(
        matcher.command('enviar horas do dia', isSendTodayHoursCommand), null);
    matcher.command('Théo', isSendTodayHoursCommand);
    now = const Duration(seconds: 15);
    expect(
        matcher.command('enviar horas do dia', isSendTodayHoursCommand), null);
    matcher.command('Théo', isSendTodayHoursCommand);
    matcher.command('conversa sem comando', isSendTodayHoursCommand);
    expect(
        matcher.command('enviar horas do dia', isSendTodayHoursCommand), null);
    matcher.command('Théo', isSendTodayHoursCommand);
    matcher.reset();
    expect(
        matcher.command('enviar horas do dia', isSendTodayHoursCommand), null);
  });
  testWidgets(
      'opt-in wake mode ignores unrelated speech and opens review without sending',
      (tester) async {
    final clients = <FakeVoice>[];
    FakeVoice factory(VoiceEventHandler cb) {
      final c = FakeVoice(cb);
      clients.add(c);
      return c;
    }

    var loads = 0, sends = 0;
    final today = DateTime(2026, 10, 15);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyHoursVoiceCommand(
                accountKey: 'a',
                clientFactory: factory,
                clock: () => today,
                loadDay: (_) async {
                  loads++;
                  return [entry('today', today)];
                },
                onSend: (_, spokenReplies) async {
                  sends++;
                }))));
    expect(clients.any((c) => c.started), false);
    await tester.tap(find.text('Ativar Théo'));
    await tester.pump();
    final mic = clients.last;
    expect(find.text('Théo está ouvindo…'), findsOneWidget);
    mic.onEvent('final', 'enviar horas do dia');
    await tester.pump();
    expect(loads, 0);
    expect(mic.disposed, false);
    mic.onEvent('interim', 'Théo enviar horas do dia');
    await tester.pump();
    expect(loads, 0);
    mic.onEvent('final', 'Théo, enviar horas do dia');
    mic.onEvent('final', 'Théo, enviar horas do dia');
    await tester.pumpAndSettle();
    expect(mic.disposed, true);
    expect(loads, 1);
    expect(sends, 0);
    expect(find.text('Conferir horas do dia'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    mic.onEvent('final', 'Théo enviar horas do dia');
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(sends, 0);
  });
  testWidgets(
      'deactivation discards pending speech and restarting clears the name',
      (tester) async {
    final clients = <FakeVoice>[];
    final commands = <String>[];
    FakeVoice factory(VoiceEventHandler cb) {
      final c = FakeVoice(cb);
      clients.add(c);
      return c;
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TheoVoiceButton(
                sessionKey: 'a',
                clientFactory: factory,
                accepts: isSendTodayHoursCommand,
                onCommand: commands.add))));
    await tester.tap(find.text('Ativar Théo'));
    await tester.pump();
    final first = clients.last;
    first.onEvent('final', 'Théo');
    await tester.pump();
    await tester.tap(find.text('Desativar Théo'));
    await tester.pump();
    expect(first.disposed, true);
    expect(first.stopped, false);
    first.onEvent('final', 'enviar horas do dia');
    expect(commands, isEmpty);
    await tester.tap(find.text('Ativar Théo'));
    await tester.pump();
    clients.last.onEvent('final', 'enviar horas do dia');
    expect(commands, isEmpty);
    clients.last.onEvent('state', 'idle');
    await tester.pump();
    expect(find.text('Théo desativado. Ative para chamar pelo nome.'),
        findsOneWidget);
    expect(find.text('Ativar Théo'), findsOneWidget);
  });
}
