import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_integration.dart';

void main() {
  testWidgets('send progress stays indeterminate until counts are confirmed', (tester) async {
    edeskProgressCounts.value = (completed: 0, total: 0);
    await tester.pumpWidget(const MaterialApp(home: EdeskProgressDialog()));
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
    edeskProgressCounts.value = (completed: 3, total: 8);
    await tester.pump();
    expect(find.text('3 de 8 itens confirmados — 37%'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .375);
    edeskProgressCounts.value = (completed: 8, total: 8);
    await tester.pump();
    expect(find.text('8 de 8 itens confirmados — 100%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    edeskProgressCounts.value = (completed: 0, total: 0);
  });
}
