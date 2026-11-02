import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/assistant/beta_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/beta_audio.dart';
import 'package:gerenciador_horas/features/assistant/beta_assistant.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

class FakeAudio implements BetaAudio {
  late void Function(String, String) event;
  final spoken = <String>[];
  int listens = 0;
  @override
  void listen(String mode) {
    listens++;
  }

  @override
  void stop() {}
  @override
  void dispose() {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  void hear(String text) => event('text', text);
}

void main() {
  for (final changed in [false, true]) {
    testWidgets(
        'visual review and explicit authorization; records changed=$changed',
        (tester) async {
      final audio = FakeAudio();
      var sends = 0, opens = 0, loads = 0;
      final now = DateTime.now();
      TimeLog log() => TimeLog(
          id: 'log',
          targetId: '2265001/3',
          date: DateTime(now.year, now.month, now.day),
          startTime: '09:00',
          endTime: changed && loads > 1 ? '10:30' : '10:00',
          durationFormatted: '01:00',
          isRegistered: true,
          projectName: 'Urban',
          taskName: 'Implantação',
          description: 'Relatórios');
      await tester.pumpWidget(MaterialApp(
          home: BetaAssistant(
              owner: 'pilot',
              accountIsCurrent: () => true,
              voiceTransport: (_) async => ' {"ready":true}',
              audioFactory: (event, transport) {
                audio.event = event;
                return audio;
              },
              loadDay: (_) async {
                loads++;
                return [log()];
              },
              openTasks: () {
                opens++;
              },
              canNavigate: () => true,
              send: (logs) async {
                sends++;
                return 'Envio confirmado';
              },
              child: Scaffold(
                  appBar: AppBar(actions: const [BetaHeaderControl()]),
                  body: const Text('Projetos')))));
      await tester.pumpAndSettle();
      expect(find.text('BETA'),findsNothing);
      await tester.tap(find.byTooltip('Ativar escuta da BETA'));
      await tester.pumpAndSettle();
      expect(find.text('BETA'),findsNothing);
      audio.hear('Olá Beta');
      await tester.pumpAndSettle();
      audio.hear('ajuda');
      await tester.pumpAndSettle();
      audio.hear('sim');
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(sends, 0);
      expect(find.text('Conferir na tela'), findsOneWidget);
      audio.hear('pode enviar');
      await tester.pumpAndSettle();
      expect(sends, 0);
      audio.hear('conferir na tela');
      await tester.pumpAndSettle();
      expect(find.textContaining('Urban'), findsOneWidget);
      audio.hear('pode enviar');
      await tester.pumpAndSettle();
      expect(sends, changed ? 0 : 1);
      if (!changed) {
        expect(find.byTooltip('Recolher BETA'), findsNothing);
        expect(audio.spoken.last, contains('só me chamar'));
      }
      if (changed) expect(audio.spoken.last, contains('mudaram'));
      audio.hear('pode enviar');
      await tester.pumpAndSettle();
      expect(sends, changed ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('account change ignores subsequent voice commands',
      (tester) async {
    final audio = FakeAudio();
    var current = true, loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: BetaAssistant(
            owner: 'pilot',
            accountIsCurrent: () => current,
            voiceTransport: (_) async => '{"ready":true}',
            audioFactory: (event, transport) {
              audio.event = event;
              return audio;
            },
            loadDay: (_) async {
              loads++;
              return [];
            },
            openTasks: () {},
            canNavigate: () => true,
            send: (_) async => null,
            child: Scaffold(
                appBar: AppBar(actions: const [BetaHeaderControl()])))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ativar escuta da BETA'));
    await tester.pumpAndSettle();
    audio.hear('Beta');
    await tester.pumpAndSettle();
    current = false;
    audio.hear('enviar horas do dia');
    await tester.pumpAndSettle();
    expect(loads, 0);
  });
}
