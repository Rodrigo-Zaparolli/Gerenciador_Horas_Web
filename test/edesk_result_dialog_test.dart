import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/edesk_result_dialog.dart';
import 'theo_replies_test.dart' show FakeSpeech;

void main() {
  for (final confirmed in [false, true]) {
    for (final audible in [false, true]) {
      testWidgets('authoritative result confirmed=$confirmed, audible=$audible',
          (tester) async {
        final spoken = <String>[];
        final speaker = FakeSpeech(spoken);
        await tester.pumpWidget(MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => EdeskResultDialog(
                                confirmed: confirmed,
                                message: 'Detalhes da integração',
                                completeProgress: true,
                                spokenHoursResult: audible,
                                speechFactory: () => speaker)),
                        child: const Text('Resultado'))))));
        expect(spoken, isEmpty);
        await tester.tap(find.text('Resultado'));
        await tester.pumpAndSettle();
        expect(
            find.text(confirmed ? 'Envio concluído' : 'Envio não confirmado'),
            findsOneWidget);
        expect(find.text('Detalhes da integração'), findsOneWidget);
        expect(find.text('100% — envio confirmado'),
            confirmed ? findsOneWidget : findsNothing);
        expect(spoken, audible ? [hoursCompletionReply(confirmed)] : isEmpty);
        if (audible) {
          await tester.tap(find.text('Silenciar Théo'));
          await tester.pump();
          expect(speaker.cancellations, greaterThan(0));
          expect(find.text('Théo: ${hoursCompletionReply(confirmed)}'),
              findsOneWidget);
        }
        await tester.pump();
        expect(spoken.length, audible ? 1 : 0);
        await tester.tap(find.text('Entendi'));
        await tester.pumpAndSettle();
        expect(speaker.disposed, true);
        expect(tester.takeException(), null);
      });
    }
  }
  testWidgets('changed account suppresses the spoken result', (tester) async {
    final spoken = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: EdeskResultDialog(
            confirmed: true,
            message: 'Resultado',
            spokenHoursResult: true,
            canSpeak: () => false,
            speechFactory: () => FakeSpeech(spoken))));
    await tester.pumpAndSettle();
    expect(spoken, isEmpty);
  });
}
