import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/speech.dart';
import 'package:gerenciador_horas/core/platform/voice.dart';
import 'package:gerenciador_horas/features/tasks/theo_replies.dart';
import 'package:gerenciador_horas/features/tasks/daily_hours_voice_command.dart';
import 'voice_dictation_test.dart' show FakeVoice;
import 'daily_hours_voice_command_test.dart' show entry;

class FakeSpeech implements SpeechClient {
  FakeSpeech(this.spoken);
  final List<String> spoken;
  bool disposed = false;
  int cancellations = 0;
  @override
  bool get supported => true;
  @override
  Future<bool> speak(String text) async {
    if (!disposed) spoken.add(text);
    return true;
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  for (final muted in [false, true]) {
    testWidgets(
        'send forwards the chosen spoken-result preference muted=$muted',
        (tester) async {
      final clients = <FakeVoice>[];
      FakeVoice factory(VoiceEventHandler cb) {
        final client = FakeVoice(cb);
        clients.add(client);
        return client;
      }

      bool? resultPreference;
      final today = DateTime(2026, 10, 15);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DailyHoursVoiceCommand(
                  accountKey: 'a',
                  clock: () => today,
                  clientFactory: factory,
                  loadDay: (_) async => [entry('today', today)],
                  onSend: (_, spokenReplies) async {
                    resultPreference = spokenReplies;
                  }))));
      if (muted) {
        await tester.tap(find.text('Respostas faladas'));
        await tester.pump();
      }
      await tester.tap(find.text('Ativar Théo'));
      await tester.pump();
      clients.last.onEvent('final', 'Théo enviar horas do dia');
      await tester.pumpAndSettle();
      expect(resultPreference, null);
      await tester.tap(find.text('Confirmar e enviar'));
      await tester.pumpAndSettle();
      expect(resultPreference, !muted);
    });
  }
  test('spoken totals and cancellation accept only supported review actions',
      () {
    expect(spokenHours(0), 'zero horas');
    expect(spokenHours(61), '1 hora e 1 minuto');
    expect(spokenHours(480), '8 horas');
    expect(spokenHours(30), '30 minutos');
    for (final phrase in [
      'cancelar',
      'Théo, cancelar.',
      'não enviar',
      'cancelar o envio'
    ]) {
      expect(isCancelHoursReview(phrase), true);
    }
    for (final phrase in [
      'não cancelar',
      'confirmar e enviar',
      'cancelar e enviar',
      'enviar'
    ]) {
      expect(isCancelHoursReview(phrase), false);
    }
  });
  for (final muted in [false, true]) {
    testWidgets('guided replies, review and voice cancellation, muted=$muted',
        (tester) async {
      final clients = <FakeVoice>[], speakers = <FakeSpeech>[];
      final spoken = <String>[];
      FakeVoice factory(VoiceEventHandler cb) {
        final c = FakeVoice(cb);
        clients.add(c);
        return c;
      }

      SpeechClient speechFactory() {
        final c = FakeSpeech(spoken);
        speakers.add(c);
        return c;
      }

      var sent = 0;
      final today = DateTime(2026, 10, 15);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DailyHoursVoiceCommand(
                  accountKey: 'a',
                  clientFactory: factory,
                  speechFactory: speechFactory,
                  clock: () => today,
                  loadDay: (_) async => [entry('a', today), entry('b', today)],
                  onSend: (_, spokenReplies) async {
                    sent++;
                  }))));
      if (muted) {
        await tester.tap(find.text('Respostas faladas'));
        await tester.pump();
      }
      await tester.tap(find.text('Ativar Théo'));
      await tester.pump();
      final wake = clients.last;
      wake.onEvent('final', 'Théo');
      await tester.pump();
      expect(find.text('Théo: Estou ouvindo. O que deseja fazer?'),
          findsOneWidget);
      wake.onEvent('final', 'enviar horas do dia');
      await tester.pumpAndSettle();
      expect(find.text('Conferir horas do dia'), findsOneWidget);
      expect(
          find.textContaining('Encontrei 2 apontamentos, totalizando 2 horas.'),
          findsOneWidget);
      expect(clients.last.started, true);
      expect(sent, 0);
      final review = clients.last;
      review.onEvent('final', 'confirmar e enviar');
      await tester.pumpAndSettle();
      expect(sent, 0);
      expect(find.text('Conferir horas do dia'), findsOneWidget);
      review.onEvent('final', 'cancelar');
      review.onEvent('final', 'cancelar');
      await tester.pumpAndSettle();
      expect(sent, 0);
      expect(find.text('Conferir horas do dia'), findsNothing);
      expect(find.text('Théo: Certo, nenhum apontamento foi enviado.'),
          findsOneWidget);
      expect(review.disposed, true);
      if (muted) {
        expect(spoken, isEmpty);
      } else {
        expect(spoken, contains('Estou ouvindo. O que deseja fazer?'));
        expect(
            spoken.any((text) => text.contains('totalizando 2 horas')), true);
        expect(spoken.last, 'Certo, nenhum apontamento foi enviado.');
      }
      expect(speakers.any((speaker) => speaker.disposed), true);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      expect(speakers.every((speaker) => speaker.disposed), true);
    });
  }
  testWidgets(
      'addressed unknown commands receive a reply without loading hours',
      (tester) async {
    final clients = <FakeVoice>[];
    final spoken = <String>[];
    FakeVoice factory(VoiceEventHandler cb) {
      final c = FakeVoice(cb);
      clients.add(c);
      return c;
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DailyHoursVoiceCommand(
                accountKey: 'a',
                clientFactory: factory,
                speechFactory: () => FakeSpeech(spoken),
                loadDay: (_) async => throw StateError('Should not load'),
                onSend: (_, spokenReplies) async => fail('Should not send')))));
    await tester.tap(find.text('Ativar Théo'));
    await tester.pump();
    final mic = clients.last;
    final before = spoken.length;
    mic.onEvent('final', 'conversa comum');
    await tester.pump();
    expect(spoken.length, before);
    mic.onEvent('final', 'Théo, comando inexistente');
    await tester.pump();
    expect(spoken.last, contains('Não entendi'));
    expect(find.text('Conferir horas do dia'), findsNothing);
  });
}
